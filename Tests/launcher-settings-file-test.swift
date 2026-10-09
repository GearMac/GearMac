// 文件职责：验证 LauncherSettingsFile 对应用、系统设置面板、命令等分区的 settings.json 记录写入、校验与安装后回填行为。
// 分层：测试 harness；用内存版索引与热键存储替代真实实现，不触碰用户配置与 Carbon 注册。
import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// 覆盖 LauncherSettingsFile 的分区写回、非法记录保留、等待记录与跨分区快捷键迁移的测试 harness。
@main
@MainActor
struct LauncherSettingsFileTest {
    private static var failures = 0
    private static let chord = HotKeyBinding.combo(
        KeyShortcut(carbonKeyCode: kVK_ANSI_V, carbonModifiers: cmdKey | shiftKey))
    private static let chordText = "cmd+shift+key-\(kVK_ANSI_V)"
    private static let bundleID = "com.example.launcher-file-test"

    /// harness 入口：依次运行全部用例并以失败数决定退出码。
    static func main() {
        testInvalidRecords()
        testOutsideScopes()
        testWaitingRecords()
        testDeletedWaitingRecord()
        testMovedShortcut()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// 校验非法记录被拒绝且不覆盖已有快捷键、别名与可见性状态。
    private static func testInvalidRecords() {
        let fixture = Fixture()
        let action = HotKeyAction.command(.clipboardHistory)
        let key = CommandID.clipboardHistory.rawValue
        fixture.hotKeys.setBinding(chord, for: action)
        fixture.aliases.setAlias("ch", for: key)
        fixture.visibility.setItemVisible(false, forKey: key)
        let aliasRevision = fixture.aliases.revision
        let visibilityRevision = fixture.visibility.revision
        let binding = fixture.file.commandsBinding(for: .clipboardCommands, owner: .clipboard)

        let invalid = binding.write(.object(["clipboard-history": chordText.settingsJSON]))
        check("a non-object record is reported", invalid.count == 1)
        check("the existing shortcut survives", fixture.hotKeys.binding(for: action) == chord)
        check("the existing alias survives", fixture.aliases.alias(for: key) == "ch")
        check("the item stays hidden", !fixture.visibility.isItemVisible(key: key))
        check(
            "preserving a record does not publish unchanged values",
            fixture.aliases.revision == aliasRevision && fixture.visibility.revision == visibilityRevision)

        let fields = binding.write(
            .object([
                "clipboard-history": .object(["shortcut": 5, "alias": true, "showInLauncher": "no"])
            ]))
        check("invalid fields are reported", fields.count == 3)
        check("invalid fields preserve the shortcut", fixture.hotKeys.binding(for: action) == chord)
        check("invalid fields preserve the alias", fixture.aliases.alias(for: key) == "ch")
        check("invalid fields preserve visibility", !fixture.visibility.isItemVisible(key: key))

        check(
            "a partial edit applies",
            binding.write(
                .object([
                    "clipboard-history": .object(["alias": "history"])
                ])
            ).isEmpty)
        check("the shortcut stays put", fixture.hotKeys.binding(for: action) == chord)
        check("the alias changes", fixture.aliases.alias(for: key) == "history")

        check("deleting a record applies", binding.write(.object([])).isEmpty)
        check("deletion clears its shortcut", fixture.hotKeys.binding(for: action) == nil)
        check("deletion clears its alias", fixture.aliases.alias(for: key) == nil)
        check("deletion restores visibility", fixture.visibility.isItemVisible(key: key))
    }

    /// 校验已移出当前分区的记录（如卸载的应用）仍能被编辑与删除。
    private static func testOutsideScopes() {
        let fixture = Fixture()
        let action = HotKeyAction.app(bundleID: bundleID)
        fixture.hotKeys.setBinding(chord, for: action)
        fixture.aliases.setAlias("outside", for: bundleID)
        fixture.visibility.setItemVisible(false, forKey: bundleID)
        let binding = fixture.file.appsBinding(for: .applications)

        check(
            "clearing the last shortcut applies",
            binding.write(
                .object([
                    bundleID: .object(["shortcut": .null])
                ])
            ).isEmpty)
        check("there is no shortcut to commit", fixture.shortcuts.commit().isEmpty)
        check("the app is unbound", fixture.hotKeys.binding(for: action) == nil)
        let saved = binding.read()[bundleID]
        check("its record still renders", saved != nil)
        check("its alias still renders", saved?["alias"] == "outside")
        check("its hidden state still renders", saved?["showInLauncher"] == false)

        check(
            "a partial edit still finds the app",
            binding.write(
                .object([
                    bundleID: .object(["alias": "renamed"])
                ])
            ).isEmpty)
        check("the new alias applies", fixture.aliases.alias(for: bundleID) == "renamed")
        check("a scan keeps that record", fixture.file.applyInstalled().isEmpty)
        check("a scan does not restore the cleared shortcut", fixture.hotKeys.binding(for: action) == nil)

        check("deleting the retained record applies", binding.write(.object([])).isEmpty)
        check("deletion clears its alias", fixture.aliases.alias(for: bundleID) == nil)
        check("deletion restores visibility", fixture.visibility.isItemVisible(key: bundleID))
        check("the deleted record no longer renders", binding.read()[bundleID] == nil)
    }

    /// 校验尚未安装的应用记录先被保留，待扫描发现后再应用。
    private static func testWaitingRecords() {
        let fixture = Fixture()
        let binding = fixture.file.appsBinding(for: .applications)
        let record: SettingsFileJSON = .object([
            "shortcut": chordText.settingsJSON, "alias": "later", "showInLauncher": true
        ])
        check("an unknown app's record is accepted", binding.write(.object([bundleID: record])).isEmpty)
        check("waiting records bind nothing", fixture.shortcuts.commit().isEmpty)
        check("waiting records apply no alias", fixture.aliases.alias(for: bundleID) == nil)

        check(
            "a waiting record accepts a partial edit",
            binding.write(
                .object([
                    bundleID: .object(["showInLauncher": false])
                ])
            ).isEmpty)
        let saved = binding.read()[bundleID]
        check("the waiting shortcut is preserved", saved?["shortcut"] == chordText.settingsJSON)
        check("the waiting alias is preserved", saved?["alias"] == "later")
        check("the waiting visibility changes", saved?["showInLauncher"] == false)
        check("a malformed waiting record is reported", binding.write(.object([bundleID: false])).count == 1)
        check("a malformed waiting record keeps its values", binding.read()[bundleID] == saved)

        fixture.index.apps = [entry(bundleID, kind: .application)]
        check("the first scan applies the waiting record", fixture.file.applyInstalled().isEmpty)
        check("the shortcut is bound", fixture.hotKeys.binding(for: .app(bundleID: bundleID)) == chord)
        check("the alias is applied", fixture.aliases.alias(for: bundleID) == "later")
        check("the app is hidden", !fixture.visibility.isItemVisible(key: bundleID))
        fixture.aliases.setAlias("edited in app", for: bundleID)
        check("a second scan has nothing to apply", fixture.file.applyInstalled().isEmpty)
        check(
            "a second scan does not replay the file", fixture.aliases.alias(for: bundleID) == "edited in app")

        fixture.index.apps = []
        fixture.hotKeys.setBinding(nil, for: .app(bundleID: bundleID))
        check(
            "a previously applied record stays in the mirror",
            binding.read()[bundleID]?["alias"] == "edited in app")
    }

    /// 校验删除等待中的记录后，后续扫描不会重新应用它。
    private static func testDeletedWaitingRecord() {
        let fixture = Fixture()
        let binding = fixture.file.panesBinding(for: .systemSettings)
        check(
            "a waiting pane's record is accepted",
            binding.write(
                .object([
                    bundleID: .object(["shortcut": chordText.settingsJSON, "alias": "pane"])
                ])
            ).isEmpty)
        check("deleting a waiting record applies", binding.write(.object([])).isEmpty)
        fixture.index.apps = [entry(bundleID, kind: .systemSettings)]
        check("a deleted waiting record is not applied", fixture.file.applyInstalled().isEmpty)
        check(
            "the pane stays unbound", fixture.hotKeys.binding(for: .settingsPane(bundleID: bundleID)) == nil)
        check("the pane has no stale alias", fixture.aliases.alias(for: bundleID) == nil)
    }

    /// 校验快捷键可跨分区移动且不产生冲突。
    private static func testMovedShortcut() {
        let fixture = Fixture()
        fixture.hotKeys.setBinding(chord, for: .command(.clipboardHistory))
        let launcher = fixture.shortcuts.binding(
            for: .launcherShortcut, action: .togglePalette, name: "App Launcher")
        let clipboard = fixture.file.commandsBinding(for: .clipboardCommands, owner: .clipboard)
        let issues =
            launcher.write(chordText.settingsJSON) + clipboard.write(.object([])) + fixture.shortcuts.commit()
        check("a shortcut moves across sections without a conflict", issues.isEmpty)
        check("the launcher receives the chord", fixture.hotKeys.binding(for: .togglePalette) == chord)
        check(
            "Clipboard History releases it", fixture.hotKeys.binding(for: .command(.clipboardHistory)) == nil)
    }

    /// 构造一个已安装条目，用于注入夹具索引。
    private static func entry(_ bundleID: String, kind: AppEntry.Kind) -> AppEntry {
        AppEntry(
            id: bundleID, name: "Fixture", url: URL(fileURLWithPath: "/fixture"),
            bundleID: bundleID, kind: kind)
    }

    /// 断言辅助：成立则打印 PASS，否则打印 FAIL 并累加失败计数。
    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    /// 测试夹具：搭建内存版索引与存储，并把 LauncherSettingsFile 接到它们上。
    @MainActor
    private final class Fixture {
        let index = AppIndex()
        let hotKeys = HotKeyManager()
        let aliases: AliasStore
        let visibility: VisibilityStore
        let shortcuts: HotKeySettingsFile
        let file: LauncherSettingsFile
        private let suite = "launcher-settings-file-test-\(UUID().uuidString)"
        private let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: suite)!
            aliases = AliasStore(defaults: defaults)
            visibility = VisibilityStore(defaults: defaults)
            shortcuts = HotKeySettingsFile(hotKeys: hotKeys)
            file = LauncherSettingsFile(
                appIndex: index, aliases: aliases, visibility: visibility, shortcuts: shortcuts)
        }

