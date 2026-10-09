// 文件职责：验证 Esc 键在命令面板中的行为优先级（PaletteEscapeAction.resolve）与 ⌘⎋ 组合键识别（CommandEscapeTap.isChord）。
// 分层：测试 harness；仅依赖 Foundation / Carbon，不引入 AppKit 或应用运行时状态。
import Carbon.HIToolbox
import Foundation

/// 一次按键绝不能跳过用户仍能看到的步骤，也不能因此丢弃用户的工作。
@main
@MainActor
struct PaletteEscapeTests {
    static var failures = 0
    static var passes = 0

    /// 断言 Esc 的解析结果与预期一致，不一致时计为失败并打印实际值与期望值。
    static func expect(_ actual: PaletteEscapeAction, _ expected: PaletteEscapeAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    /// 断言 ⌘⎋ 组合键识别结果与预期一致，不一致时计为失败并打印实际值与期望值。
    static func expectChord(_ actual: Bool, _ expected: Bool, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    /// 使用出厂默认参数，这样每个用例只需写出它真正关心的那几项。
    static func resolve(
        menuOpen: Bool = false, menuQuery: String = "", argumentFocused: Bool = false,
        query: String = "", mode: PaletteMode = .launcher, canGoBack: Bool = false,
        behavior: EscapeKeyBehavior = .navigateBackOrClose
    ) -> PaletteEscapeAction {
        PaletteEscapeAction.resolve(
            menuOpen: menuOpen, menuQuery: menuQuery, argumentFocused: argumentFocused,
            query: query, mode: mode, canGoBack: canGoBack, behavior: behavior)
    }

    static func main() {
        expect(
            resolve(menuOpen: true, menuQuery: "paste"),
            .clearMenuQuery,
            "an open menu clears its own query before it closes")
        expect(
            resolve(menuOpen: true, query: "notes"),
            .closeMenu,
            "an open menu closes before anything else")
        expect(
            resolve(query: "notes"),
            .clearQuery,
            "a typed launcher query clears before the palette hides")
        expect(
            resolve(query: "notes", mode: .extensionCommand),
            .clearQuery,
            "a typed extension query clears before the extension screen exits")
        expect(
            resolve(mode: .extensionCommand),
            .exitExtensionScreen,
            "an empty extension query exits the extension screen, which owns its own stack")
        expect(
            resolve(),
            .hidePalette,
            "an empty launcher query hides the palette")
        // 这里输入框不是搜索框，而是聊天草稿。
        expect(
            resolve(query: "why is the sky", mode: .ai),
            .clearQuery,
            "an unsent chat draft clears before chat itself is left")

        // 决定有无返回目标的是来源（provenance），而不是模式本身。
        expect(
            resolve(mode: .clipboard, canGoBack: true),
            .goBack,
            "a clipboard screen opened from the root search returns to it")
        expect(
            resolve(mode: .clipboard),
            .hidePalette,
            "the same screen summoned by its own hotkey is a root, so it hides")
        expect(
            resolve(mode: .ai, canGoBack: true),
            .goBack,
            "chat is no different: reached from the root, it goes back to it")
        expect(
            resolve(mode: .ai),
            .hidePalette,
            "chat summoned by its own hotkey hides rather than falling back to the launcher")
        expect(
            resolve(query: "notes", mode: .clipboard, canGoBack: true),
            .clearQuery,
            "a typed query still clears before the back step it would otherwise skip")

        // 关闭并弹回根屏：无论它是叠在什么界面之上打开的，一次按键即结束本次会话。
        expect(
            resolve(mode: .clipboard, canGoBack: true, behavior: .closeAndPopToRoot),
            .hidePalette,
            "close-and-pop-to-root hides even where a back step exists")
        expect(
            resolve(mode: .extensionCommand, canGoBack: true, behavior: .closeAndPopToRoot),
            .hidePalette,
            "close-and-pop-to-root outranks an extension's own stack too")
        expect(
            resolve(query: "notes", behavior: .closeAndPopToRoot),
            .clearQuery,
            "clearing the query is the first press under either behavior")
        expect(
            resolve(menuOpen: true, canGoBack: true, behavior: .closeAndPopToRoot),
            .closeMenu,
            "a menu outranks the behavior setting beneath it")

        expect(
            resolve(menuOpen: true, mode: .ai),
            .closeMenu,
            "a menu outranks the chat screen it is drawn over")
        expect(
            resolve(menuOpen: true, mode: .extensionCommand),
            .closeMenu,
            "a menu outranks the extension screen it is drawn over")
        // 内联参数输入框比找到该命令的那条查询更深一层。
        expect(
            resolve(argumentFocused: true, query: "search"),
            .leaveArgumentField,
            "an argument field hands focus back before the query that found it clears")
        expect(
            resolve(argumentFocused: true, canGoBack: true),
            .leaveArgumentField,
            "an empty query does not let the argument field skip its own step")
        expect(
            resolve(menuOpen: true, argumentFocused: true, query: "search"),
            .closeMenu,
            "a menu still outranks the argument field beneath it")

        // ⌘⎋ 不会进入 responder chain，因此什么算作该组合键由 tap 决定。
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: [.maskCommand]),
            true, "a bare ⌘⎋ is the root-search chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_Escape), flags: []),
            false, "an unmodified Escape belongs to the palette's own handler")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlternate]),
            false, "⌥⌘⎋ is Force Quit and must pass straight through")
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskShift]),
            false, "any further modifier spells somebody else's chord")
        expectChord(
            CommandEscapeTap.isChord(keyCode: Int64(kVK_ANSI_A), flags: [.maskCommand]),
            false, "⌘A is not it")
        // 真实键盘上 Caps Lock 与 fn 会一并带上，但不改变实际按下的组合键。
        expectChord(
            CommandEscapeTap.isChord(
                keyCode: Int64(kVK_Escape), flags: [.maskCommand, .maskAlphaShift, .maskSecondaryFn]),
            true, "the flags a real keyboard adds do not disqualify the chord")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
