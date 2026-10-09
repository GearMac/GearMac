// 文件职责：验证 QuicklinkCoordinator 打开 quicklink 时的决策链：缺失/可读选区、剪贴板兜底、组合参数与普通链接，并断言参数提示、焦点与窗口可见性。
// 分层：测试 harness；编译真实 coordinator，平台协作对象（设置/注入器/窗口/启动器）由文件下方的桩实现留痕。

import AppKit
import SwiftUI

/// 验证 QuicklinkCoordinator 打开流程的测试入口。
@main
@MainActor
struct QuicklinkCoordinatorTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        try await missingSelection()
        try await readableSelection()
        try await clipboardFallback()
        try await combinedArguments()
        try await plainLink()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func missingSelection() async throws {
        for token in ["selection", "selectedText"] {
            let fixture = try Fixture(link: "https://de.wikipedia.org/w/index.php?search={\(token)}")
            defer { fixture.cleanUp() }
            fixture.coordinator.openQuicklink(id: fixture.link.id, forcingDefaultApp: true)
            try await Task.sleep(for: .milliseconds(1))
            expect(QuicklinkLauncher.opened.isEmpty, "an unreadable \(token) never opens an empty search")
            expect(fixture.window.isVisible, "an unreadable \(token) shows Search Quicklinks")
            expect(fixture.core.palette.selection == 1, "the prompt selects the requested quicklink")
            expect(
                fixture.core.palette.pendingArgumentEntryID == fixture.link.entryID,
                "the prompt requests argument focus after showing the palette")
            expect(
                fixture.accessory()?.firstIncompleteField == "Selected Text",
                "the selection field receives focus")

            fixture.core.palette.pendingArgumentEntryID = nil
            fixture.coordinator.openQuicklink(id: fixture.link.id)
            try await Task.sleep(for: .milliseconds(1))
            expect(QuicklinkLauncher.opened.isEmpty, "submitting the empty selection field keeps prompting")
            fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Selected Text": "Swift & macOS"])
            await waitForOpen()
            expect(
                QuicklinkLauncher.opened.first?.link
                    == "https://de.wikipedia.org/w/index.php?search=Swift%20%26%20macOS",
                "manual selection is encoded once")
            expect(QuicklinkLauncher.opened.first?.app == nil, "the default-app override survives the prompt")
            expect(!fixture.window.isVisible, "a completed prompt closes the palette")
        }
    }

    static func readableSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.injector.selection = "selected text"
        expect(fixture.accessory()?.firstIncompleteField == nil, "a normal selection chip stays optional")
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=selected%20text",
            "a readable selection opens immediately")
        expect(fixture.palette.shows == 0, "a readable selection needs no prompt")
        expect(QuicklinkLauncher.opened.first?.app == "com.example.browser", "the saved handler is used")

        QuicklinkLauncher.opened = []
        fixture.window.isVisible = true
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(fixture.injector.target == .previous, "palette activation reads the previous app")
    }

    static func clipboardFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.quicklinkSelectionFallback = .clipboard
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=clipboard%20text",
            "clipboard fallback still opens without prompting")
        expect(fixture.palette.shows == 0, "clipboard fallback never requests selection input")
        expect(fixture.accessory() == nil, "clipboard fallback has no selection chip")
    }

    static func combinedArguments() async throws {
        let fixture = try Fixture(link: "https://example.com/?q={selection}&site={argument name=\"Site\"}")
        defer { fixture.cleanUp() }
        fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Site": "swift.org"])
        try await Task.sleep(for: .milliseconds(1))
        expect(QuicklinkLauncher.opened.isEmpty, "filled arguments cannot bypass a missing selection")
        expect(
            fixture.accessory()?.firstIncompleteField == "Selected Text",
            "filled arguments leave selection focused")
        expect(
            fixture.core.palette.commandArguments[PaletteState.argumentKey(fixture.link.entryID, "Site")]
                == "swift.org",
            "the selection prompt preserves entered arguments")

        fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Selected Text": "Swift"])
        expect(
            fixture.accessory()?.firstIncompleteField == "Site",
            "a required argument is focused before selection")
        fixture.coordinator.openQuicklink(
            id: fixture.link.id, values: ["Selected Text": "Swift", "Site": "swift.org"])
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=Swift&site=swift.org",
            "selection and declared arguments resolve together")
    }

    static func plainLink() async throws {
        let fixture = try Fixture(link: "https://example.com/")
        defer { fixture.cleanUp() }
        fixture.settings.quicklinksEnabled = false
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        try await Task.sleep(for: .milliseconds(1))
        expect(
            QuicklinkLauncher.opened.isEmpty && fixture.palette.shows == 0, "disabled quicklinks remain inert"
        )
        fixture.settings.quicklinksEnabled = true
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == fixture.link.link,
            "a plain link opens without selection input")
    }

    /// 轮询等待 launcher 记录到一次打开请求，超时即判定为失败。
    static func waitForOpen() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while QuicklinkLauncher.opened.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(QuicklinkLauncher.opened.count == 1, "one destination opens")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 每个用例的测试夹具：准备临时 quicklink 存储与真实的 QuicklinkCoordinator。
    @MainActor
    final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: QuicklinkStore
        let link: Quicklink
        let settings = AppSettings()
        let injector = TextInjector()
        let window = PaletteWindowController()
        let core = AppCore()
        let palette: PaletteCoordinator
        let coordinator: QuicklinkCoordinator

        init(link: String = "https://example.com/?q={selection}") throws {
            QuicklinkLauncher.opened = []
            store = QuicklinkStore(directory: directory)
            try store.add(Quicklink(name: "A different quicklink", link: "https://example.com/"))
            self.link = try store.add(
                Quicklink(name: "Wikipedia", link: link, openWithBundleID: "com.example.browser"))
            palette = PaletteCoordinator(window: window, state: core.palette)
            coordinator = QuicklinkCoordinator(
                store: store, settings: settings, appIndex: AppIndex(), injector: injector,
                hotKeys: HotKeyManager(), favorites: FavoritesStore(), visibility: VisibilityStore(),
                ranking: LauncherRankingStore(), aliases: AliasStore(), windowController: window,
                paletteCoordinator: palette, settingsCoordinator: SettingsCoordinator(),
                clipboardHistory: { ["clipboard text"] }, core: core)
            core.quicklinkCoordinator = coordinator
        }

        func accessory() -> PaletteHeaderAccessory? {
            QuicklinkArgumentsAccessory.make(
                quicklink: link, core: core, vm: core.palette,
                focus: FocusState<String?>().projectedValue, placement: .besideSearchField,
                onOpenOptions: { _ in }, onSubmit: {})
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }
}

