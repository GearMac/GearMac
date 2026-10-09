// 文件职责：扩展的本地持久化存储（LocalStorage / Cache / Preferences / 搜索栏下拉值），每个扩展一个 JSON 文件。
// 分层：Service；@MainActor 隔离，写入合并后延迟落盘；解码失败时按空 Store 处理，不因单个 key 丢掉整个扩展数据。
import Foundation

/// 每个扩展一个 JSON 文件：体积小、启动时整体读取、很少写入。
@MainActor
final class ExtensionStorage {
    private struct Store: Codable {
        var localStorage: [String: StoredValue] = [:]
        var caches: [String: [String: String]] = [:]
        var preferences: [String: StoredValue] = [:]
        /// 搜索栏下拉框的 `storeValue` 选项——属于宿主 UI 状态，因此不属于 `LocalStorage`。
        var accessoryValues: [String: String] = [:]

        enum CodingKeys: String, CodingKey {
            case localStorage, caches, preferences, accessoryValues
        }

        init() {}

        /// 各分区各自解码：缺失一个 key 不能连带弄丢整个扩展的存储（包括 API key），
        /// 因为解码一失败整个文件就会被重置。
        init(from decoder: Decoder) throws {
            let store = try decoder.container(keyedBy: CodingKeys.self)
            localStorage =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .localStorage) ?? [:]
            caches =
                try store.decodeIfPresent([String: [String: String]].self, forKey: .caches) ?? [:]
            preferences =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .preferences) ?? [:]
            accessoryValues =
                try store.decodeIfPresent([String: String].self, forKey: .accessoryValues) ?? [:]
        }
    }

    /// `LocalStorage` 接受字符串、数字和布尔值，并且必须按原类型返回。
    enum StoredValue: Codable, Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)

        /// 转换为可直接 JSON 序列化的值。
        var jsonValue: Any {
            switch self {
            case .string(let value): return value
            case .number(let value): return value
            case .bool(let value): return value
            }
        }

        /// 从渲染层值构造；非标量类型（null/数组/对象）返回 nil。
        init?(renderValue: RenderValue) {
            switch renderValue {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            default: return nil
            }
        }

        /// 从扩展偏好值构造；`application` 类型以路径字符串存储。
        init(preference: ExtensionPreferenceValue) {
            switch preference {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            case .application(let path): self = .string(path)
            }
        }

        /// 转换回扩展偏好值。
        var preferenceValue: ExtensionPreferenceValue {
            switch self {
            case .string(let value): return .string(value)
            case .number(let value): return .number(value)
            case .bool(let value): return .bool(value)
            }
        }
    }

    private let directory: URL
    private var stores: [String: Store] = [:]
    /// 写入会被合并，使频繁读写的 `Cache` 不会每个 key 都访问磁盘。
    private var dirty: Set<String> = []
    private var flushTask: Task<Void, Never>?

    /// 指定存储目录并确保它存在。
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - LocalStorage

    /// 读取指定扩展的单个 `LocalStorage` 值。
    func localStorageValue(extension name: String, key: String) -> StoredValue? {
        store(for: name).localStorage[key]
    }

    /// 读取指定扩展的完整 `LocalStorage` 字典。
    func allLocalStorage(extension name: String) -> [String: StoredValue] {
        store(for: name).localStorage
    }

    func setLocalStorage(extension name: String, key: String, value: StoredValue) {
        mutate(name) { $0.localStorage[key] = value }
    }

    func removeLocalStorage(extension name: String, key: String) {
        mutate(name) { $0.localStorage.removeValue(forKey: key) }
    }

    func clearLocalStorage(extension name: String) {
        mutate(name) { $0.localStorage.removeAll() }
    }

    // MARK: - Search-bar dropdowns

    /// 读取搜索栏下拉框当前选项。
    func accessoryValue(extension name: String, key: String) -> String? {
        store(for: name).accessoryValues[key]
    }

    func setAccessoryValue(extension name: String, key: String, value: String) {
        mutate(name) { $0.accessoryValues[key] = value }
    }

    // MARK: - Cache

    /// 读取指定扩展的全部缓存命名空间。
    func caches(extension name: String) -> [String: [String: String]] {
        store(for: name).caches
    }

    /// `nil` 值的 key 表示删除该键；`nil` 的 key 表示清空整个命名空间。
    func setCache(extension name: String, namespace: String, key: String?, value: String?) {
        mutate(name) { store in
            guard let key else {
                store.caches[namespace] = [:]
                return
            }
            var bucket = store.caches[namespace] ?? [:]
            if let value { bucket[key] = value } else { bucket.removeValue(forKey: key) }
            store.caches[namespace] = bucket
        }
    }

    func clearCache(extension name: String, namespace: String) {
        mutate(name) { $0.caches[namespace] = [:] }
    }

    // MARK: - Preferences

    /// 读取单个偏好项的用户值（未设置时返回 nil）。
    func preference(extension name: String, key: String) -> ExtensionPreferenceValue? {
        store(for: name).preferences[key]?.preferenceValue
    }

    func setPreference(extension name: String, key: String, value: ExtensionPreferenceValue?) {
        mutate(name) { store in
            if let value {
                store.preferences[key] = StoredValue(preference: value)
            } else {
                store.preferences.removeValue(forKey: key)
            }
        }
    }

    /// 以 Manifest 默认值叠加用户设置——即 `getPreferenceValues()` 看到的内容。
    func resolvedPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [String: ExtensionPreferenceValue] {
        var resolved: [String: ExtensionPreferenceValue] = [:]
        for schema in schemas {
            resolved[schema.name] = schema.runtimeValue(preference(extension: name, key: schema.name))
        }
        return resolved
    }

    /// 带有未设置的必填偏好的命令不得运行。
    func missingRequiredPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [ExtensionPreferenceSchema] {
        schemas.filter { schema in
            guard schema.required else { return false }
            let value = preference(extension: name, key: schema.name) ?? schema.effectiveDefault
            if case .string(let text) = value { return text.isEmpty }
            return false
        }
    }

    /// 删除指定扩展的全部数据（内存缓存与磁盘文件）。
    func removeAll(extension name: String) {
        stores.removeValue(forKey: name)
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    // MARK: - Persistence

    /// 获取指定扩展的内存 Store，未加载时从磁盘读取；读取失败则回退为空 Store。
    private func store(for name: String) -> Store {
        if let existing = stores[name] { return existing }
        let loaded =
            (try? Data(contentsOf: fileURL(for: name)))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        stores[name] = loaded
        return loaded
    }

    /// 在内存中修改 Store 并标记为脏，交给合并调度器落盘。
    private func mutate(_ name: String, _ body: (inout Store) -> Void) {
        var current = store(for: name)
        body(&current)
        stores[name] = current
        dirty.insert(name)
        scheduleFlush()
    }

    /// 启动延迟落盘任务（仅当尚无待处理任务时）。
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }

    /// 立即将所有脏 Store 原子写入磁盘。
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        let pending = dirty
        dirty.removeAll()
        for name in pending {
            guard let store = stores[name], let data = try? JSONEncoder().encode(store) else { continue }
            try? data.write(to: fileURL(for: name), options: .atomic)
        }
    }

    /// 根据扩展名生成对应的存储文件 URL（文件名经过安全化处理）。
    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent("\(ExtensionCatalog.safeName(name)).json")
    }
}
