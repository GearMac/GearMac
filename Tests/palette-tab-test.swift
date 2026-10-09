// 文件职责：验证 Tab 键在启动器、AI Chat、剪贴板三个界面间的环形切换逻辑，以及关闭 AI/剪贴板后跳过对应站点、子屏幕退出到启动器的行为。
// 分层：测试 harness；直接编译真实源码，只调用 `PaletteTabAction.resolve` 纯逻辑，不触碰真实界面。

import Foundation

/// 三个界面保持单向可达，且 chat 关闭时会被跳过。
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    /// 逐条断言 Tab 在每个模式下的下一步动作，并验证按压三次能回到启动器。
    static func main() {
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: true, clipboardEnabled: true),
            .ask,
            "the launcher hands the typed text to chat as the question, not as a draft")
        expect(
            PaletteTabAction.resolve(mode: .ai, aiEnabled: true, clipboardEnabled: true),
            .freshScreen(.clipboard),
            "chat hands on to the clipboard without carrying the unsent draft into the filter")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: true, clipboardEnabled: true),
            .carryQuery(.launcher),
            "the clipboard closes the ring, and one search narrows both lists")

        // 关闭后 chat 既无启动器命令也无热键；环形切换不能让用户困在那里。
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: false, clipboardEnabled: true),
            .carryQuery(.clipboard),
            "turned off, chat is skipped and the launcher flips straight to the clipboard")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, aiEnabled: false, clipboardEnabled: true),
            .carryQuery(.launcher),
            "turned off, the clipboard still returns to the launcher")

        // 子屏幕通过命令或热键进入，因此 Tab 是离开而不是继续环形切换。
        for mode in [
            PaletteMode.aiHistory, .emoji, .fileSearch, .calculatorHistory, .quicklinks, .snippets
        ] {
            expect(
                PaletteTabAction.resolve(mode: mode, aiEnabled: true, clipboardEnabled: true),
                .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        expect(
            PaletteTabAction.resolve(
                mode: .extensionCommand, aiEnabled: true, clipboardEnabled: true),
            .carryQuery(.launcher),
            "an extension command exits to the launcher rather than joining the ring")

        // 两个站点都关闭，Tab 无处可去，只能让启动器保持不动。
        expect(
            PaletteTabAction.resolve(
                mode: .launcher, aiEnabled: false, clipboardEnabled: false),
            .carryQuery(.launcher),
            "with the clipboard off too, the launcher rings back onto itself")
        expect(
            PaletteTabAction.resolve(mode: .ai, aiEnabled: true, clipboardEnabled: false),
            .carryQuery(.launcher),
            "turned off, the clipboard is skipped and chat returns to the launcher")

        // 从启动器按三次必须回到启动器，否则这个环就是死路。
        var mode = PaletteMode.launcher
        var visited: [PaletteMode] = []
        for _ in 0..<3 {
            switch PaletteTabAction.resolve(mode: mode, aiEnabled: true, clipboardEnabled: true) {
            case .carryQuery(let next), .freshScreen(let next): mode = next
            // ask 会打开 chat，因此环仍会经过它。
            case .ask: mode = .ai
            }
            visited.append(mode)
        }
        if visited == [.ai, .clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: three presses ring back to the launcher — got \(visited)")
        }

        var offMode = PaletteMode.launcher
        var offVisited: [PaletteMode] = []
        for _ in 0..<2 {
            switch PaletteTabAction.resolve(
                mode: offMode, aiEnabled: false, clipboardEnabled: true)
            {
            case .carryQuery(let next), .freshScreen(let next): offMode = next
            case .ask: offMode = .ai
            }
            offVisited.append(offMode)
        }
        if offVisited == [.clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: turned off, two presses ring back to the launcher — got \(offVisited)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
