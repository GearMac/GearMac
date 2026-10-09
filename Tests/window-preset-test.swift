// 文件职责：以独立可执行 harness 验证窗口快捷键预设表，以及应用某个预设时对当前绑定的分配、覆盖与顶替结果。
// 分层：测试 harness；独立可执行（@main），仅依赖 Carbon.HIToolbox 与 Foundation，不 import AppKit/SwiftUI，只读取被测类型而不改动其行为。
import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct WindowPresetTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件为真时计一次通过，否则计一次失败并打印 FAIL 信息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 用 Carbon 键码与修饰键拼出一个组合键绑定（测试夹具）。
    static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }

    /// harness 入口：依次运行全部用例，汇总通过/失败计数，有失败时以退出码 1 结束。
    static func main() {
        testTables()
        testEmptyCurrent()
        testAlreadyApplied()
        testOverwrite()
        testDisplaced()
        testUnrelated()
        testMatching()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 校验各预设表的完整性（非空、同一个键不会绑给两个命令、修饰键能被录制器接受）以及代表性绑定。
    static func testTables() {
        for preset in WindowShortcutPreset.allCases {
            let bindings = preset.bindings
            expect(!bindings.isEmpty, "\(preset.title) binds something")
            expect(
                Set(bindings.values).count == bindings.count,
                "\(preset.title) never gives one key to two commands")
            for (id, binding) in bindings {
                let modifiers = binding.shortcut?.carbonModifiers ?? 0
                expect(
                    modifiers & (cmdKey | optionKey | controlKey) != 0,
                    "\(preset.title) \(id) has a modifier the recorder would accept")
            }
        }
        expect(
            WindowShortcutPreset.rectangle.bindings[.leftHalf]
                == combo(kVK_LeftArrow, controlKey | optionKey),
            "Rectangle's Left Half is ⌃⌥←")
        expect(
            WindowShortcutPreset.spectacle.bindings[.restore] == combo(kVK_ANSI_Z, optionKey | cmdKey),
            "Spectacle's undo is ⌥⌘Z")
    }

    /// 当前没有任何绑定时应用预设：全部条目都应分配，无顶替、无需确认。
    static func testEmptyCurrent() {
        let plan = WindowShortcutPresetPlan(preset: .rectangle, current: [:])
        expect(plan.assignments == WindowShortcutPreset.rectangle.bindings, "unset: every entry assigns")
        expect(plan.displaced.isEmpty, "unset: nothing displaced")
        expect(plan.overwritten.isEmpty, "unset: no confirmation")
    }

    /// 已完全应用同一预设：无可分配项，也无需确认。
    static func testAlreadyApplied() {
        let plan = WindowShortcutPresetPlan(
            preset: .spectacle, current: WindowShortcutPreset.spectacle.bindings)
        expect(plan.assignments.isEmpty, "applied twice: nothing to assign")
        expect(plan.overwritten.isEmpty, "applied twice: no confirmation")
    }

    /// 用户自定义键与预设冲突：冲突键被覆盖并需要确认，完全相同的键保持不动。
    static func testOverwrite() {
        let preset = WindowShortcutPreset.rectangle.bindings
        let own = combo(kVK_ANSI_L, controlKey | optionKey | cmdKey)
        let current: [WindowCommand.ID: HotKeyBinding] = [
            .leftHalf: own, .rightHalf: preset[.rightHalf]!
        ]
        let plan = WindowShortcutPresetPlan(preset: .rectangle, current: current)
        expect(plan.assignments[.leftHalf] == preset[.leftHalf], "a user key is replaced")
        expect(plan.assignments[.rightHalf] == nil, "a matching key is left alone")
        expect(plan.overwritten == [.leftHalf], "only the differing user key needs confirming")
    }

    /// 某命令正持有预设要用的键：该命令被顶替，并需要确认。
    static func testDisplaced() {
        let preset = WindowShortcutPreset.spectacle.bindings
        expect(preset[.moveLeft] == nil, "fixture: Spectacle leaves Move Left unbound")
        let current: [WindowCommand.ID: HotKeyBinding] = [.moveLeft: preset[.leftHalf]!]
        let plan = WindowShortcutPresetPlan(preset: .spectacle, current: current)
        expect(plan.displaced == [.moveLeft], "a command holding a preset key is displaced")
        expect(plan.overwritten == [.moveLeft], "a displaced command needs confirming")
    }

    /// 与预设无关的自定义键：不被顶替、无需确认，也不参与分配。
    static func testUnrelated() {
        let current: [WindowCommand.ID: HotKeyBinding] = [
            .moveLeft: combo(kVK_ANSI_H, controlKey | optionKey | cmdKey)
        ]
        let plan = WindowShortcutPresetPlan(preset: .spectacle, current: current)
        expect(plan.displaced.isEmpty, "an unrelated key is not displaced")
        expect(plan.overwritten.isEmpty, "an unrelated key needs no confirmation")
        expect(plan.assignments[.moveLeft] == nil, "a command outside the preset is untouched")
    }

    /// 反查当前绑定对应哪个预设：完全一致或仅多出无关命令仍匹配，改动或清空任一键则不再匹配。
    static func testMatching() {
        let rectangle = WindowShortcutPreset.rectangle.bindings
        expect(WindowShortcutPreset.matching([:]) == nil, "nothing bound matches no preset")
        expect(WindowShortcutPreset.matching(rectangle) == .rectangle, "a full apply matches")
        var extra = rectangle
        extra[.moveLeft] = combo(kVK_ANSI_H, controlKey | optionKey | cmdKey)
        expect(WindowShortcutPreset.matching(extra) == .rectangle, "a command outside still matches")
        var edited = rectangle
        edited[.leftHalf] = combo(kVK_ANSI_L, controlKey | optionKey | cmdKey)
        expect(WindowShortcutPreset.matching(edited) == nil, "one changed key breaks the match")
        var cleared = rectangle
        cleared[.leftHalf] = nil
        expect(WindowShortcutPreset.matching(cleared) == nil, "one cleared key breaks the match")
    }
}