// 平台协作对象均为惰性桩，使已发布的 coordinator 不会真的打开 app 或读取选区。

/// 测试桩：仅提供 coordinator 在本 harness 中触达的设置项。
@MainActor
final class AppSettings {
    var quicklinksEnabled = true
    var quicklinksShowInLauncher = true
    var quicklinkSelectionFallback = QuicklinkSelectionFallback.ask
    var quicklinkOpensNewWindow = false
    var quicklinkConfirmsBeforeDelete = false
    var interfaceSize = InterfaceSize()
    var language: AppLanguage = .english
    func text<K: LocalizableKey>(_ key: K) -> String { L10n.string(key, language: language) }
}

struct InterfaceSize { var metrics: Int { 0 } }
enum CommandID { case createQuicklink, searchQuicklinks, importQuicklinks, exportQuicklinks }

@MainActor
final class AppIndex {
    func setQuicklinks(_ links: [Quicklink]) {}
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {}
    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {}
}

enum InjectionTarget: Equatable { case frontmost, previous; static func current() -> Self? { .frontmost } }

/// 测试桩：返回固定的展开上下文（选区、剪贴板历史等），并记录目标 app。
@MainActor
final class TextInjector {
    var selection = ""
    var target: InjectionTarget?
    func captureExpansionContext(
        target: InjectionTarget?, clipboardHistory: [String]
    ) -> SnippetTemplateEngine.ExpansionContext {
        self.target = target
        return .init(
            clipboardHistory: clipboardHistory, selection: selection, now: .distantPast,
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}

enum HotKeyAction: Equatable { case quicklink(id: UUID) }
@MainActor
final class HotKeyManager {
    var recordingAction: HotKeyAction?
    func setBinding(_ binding: String?, for action: HotKeyAction) {}
}
final class FavoritesStore { func remove(keys: Set<String>) {} }
final class VisibilityStore { func removeItemKeys(_ keys: Set<String>) {} }
final class LauncherRankingStore { func reset(itemKey: String) {} }
final class AliasStore { func removeKeys(_ keys: Set<String>) {} }

@MainActor
final class PaletteWindowController {
    var isVisible = false
    var previousTarget: InjectionTarget? = .previous
}

enum PaletteMode { case quicklinks }
@MainActor
final class PaletteState {
    var selection = 0
    var commandArguments: [String: String] = [:]
    var pendingArgumentEntryID: String?
    static func argumentKey(_ entryID: String, _ name: String) -> String { entryID + "\u{1}" + name }
}

/// 测试桩：记录 showPalette 调用次数并同步窗口可见性。
@MainActor
final class PaletteCoordinator {
    let window: PaletteWindowController
    let state: PaletteState
    var shows = 0
    init(window: PaletteWindowController, state: PaletteState) { self.window = window; self.state = state }
    func showPalette(mode: PaletteMode) {
        shows += 1
        window.isVisible = true
        state.selection = 0
        state.commandArguments = [:]
        state.pendingArgumentEntryID = nil
    }
    func hidePalette(restoreFocus: Bool) { window.isVisible = false }
}

enum SettingsTab { case quicklinks }
final class SettingsCoordinator { func showSettings(tab: SettingsTab) {} }
struct QuicklinkEditRequest { let quicklink: Quicklink? }
enum DialogTone { case danger, neutral, success }
/// 测试桩：仅提供 coordinator 需要的窗口/设置/提示等接口。
@MainActor
final class AppCore {
    let palette = PaletteState()
    let settings = AppSettings()
    lazy var quicklinkCoordinator: QuicklinkCoordinator = {
        fatalError("The fixture must wire the coordinator")
    }()
    var pendingQuicklinkEdit: QuicklinkEditRequest?
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {}
    func reportFailure(title: String, message: String, symbol: String, recovery: String) async -> Bool {
        false
    }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String) {}
}

enum BackupActions {
    static func chooseSaveLocation(named: String) -> URL? { nil }
    static func chooseJSONFile() -> URL? { nil }
}

/// 测试桩：记录每次打开请求，不真正打开链接。
@MainActor
enum QuicklinkLauncher {
    struct Opened { let link: String; let app: String? }
    static var opened: [Opened] = []
    enum Failure: LocalizedError {
        case refused
        var missingApplicationBundleID: String? { nil }
        func message(_ language: AppLanguage) -> String { "" }
    }
    static func open(_ link: String, openWithBundleID: String?, inNewWindow: Bool) async throws(Failure) {
        opened.append(Opened(link: link, app: openWithBundleID))
    }
}

struct InlineArgument { let id: String; let title: String; let options: [String]; let isOptional: Bool }
struct InlineArgumentFields: View {
    let arguments: [InlineArgument]
    let symbol: String?
    let value: (String) -> Binding<String>
    let focused: FocusState<String?>.Binding
    let openOptions: (String) -> Void
    let onSubmit: () -> Void
    var body: some View { EmptyView() }
    static func totalWidth(for arguments: [InlineArgument], hasIcon: Bool, metrics: Int) -> CGFloat { 0 }
}

struct PaletteHeaderAccessory {
    enum Placement { case afterQuery, besideSearchField }
    let width: CGFloat
    let fieldNames: [String]
    let firstIncompleteField: String?
    let optionsMenu: (String) -> PopoverMenuContent?
    let placement: Placement
    let view: AnyView
}

struct PopoverMenuContent { let header: String; let items: [PopoverMenuItem] }
struct PopoverMenuItem {
    enum Icon { case symbol(String), blank }
    let title: String
    let icon: Icon
    let action: () -> Void
}
