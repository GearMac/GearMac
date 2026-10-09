// 文件职责：把 settings.json 中记录的启动器条目（应用、设置面板、系统动作、内置命令）与内存中的别名/可见性/快捷键状态双向同步。
// 分层：Service（设置文件读写适配层）；@MainActor 隔离，某个键读失败时返回 issue 而不影响其他键。
import Foundation

/// settings.json 中记录的启动器条目：每个应用、面板、系统动作与内置命令对应一条记录。
@MainActor
final class LauncherSettingsFile {
    private typealias Record = LauncherFileFormat.Record

    /// 区分应用与设置面板两类 bundle，统一其 kind、名称与热键动作的差异。
    private enum Bundle {
        case app, pane

        var kind: AppEntry.Kind { self == .app ? .application : .systemSettings }
        var noun: String { self == .app ? "app" : "settings pane" }

        func action(_ bundleID: String) -> HotKeyAction {
            self == .app ? .app(bundleID: bundleID) : .settingsPane(bundleID: bundleID)
        }
    }

    /// 单个启动器条目的最小描述：名称、偏好键与可选热键动作。
    private struct Item {
        let name: String
        let preferenceKey: String
        let action: HotKeyAction?
    }

    /// 某个设置键下已应用与排队等待识别的 bundle 记录。
    private struct BundleRecords {
        let bundle: Bundle
        var applied: Set<String> = []
        var waiting: [String: Record] = [:]
    }

    private let appIndex: AppIndex
    private let aliases: AliasStore
    private let visibility: VisibilityStore
    private let shortcuts: HotKeySettingsFile
    private var bundleRecords: [SettingsFileKey: BundleRecords] = [:]

    /// 注入索引、别名、可见性与快捷键存储，作为读写设置文件的依赖。
    init(
        appIndex: AppIndex, aliases: AliasStore, visibility: VisibilityStore,
        shortcuts: HotKeySettingsFile
    ) {
        self.appIndex = appIndex
        self.aliases = aliases
        self.visibility = visibility
        self.shortcuts = shortcuts
    }

