// 文件职责：管理用户自建快捷动作的持久化存储（读写 quick-actions.json）与增删改编排。
// 分层：Model；仅当文件读取失败时标记不可用，之后所有写操作拒绝执行而不伪装成功。
import Foundation

@MainActor
@Observable
final class CustomQuickActionStore {
    private(set) var actions: [CustomQuickAction] = []
    /// 文件无法读取时为 false；此后每个修改操作都拒绝执行，而不会假装成功。
    private(set) var isAvailable = true
    @ObservationIgnored var onChange: (([CustomQuickAction]) -> Void)?

    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("quick-actions.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    /// 加载磁盘上的动作列表；文件不存在则保持现状。
    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // 文件存在却读不出来，说明是用户手写的数据：报告异常，绝不覆写。
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([CustomQuickAction].self, from: data)
        else {
            isAvailable = false
            return
        }
        actions = Self.sanitized(decoded)
    }

    func action(id: UUID) -> CustomQuickAction? {
        actions.first { $0.id == id }
    }

    func action(entryID: String) -> CustomQuickAction? {
        CustomQuickAction.id(fromEntryID: entryID).flatMap(action)
    }

    /// 新增一个自建动作，校验并落盘后返回规范化后的值。
    @discardableResult
    func add(_ draft: CustomQuickAction) throws(CustomQuickActionError) -> CustomQuickAction {
        let value = try validated(draft)
        try commit(actions + [value])
        return value
    }

    /// 更新同 id 的自建动作；未找到则静默返回。
    func update(_ draft: CustomQuickAction) throws(CustomQuickActionError) {
        guard let index = actions.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = actions
        updated[index] = value
        try commit(updated)
    }

    /// 删除指定 id 的自建动作，返回被删除的项；未找到则返回 nil。
    @discardableResult
    func remove(id: UUID) throws(CustomQuickActionError) -> CustomQuickAction? {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = actions
        let removed = updated.remove(at: index)
        try commit(updated)
        return removed
    }

    /// 只切换某个动作的“是否预览结果”开关。
    func setPreviewsResult(
        _ previews: Bool, id: UUID
    ) throws(CustomQuickActionError) {
        guard var value = action(id: id), value.previewsResult != previews else { return }
        value.previewsResult = previews
        try update(value)
    }

    /// 去除首尾空白、校验非空与合法字符，返回可供持久化的副本。
    private func validated(
        _ draft: CustomQuickAction
    ) throws(CustomQuickActionError) -> CustomQuickAction {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol =
            draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        value.instructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.instructions.isEmpty else { throw .emptyInstructions }
        return value
    }

    /// 先落盘再更新内存列表，以读到的“保存成功”确实已在磁盘上。
    private func commit(_ updated: [CustomQuickAction]) throws(CustomQuickActionError) {
        guard isAvailable else { throw .storageUnavailable }
        let ordered = updated.sorted(by: CustomQuickAction.precedes)
        guard ordered != actions else { return }
        try persist(ordered)
        actions = ordered
        onChange?(ordered)
    }

    /// 将动作列表按稳定顺序原子写入 JSON 文件。
    private func persist(_ values: [CustomQuickAction]) throws(CustomQuickActionError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values),
            (try? data.write(to: fileURL, options: .atomic)) != nil
        else { throw .storageUnavailable }
    }

    /// 清洗磁盘读入的数据：去空白、丢弃非法字符/空字段与重复 id，并重新排序。
    private static func sanitized(_ values: [CustomQuickAction]) -> [CustomQuickAction] {
        var ids = Set<UUID>()
        var result: [CustomQuickAction] = []
        for value in values {
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.iconSymbol =
                value.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            cleaned.instructions = value.instructions.trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"),
                !cleaned.instructions.isEmpty, ids.insert(cleaned.id).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: CustomQuickAction.precedes)
    }
}

extension String {
    /// 空字符串返回 nil，否则返回自身（用于可选字段的去空白归一）。
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