        isolated deinit { defaults.removePersistentDomain(forName: suite) }
    }
}

// 内存内扫描与 Carbon 使已发布的绑定与存储可以被安全测试。
/// 测试用条目：带标识、名称、URL 与类型的值类型描述。
struct AppEntry: Sendable {
    enum Kind: String, Sendable { case application, systemSettings, systemAction, command, quickAction }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    var settingsOwner: SettingsTab?
    var subtitle: String?
    /// 用于偏好存储的键：优先用 bundleID，否则回退到 id。
    var preferenceKey: String { bundleID ?? id }
}

/// 内存版应用索引，供夹具注入已安装条目。
@MainActor
@Observable
final class AppIndex {
    var apps: [AppEntry] = []
}

/// 内存版热键管理器，记录绑定与冲突而不向系统注册。
@MainActor
@Observable
final class HotKeyManager {
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    /// 已绑定的应用 bundleID 列表。
    var boundBundleIDs: [String] {
        bindings.keys.compactMap { if case .app(let id) = $0 { id } else { nil } }
    }
    /// 已绑定的系统设置面板 bundleID 列表。
    var boundPaneBundleIDs: [String] {
        bindings.keys.compactMap { if case .settingsPane(let id) = $0 { id } else { nil } }
    }
    func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action] }
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) { bindings[action] = binding }
    /// 返回与给定绑定冲突的其它动作标识，无冲突则为 nil。
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        bindings.first { $0.key != action && binding.conflicts(with: $0.value) }
            .map { String(describing: $0.key) }
    }
}