    /// 返回应用列表对应的 settings.json 绑定。
    func appsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        bundlesBinding(for: key, .app)
    }

    /// 返回系统设置面板列表对应的 settings.json 绑定。
    func panesBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        bundlesBinding(for: key, .pane)
    }

    /// 返回系统动作列表对应的 settings.json 绑定。
    func systemActionsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        let items = SystemActionCatalog.all.map { action in
            Item(
                name: action.id.rawValue, preferenceKey: action.entryID,
                action: .systemAction(id: action.id))
        }
        return catalogBinding(for: key, items: items, noun: "system action")
    }

    /// `owner` 所拥有的内置命令；nil 表示 Commands 面板自身拥有的命令。
    func commandsBinding(for key: SettingsFileKey, owner: SettingsTab?) -> SettingsFileBinding {
        let items = CommandID.allCases.filter { $0.owner == owner && !$0.isQueryDriven }.map { id in
            Item(
                name: String(id.rawValue.drop { $0 != ":" }.dropFirst()), preferenceKey: id.rawValue,
                action: id.hotKeyAction)
        }
        return catalogBinding(for: key, items: items, noun: "command")
    }

    /// 返回某个 kind 整体启用状态的 settings.json 绑定（对应分类开关）。
    func kindBinding(for key: SettingsFileKey, kind: AppEntry.Kind) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [visibility] in .bool(visibility.isKindEnabled(kind)) },
            write: { [visibility] json in
                guard let enabled = json.bool else { return [.invalidValue(key)] }
                visibility.setKindEnabled(enabled, for: kind)
                return []
            })
    }

    /// 应用已经能识别的待处理记录（如新安装的应用），并汇总快捷键提交结果。
    func applyInstalled() -> [SettingsFileIssue] {
        var issues: [SettingsFileIssue] = []
        for (key, var held) in bundleRecords {
            guard !held.waiting.isEmpty else { continue }
            let known = knownBundleIDs(held.bundle)
            let ready = held.waiting.filter { known.contains($0.key) }
            guard !ready.isEmpty else { continue }
            held.applied.formUnion(ready.keys)
            for name in ready.keys { held.waiting[name] = nil }
            bundleRecords[key] = held
            let items = ready.keys.sorted().map { item($0, held.bundle) }
            issues += apply(ready, to: items, noun: held.bundle.noun, key: key)
        }
        return issues + shortcuts.commit()
    }

    // MARK: - Bindings

    /// 为固定目录（系统动作、内置命令）构建读写绑定：不属该分组的名称会报错。
    private func catalogBinding(
        for key: SettingsFileKey, items: [Item], noun: String
    ) -> SettingsFileBinding {
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        return SettingsFileBinding(
            key,
            read: { [self] in LauncherFileFormat.json(customized(items)) },
            write: { [self] json in
                let spelling = shortcuts.spelling
                let read = LauncherFileFormat.records(from: json) { name in
                    byName[name].map { record(of: $0, spelling) } ?? Record()
                }
                guard let decoded = read else { return [.invalidValue(key)] }
                let unknown = decoded.records.keys.filter { byName[$0] == nil }.sorted().map {
                    SettingsFileIssue.invalidEntry(key, "no \(noun) in this section is called “\($0)”")
                }
                return decoded.problems.map { .invalidEntry(key, $0) } + unknown
                    + apply(decoded.records, to: items, noun: noun, key: key)
            })
    }

    /// 为应用/面板类 bundle 构建读写绑定；当前系统中尚未出现的 bundle 先暂存等待识别。
    private func bundlesBinding(for key: SettingsFileKey, _ bundle: Bundle) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [self] in
                let state = bundleRecords[key]
                let known = knownBundleIDs(bundle).union(state?.applied ?? [])
                let live = customized(known.map { item($0, bundle) })
                let liveNames = Set(live.map(\.name))
                let held = (state?.waiting ?? [:]).filter { !liveNames.contains($0.key) }
                let records = live + held.map { (name: $0.key, record: $0.value) }
                return LauncherFileFormat.json(records.sorted { $0.name < $1.name })
            },
            write: { [self] json in
                let previous = bundleRecords[key]
                let spelling = shortcuts.spelling
                let read = LauncherFileFormat.records(from: json) { name in
                    previous?.waiting[name] ?? record(of: item(name, bundle), spelling)
                }
                guard let decoded = read else { return [.invalidValue(key)] }
                let known = knownBundleIDs(bundle).union(previous?.applied ?? [])
                let present = decoded.records.filter { known.contains($0.key) }
                bundleRecords[key] = BundleRecords(
                    bundle: bundle, applied: Set(present.keys),
                    waiting: decoded.records.filter { !known.contains($0.key) })
                let live = customized(known.map { item($0, bundle) }).map(\.name)
                let items = Set(live).union(present.keys).sorted().map { item($0, bundle) }
                return decoded.problems.map { .invalidEntry(key, $0) }
                    + apply(present, to: items, noun: bundle.noun, key: key)
            })
    }

    // MARK: - Items

    /// 由 bundle id 构造条目描述。
    private func item(_ bundleID: String, _ bundle: Bundle) -> Item {
        Item(name: bundleID, preferenceKey: bundleID, action: bundle.action(bundleID))
    }

    /// 设置界面列出的全部 id，外加虽在搜索范围外但已绑定快捷键的应用，后者保留其快捷键。
    private func knownBundleIDs(_ bundle: Bundle) -> Set<String> {
        let hotKeys = shortcuts.hotKeys
        var bundleIDs = Set(bundle == .app ? hotKeys.boundBundleIDs : hotKeys.boundPaneBundleIDs)
        for entry in appIndex.apps where entry.kind == bundle.kind {
            if let bundleID = entry.bundleID { bundleIDs.insert(bundleID) }
        }
        return bundleIDs
    }

    /// 由条目当前状态构造一条 settings.json 记录。
    private func record(of item: Item, _ spelling: HotKeySpelling) -> Record {
        Record(
            shortcut: item.action.flatMap { shortcuts.text(for: $0, spelling) },
            alias: aliases.alias(for: item.preferenceKey),
            showInLauncher: visibility.isItemVisible(key: item.preferenceKey))
    }

    /// 仅保留字段非空的条目，非空才需要写入文件。
    private func customized(_ items: [Item]) -> [(name: String, record: Record)] {
        let spelling = shortcuts.spelling
        return items.compactMap { item in
            let record = self.record(of: item, spelling)
            return record.isEmpty ? nil : (item.name, record)
        }
    }

    /// 记录中缺失的条目按空记录处理，因此文件中删除的行会清空对应设置项。
    private func apply(
        _ records: [String: Record], to items: [Item], noun: String, key: SettingsFileKey
    ) -> [SettingsFileIssue] {
        var issues: [SettingsFileIssue] = []
        var wanted: [HotKeySettingsFile.Wanted] = []
        for item in items {
            let record = records[item.name] ?? Record()
            aliases.setAlias(record.alias ?? "", for: item.preferenceKey)
            visibility.setItemVisible(record.showInLauncher, forKey: item.preferenceKey)
            let label = "\(noun) “\(item.name)”"
            if let action = item.action {
                wanted.append(HotKeySettingsFile.Wanted(action: action, text: record.shortcut, label: label))
            } else if record.shortcut != nil {
                issues.append(.invalidEntry(key, "\(label) can't have a shortcut"))
            }
        }
        return issues + shortcuts.apply(wanted, key: key)
    }
}
