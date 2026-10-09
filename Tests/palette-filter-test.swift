// 文件职责：验证 ⌘P 在当前屏幕上的归属（PaletteFilterAction.resolve），即它应打开哪个头部菜单或保持不处理。
// 分层：测试 harness；仅依赖 Foundation，不引入 AppKit 或应用运行时状态。
import Foundation

/// ⌘P 只作用于当前屏幕的头部菜单。
@main
@MainActor
struct PaletteFilterTests {
    static var failures = 0
    static var passes = 0

    /// 断言 ⌘P 的解析结果与预期一致，不一致时计为失败并打印实际值与期望值。
    static func expect(
        _ actual: PaletteFilterAction, _ expected: PaletteFilterAction, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    /// 使用默认参数调用 PaletteFilterAction.resolve，便于用例只写出真正关心的入参。
    static func resolve(
        collapsed: Bool = false, mode: PaletteMode, accessory: Bool = false
    ) -> PaletteFilterAction {
        PaletteFilterAction.resolve(
            collapsed: collapsed, mode: mode, commandHasAccessory: accessory)
    }

    static func main() {
        expect(
            resolve(mode: .clipboard), .clipboardFilter,
            "the clipboard's type filter is what ⌘P has always opened")
        expect(
            resolve(mode: .fileSearch), .fileSearchFilter,
            "file search has a header filter of its own")
        expect(
            resolve(mode: .emoji), .emojiCategory,
            "the emoji picker exposes its category selector through ⌘P")
        expect(
            resolve(mode: .ai), .aiModel,
            "Quick AI opens its model selector through ⌘P")
        expect(
            resolve(mode: .ai, accessory: true), .aiModel,
            "a stale extension accessory cannot replace Quick AI's model selector")
        expect(
            resolve(mode: .extensionCommand, accessory: true), .extensionAccessory,
            "a running command's own dropdown answers ⌘P on its own screen")

        // 此处要防住的回归：命令自带的下拉菜单不得让剪贴板的筛选器叠在它上面，
        // 也不得吞掉一个本就未声明任何下拉菜单的命令上的 ⌘P。
        expect(
            resolve(mode: .extensionCommand, accessory: false), .ignored,
            "a command with no dropdown leaves ⌘P alone rather than opening nothing")
        expect(
            resolve(mode: .clipboard, accessory: true), .clipboardFilter,
            "off an extension screen the flag cannot reach the clipboard's own filter")

        expect(
            resolve(mode: .fileSearch, accessory: true), .fileSearchFilter,
            "off an extension screen the flag cannot reach file search's own filter either")

        // 其余模式此前不受 ⌘P 影响，必须保持原样。
        for mode in [
            PaletteMode.launcher, .aiHistory, .calculatorHistory,
            .quicklinks, .snippets, .schedule, .uninstall
        ] {
            expect(
                resolve(mode: mode), .ignored,
                "\(mode.rawValue) has no header filter, so ⌘P stays with the field")
            expect(
                resolve(mode: mode, accessory: true), .ignored,
                "\(mode.rawValue) opens no filter even if a stale accessory flag says so")
        }

        // 折叠态没有头部可挂按钮，因此不应打开任何筛选器。
        for mode in [PaletteMode.clipboard, .fileSearch, .emoji, .ai, .extensionCommand, .launcher] {
            expect(
                resolve(collapsed: true, mode: mode, accessory: true), .ignored,
                "the compact bar draws no filter button, so ⌘P opens nothing on \(mode.rawValue)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
