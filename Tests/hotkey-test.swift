// 文件职责：测试双击修饰键检测器（DoubleTapDetector/ModifierKeyDetector）与热键拼写、Hyper chord、Globe 行为。
// 分层：测试 harness；在虚拟时钟上驱动真实检测器，不依赖 XCTest。

import AppKit
import Carbon.HIToolbox
import Foundation

/// 在虚拟时钟上驱动 `DoubleTapDetector`，因此每个时间边界都能被精确断言。
@MainActor
private struct Keyboard {
    var detector = DoubleTapDetector()
    private(set) var fired: [DoubleTapModifier] = []

    /// 更新检测器状态（按下修饰键集合），必要时记录已触发的双击修饰键。
    mutating func press(
        _ modifiers: Set<DoubleTapModifier>, other: Bool = false, at time: TimeInterval
    ) {
        if let modifier = detector.handle(
            .modifiers(modifiers, hasOtherModifiers: other), at: time)
        {
            fired.append(modifier)
        }
    }

    /// 释放全部修饰键（等价于按下空集合）。
    mutating func release(other: Bool = false, at time: TimeInterval) {
        press([], other: other, at: time)
    }

    /// 告知检测器发生了其它输入（按键或点击）。
    mutating func otherInput(at time: TimeInterval) {
        if let modifier = detector.handle(.otherInput, at: time) { fired.append(modifier) }
    }

    /// 完整执行一次按下再释放的点击。
    mutating func tap(
        _ modifier: DoubleTapModifier, at time: TimeInterval, hold: TimeInterval = 0.05
    ) {
        press([modifier], at: time)
        release(at: time + hold)
    }
}

@main
@MainActor
/// 双击修饰键与热键模型的独立测试 harness（直接运行，不依赖 XCTest）。
struct DoubleTapDetectorTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件不成立时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 断言辅助：比较实际触发序列与期望序列，失败时打印两侧的 rawValue。
    static func expect(_ fired: [DoubleTapModifier], _ expected: [DoubleTapModifier], _ m: String) {
        expect(fired == expected, "\(m) — fired \(fired.map(\.rawValue)), want \(expected.map(\.rawValue))")
    }

    /// harness 入口：依次运行全部用例，打印统计并在存在失败时以退出码 1 结束。
    static func main() {
        modifierGlyphs()
        commandActions()
        layoutCharacters()
        hyperChord()
        hyperRetargeting()
        hyperModifierIsolation()
        recorderKeycaps()
        spelling()
        globeTap()
        sidedModifiers()
        globeChord()
        firing()
        timing()
        chords()
        interruptions()
        repeats()
        resetting()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Spelling

    /// 足以用于拼写测试的美式键盘布局子集；应用自身通过 `ASCIIKeyboardLayout` 读取真实布局。
    private static let usKeys = [
        kVK_ANSI_K: "k", kVK_ANSI_1: "1", kVK_ANSI_Keypad1: "1", kVK_ANSI_Slash: "/",
        kVK_ANSI_Equal: "="
    ]
    /// Hyper 键对应的四个修饰键位掩码。
    private static let hyperModifiers = controlKey | optionKey | shiftKey | cmdKey

    /// 验证热键的文本拼写与解析双向一致（含别名、Hyper、双按与 Globe）。
    static func spelling() {
        let plain = HotKeySpelling(characters: usKeys, hyperModifiers: nil)
        let hyper = HotKeySpelling(characters: usKeys, hyperModifiers: hyperModifiers)
        func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
            .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
        }
        func roundTrips(_ binding: HotKeyBinding, as text: String, _ spelling: HotKeySpelling) {
            expect(spelling.text(for: binding) == text, "\(text) is how the binding spells")
            expect(spelling.binding(from: text) == binding, "\(text) reads back as the same binding")
        }

        roundTrips(combo(kVK_LeftArrow, controlKey | optionKey), as: "ctrl+option+left", plain)
        roundTrips(combo(kVK_ANSI_K, shiftKey | cmdKey), as: "shift+cmd+k", plain)
        roundTrips(combo(kVK_Space, optionKey), as: "option+space", plain)
        roundTrips(combo(kVK_F5, 0), as: "f5", plain)
        roundTrips(combo(kVK_ANSI_Slash, cmdKey), as: "cmd+/", plain)
        roundTrips(combo(kVK_UpArrow, kEventKeyModifierFnMask | controlKey), as: "fn+ctrl+up", plain)
        roundTrips(combo(kVK_ANSI_Keypad1, cmdKey), as: "cmd+keypad-1", plain)
        roundTrips(combo(kVK_ANSI_1, cmdKey), as: "cmd+1", plain)
        roundTrips(combo(110, controlKey), as: "ctrl+key-110", plain)
        roundTrips(.doubleTap(.command), as: "double-tap cmd", plain)
        roundTrips(.doubleTap(.control), as: "double-tap ctrl", plain)
        roundTrips(.globe, as: "globe", plain)
        roundTrips(.doubleGlobe, as: "double-tap globe", plain)
        roundTrips(combo(kVK_ANSI_K, hyperModifiers), as: "hyper+k", hyper)
        roundTrips(combo(kVK_ANSI_K, controlKey | optionKey | cmdKey), as: "ctrl+option+cmd+k", hyper)

        expect(
            plain.binding(from: " Command+Shift+K ") == combo(kVK_ANSI_K, shiftKey | cmdKey),
            "modifiers read in any order, case and alias")
        expect(
            plain.binding(from: "alt+space") == combo(kVK_Space, optionKey), "alt reads as option")
        expect(
            plain.binding(from: "double-tap command") == .doubleTap(.command),
            "a double-tap reads its modifier's alias")
        expect(
            plain.text(for: combo(kVK_ANSI_K, hyperModifiers)) == "ctrl+option+shift+cmd+k",
            "without a Hyper key the chord is spelled out")
        expect(plain.binding(from: "hyper+k") == nil, "without a Hyper key, hyper means nothing")

        let plusKey = HotKeySpelling(characters: [kVK_ANSI_Equal: "+"], hyperModifiers: nil)
        expect(
            plusKey.binding(from: "cmd++") == combo(kVK_ANSI_Equal, cmdKey),
            "a layout's plus key is spelled after the separator")

        expect(plain.binding(from: "k") == nil, "a bare key is refused, as the recorder refuses it")
        expect(plain.binding(from: "shift+k") == nil, "Shift alone does not command")
        expect(plain.binding(from: "cmd+") == nil, "a chord needs a key")
        expect(plain.binding(from: "cmd+nope") == nil, "an unknown key is refused")
        expect(plain.binding(from: "cmd+key-999") == nil, "a raw key code must be a real one")
        expect(plain.binding(from: "double-tap fn") == nil, "fn has no double-tap")
    }

    // MARK: - Model

    /// 验证 Globe 单击/双击、被其它修饰键取消及持久化往返。
    static func globeTap() {
        var detector = ModifierKeyDetector()
        var globeDown = false
        func globe(
            _ down: Bool, at time: TimeInterval, physical: Bool = true, other: Bool = false
        ) -> HotKeyBinding? {
            if physical { globeDown = down }
            var keys: Set<ModifierKey> = globeDown ? [.globe] : []
            if other { keys.insert(.leftShift) }
            guard case .released(let key, let doubleTap, false) = detector.handle(keys, at: time)
            else { return nil }
            return doubleTap ? key.doubleBinding : key.singleBinding
        }

        expect(globe(true, at: 0) == nil, "Globe press waits for release")
        expect(globe(false, at: 0.05) == .globe, "lone Globe fires on release")
        expect(globe(false, at: 0.10) == nil, "a second release without a press does nothing")
        expect(globe(true, at: 0.25) == nil, "a second Globe press waits for release")
        expect(globe(false, at: 0.30) == .doubleGlobe, "two quick Globe presses form a double tap")

        _ = globe(true, at: 1)
        _ = globe(true, at: 1.02, physical: false, other: true)
        expect(globe(false, at: 1.05) == nil, "another modifier cancels Globe")

        _ = globe(true, at: 2)
        detector.cancel()
        expect(globe(false, at: 2.05) == nil, "a key press or click cancels Globe")
        expect(globe(true, at: 3, physical: false) == nil, "an F-key cannot start Globe")
        expect(globe(false, at: 3.05, physical: false) == nil, "an F-key cannot finish Globe")

        _ = globe(true, at: 4)
        expect(globe(false, at: 4.05) == .globe, "first release remains a single candidate")
        _ = globe(true, at: 4.40)
        expect(globe(false, at: 4.45) == .globe, "a late second press starts a new tap")
        _ = globe(true, at: 5)
        expect(globe(false, at: 5.30) == nil, "holding Globe is not a tap")

        for binding in [HotKeyBinding.globe, .doubleGlobe] {
            let encoded = try? JSONEncoder().encode(binding)
            expect(
                encoded.flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) }
                    == binding,
                "\(binding) round-trips through the existing persistence format")
        }
        expect(HotKeyBinding.globe.keycaps == ["🌐︎"], "Globe uses one monochrome keycap")
        expect(
            HotKeyBinding.doubleGlobe.keycaps == ["🌐︎", "🌐︎"],
            "double Globe renders as two monochrome keycaps")
    }

    /// 验证 Globe 作为修饰键参与组合键时的 Carbon 位与键帽。
    static func globeChord() {
        let shortcut = KeyShortcut(keyCode: kVK_ANSI_J, modifierFlags: [.function])
        expect(shortcut != nil, "Globe alone can modify a letter")
        expect(
            shortcut?.carbonModifiers == kEventKeyModifierFnMask,
            "Globe uses Carbon's fn modifier bit")
        expect(shortcut?.keycaps == ["🌐︎", "J"], "Globe and the key have separate caps")
        expect(
            KeyShortcut(keyCode: kVK_ANSI_J, modifierFlags: [.function, .command])?.modifierFlags
                == [.function, .command],
            "Globe combines with ordinary modifiers")
        expect(
            KeyShortcut(carbonKeyCode: kVK_ANSI_J, carbonModifiers: Int.max).carbonModifiers
                == KeyShortcut.carbonModifiers(from: [.function, .control, .option, .shift, .command]),
            "decoding keeps fn but still discards unrelated modifier bits")
    }

    /// 验证左右侧修饰键由各自设备位识别，且单按/双按/长按判定互不干扰。
    static func sidedModifiers() {
        let spelling = HotKeySpelling(characters: usKeys, hyperModifiers: nil)
        let physicalMasks: [(UInt64, ModifierKey)] = [
            (0x1, .leftControl), (0x2000, .rightControl),
            (0x20, .leftOption), (0x40, .rightOption),
            (0x2, .leftShift), (0x4, .rightShift),
            (0x8, .leftCommand), (0x10, .rightCommand)
        ]
        for (mask, key) in physicalMasks {
            expect(
                ModifierKey.held(in: mask | 0xFFFF_0000, globeDown: false) == [key],
                "\(key) comes from its own device flag, not generic flags")
        }
        expect(
            ModifierKey.held(in: 0, globeDown: true) == [.globe],
            "only a physical Globe transition introduces Globe")
        for key in ModifierKey.allCases {
            for binding in [key.singleBinding, key.doubleBinding] {
                let encoded = try? JSONEncoder().encode(binding)
                expect(
                    encoded.flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) }
                        == binding, "\(binding) persists without losing its side")
                expect(
                    spelling.binding(from: spelling.text(for: binding)) == binding,
                    "\(binding) round-trips in settings.json")
            }
            var detector = ModifierKeyDetector()
            expect(detector.handle([key], at: 0) == .pressed(key), "\(key) presses immediately")
            expect(
                detector.handle([], at: 0.05) == .released(key, doubleTap: false, held: false),
                "\(key) single tap")
            _ = detector.handle([key], at: 0.2)
            expect(
                detector.handle([], at: 0.25) == .released(key, doubleTap: true, held: false),
                "\(key) double tap")
            _ = detector.handle([key], at: 1)
            expect(
                detector.handle([], at: 2) == .released(key, doubleTap: false, held: true),
                "\(key) can be recorded by holding")
            _ = detector.handle([key], at: 3)
            detector.cancel()
            expect(detector.handle([], at: 4) == nil, "\(key) a chord cannot finish a hold")
            _ = detector.handle([key], at: 5)
            detector.reset()
            expect(detector.handle([], at: 6) == nil, "\(key) reset discards a held key")
        }

        var detector = ModifierKeyDetector()
        _ = detector.handle([.leftCommand], at: 0)
        _ = detector.handle([], at: 0.05)
        _ = detector.handle([.rightCommand], at: 0.1)
        expect(
            detector.handle([], at: 0.15)
                == .released(.rightCommand, doubleTap: false, held: false),
            "opposite sides cannot complete each other's double tap")
        _ = detector.handle([.leftCommand], at: 1)
        expect(
            detector.handle([.leftCommand, .rightCommand], at: 1.1) == .cancelled,
            "both Command keys held cancels the lone press")
        expect(
            detector.handle([.rightCommand], at: 1.2) == .cancelled,
            "unwinding a chord does not start a fresh hold")
        expect(detector.handle([], at: 1.3) == nil, "a chord release cannot trigger a tap")
        expect(
            ModifierKey.held(in: 0x18, globeDown: false) == [.leftCommand, .rightCommand],
            "device flags distinguish both Command keys")
        expect(
            ModifierKey.held(in: 0xFFFF_0080, globeDown: false).isEmpty,
            "generic flags and Caps Lock alone cannot invent a physical key")
        expect(
            ModifierKey.leftCommand.singleBinding.keycaps == ["Left", "⌘"],
            "the physical side is visible in every shortcut display")
        expect(
            !HotKeyBinding.modifier(.leftCommand).conflicts(with: .modifier(.rightCommand)),
            "different sides can hold separate actions")
        expect(
            HotKeyBinding.doubleTap(.command).conflicts(with: .doubleModifier(.leftCommand)),
            "generic and sided double taps overlap")
        expect(
            !HotKeyBinding.modifier(.leftCommand).conflicts(with: .doubleModifier(.leftCommand)),
            "a single and double tap can coexist")
        expect(
            HotKeyBinding.modifier(.leftCommand).conflicts(
                with: .doubleModifier(.leftCommand), holdsModifier: true),
            "a hold reserves its key across single and double taps")
        expect(
            HotKeyBinding.modifier(.leftCommand).conflicts(
                with: .doubleTap(.command), holdsModifier: true),
            "a hold cannot shadow a generic double tap")
        expect(
            spelling.binding(from: "left cmd+k") == nil,
            "ordinary combinations remain side-agnostic")
    }

    /// 验证可双击修饰键的集合、字形与持久化 rawValue 顺序。
    static func modifierGlyphs() {
        expect(DoubleTapModifier.allCases.count == 4, "exactly four modifiers are eligible")
        expect(
            Set(DoubleTapModifier.allCases.map(\.glyph)) == ["⌃", "⌥", "⇧", "⌘"],
            "the glyphs are the four macOS modifier symbols")
        expect(
            DoubleTapModifier.allCases.allSatisfy { $0.keycaps == [$0.glyph, $0.glyph] },
            "a double-tap renders as its glyph twice")
        expect(
            DoubleTapModifier.allCases.map(\.rawValue)
                == ["control", "option", "shift", "command"],
            "raw values are the persisted spelling and stay in canonical ⌃⌥⇧⌘ order")
    }

    /// 验证 ASCII 键盘布局对调色板组合键用到的按键都能给出字符。
    static func layoutCharacters() {
        let keyCodes = [kVK_ANSI_K, kVK_ANSI_X, kVK_ANSI_Q, kVK_ANSI_Comma, kVK_ANSI_Period]
        let characters = keyCodes.compactMap { ASCIIKeyboardLayout.character(for: $0) }
        expect(
            characters.count == keyCodes.count,
            "the ASCII-capable layout translates every ANSI key a palette chord uses")
        expect(
            characters.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) },
            "the shortcut character stays ASCII while a non-ASCII input source is active")
        expect(
            keyCodes.allSatisfy {
                ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) != nil
            },
            "a layout's Command table resolves the same keys, so ⌘ chords never lose their letter")
    }

    // MARK: - Built-in command mappings

    /// 验证内置命令的热键动作绑定、defaults key 稳定性与 Quick Action 一致性。
    static func commandActions() {
        expect(
            HotKeyAction.systemAction(id: .toggleMicrophoneMute).defaultsKey
                == "hotkey.systemAction.toggle-microphone-mute",
            "microphone mute persists under its own global hotkey key")
        expect(
            HotKeyAction.systemAction(id: .toggleMicrophoneMute).defaultsKey
                != HotKeyAction.systemAction(id: .toggleMute).defaultsKey,
            "microphone and output mute can have independent hotkeys")
        let unbindable = Set(CommandID.allCases.filter { $0.hotKeyAction == nil })
        expect(
            unbindable == [.openInBrowser, .runShellCommand, .quit],
            "only the query-driven pair and Quit are unbindable — got \(unbindable.map(\.name))")
        expect(
            CommandID.allCases.allSatisfy {
                unbindable.contains($0) || $0.hotKeyAction == .command($0)
            },
            "every other command binds to its own action, so every row gets a recorder")

        // 以 rawValue 而非位置为键，因此重排枚举不会移动已有绑定。
        for id in CommandID.allCases where !unbindable.contains(id) {
            expect(
                id.hotKeyAction?.defaultsKey == "hotkey.\(id.rawValue)",
                "\(id.name) persists under hotkey.\(id.rawValue)")
            expect(
                HotKeyAction.builtInActions.contains(.command(id)),
                "\(id.name) is registered at launch like every other fixed action")
        }
        expect(
            HotKeyAction.builtInActions.contains(.togglePalette),
            "the launcher toggle is bindable without a command row of its own")

        // 每个动作都既能作为快捷键、也能到达启动器；`CommandID.init` 是穷尽的。
        expect(
            BuiltInQuickAction.allCases.allSatisfy { CommandID($0).name == $0.title },
            "each Quick Action's command carries the action's own title")
        expect(
            Set(BuiltInQuickAction.allCases.map(CommandID.init)).count == BuiltInQuickAction.allCases.count,
            "no two Quick Actions share a launcher command")
        expect(
            Set(HotKeyAction.builtInActions.map(\.defaultsKey)).count
                == HotKeyAction.builtInActions.count,
            "no two built-in actions share a defaults key, which would bind them together")
    }

    // MARK: - The Hyper chord

    /// 构造 G 键上的组合键，按磁盘存储形态用 Carbon 位表示。
    private static func combo(_ flags: NSEvent.ModifierFlags) -> KeyShortcut {
        KeyShortcut(
            carbonKeyCode: kVK_ANSI_G, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    /// 计算给定修饰键集合的折叠键帽，可选地按 Hyper chord 折叠。
    private static func caps(_ flags: NSEvent.ModifierFlags, includesShift: Bool?) -> [String] {
        KeyShortcut.collapsedModifierSymbols(
            from: flags,
            hyperChord: includesShift.map { KeyShortcut.hyperChord(includesShift: $0) })
    }

    /// 验证 Hyper chord 的组成、✦ 折叠显示与录制行为。
    static func hyperChord() {
        expect(
            KeyShortcut.hyperChord(includesShift: false) == [.control, .option, .command],
            "Hyper without Include Shift is exactly ⌃⌥⌘")
        expect(
            KeyShortcut.hyperChord(includesShift: true) == [.control, .option, .shift, .command],
            "Include Shift adds ⇧ and nothing else")

        for includesShift in [false, true] {
            let chord = KeyShortcut.hyperChord(includesShift: includesShift)
            expect(
                caps(chord, includesShift: includesShift) == ["✦"],
                "the chord itself collapses to a lone ✦ (shift \(includesShift))")
            expect(
                caps(chord.union(.capsLock), includesShift: includesShift) == ["✦"],
                "a stray non-shortcut flag doesn't defeat the collapse (shift \(includesShift))")
            expect(
                caps(chord, includesShift: nil) == KeyShortcut.modifierSymbols(from: chord),
                "with no Hyper key configured the chord renders literally (shift \(includesShift))")
        }

        // ⌃⌥⌘ 是 ⌃⌥⇧⌘ 的子集，因此在更宽的集合下只有关掉 Shift 的那个 chord 会被折叠。
        expect(
            caps([.control, .option, .command], includesShift: true) == ["⌃", "⌥", "⌘"],
            "the narrower chord doesn't collapse while Include Shift is on")
        expect(
            caps([.control, .option, .shift, .command], includesShift: false) == ["✦", "⇧"],
            "an extra modifier trails ✦ in canonical order")
        expect(
            caps([.command, .shift], includesShift: false) == ["⇧", "⌘"],
            "an ordinary combo is untouched, and stays in ⌃⌥⇧⌘ order rather than press order")

        expect(
            KeyShortcut(
                keyCode: kVK_ANSI_G,
                modifierFlags: KeyShortcut.hyperChord(
                    includesShift: true))?.carbonModifiers
                == combo([.control, .option, .shift, .command]).carbonModifiers,
            "recording while Hyper is held captures exactly the chord")
    }

    /// 验证开启/关闭 Include Shift 时对 Hyper chord 的重定向（含幂等与非 Hyper 键保持原样）。
    static func hyperRetargeting() {
        let narrow = combo([.control, .option, .command])
        let wide = combo([.control, .option, .shift, .command])

        expect(narrow.retargetingHyper(includesShift: true) == wide, "⌃⌥⌘G follows ⇧ going on")
        expect(wide.retargetingHyper(includesShift: false) == narrow, "⌃⌥⇧⌘G follows ⇧ going off")
        expect(
            narrow.retargetingHyper(includesShift: true).retargetingHyper(includesShift: false)
                == narrow,
            "the chord round-trips across a flip and back")
        for includesShift in [false, true] {
            let target = includesShift ? wide : narrow
            expect(
                target.retargetingHyper(includesShift: includesShift) == target,
                "retargeting is idempotent, so an import can't corrupt a matching chord")
        }

        expect(
            narrow.retargetingHyper(includesShift: true).carbonKeyCode == kVK_ANSI_G,
            "only the modifiers move; the key is preserved")
        expect(
            combo([.control, .option, .command, .capsLock]).retargetingHyper(includesShift: true)
                == wide,
            "the masking initializer keeps a stray flag out of the retargeted chord")

        // 任何不属于另一个 chord 的组合键都按录制原样保留。
        for flags in [[.command, .shift], [.option], [.control, .option], []]
            as [NSEvent
            .ModifierFlags]
        {
            let shortcut = combo(flags)
            for includesShift in [false, true] {
                expect(
                    shortcut.retargetingHyper(includesShift: includesShift) == shortcut,
                    "\(KeyShortcut.modifierSymbols(from: flags).joined()) is not a Hyper chord")
            }
        }
    }

    /// 验证录制界面中侧键标签与前缀键帽的显示规则。
    static func recorderKeycaps() {
        for (key, prefix, glyph) in [
            (ModifierKey.leftControl, "L", "⌃"), (.rightControl, "R", "⌃"),
            (.leftOption, "L", "⌥"), (.rightOption, "R", "⌥"),
            (.leftShift, "L", "⇧"), (.rightShift, "R", "⇧"),
            (.leftCommand, "L", "⌘"), (.rightCommand, "R", "⌘")
        ] {
            expect(key.singleBinding.recorderPrefix == prefix, "\(key) uses a compact side label")
            expect(key.singleBinding.recorderKeycaps == [glyph], "\(key) needs only one cap")
            expect(key.doubleBinding.recorderPrefix == nil, "double \(key) has no side label")
            expect(key.doubleBinding.keycaps == [glyph, glyph], "double \(key) displays only glyphs")
            expect(key.doubleBinding.recorderKeycaps == [glyph, glyph], "double \(key) has two caps")
        }
        for binding in [
            HotKeyBinding.globe, .doubleGlobe, .doubleTap(.command),
            .combo(combo([.command, .shift]))
        ] {
            expect(binding.recorderPrefix == nil, "\(binding) has no physical side label")
            expect(binding.recorderKeycaps == binding.keycaps, "\(binding) keeps its existing caps")
        }
    }

    /// 验证 Hyper 的设备位不会让检测器误判为普通修饰键单按/双按或长按。
    static func hyperModifierIsolation() {
        let previousChord = KeyShortcut.displayedHyperChord
        defer { KeyShortcut.displayedHyperChord = previousChord }
        for includesShift in [false, true] {
            let chord = KeyShortcut.hyperChord(includesShift: includesShift)
            KeyShortcut.displayedHyperChord = { chord }
            // Hyper 会叠加左侧设备位；被重映射的右键也可能保留自身的设备位。
            let leftBits: UInt64 = includesShift ? 0x2B : 0x29
            let residues: [(HyperKeyPhysicalKey, UInt64)] = [
                (.capsLock, 0), (.rightControl, 0x2000), (.rightOption, 0x40),
                (.rightCommand, 0x10), (.rightShift, includesShift ? 0x4 : 0)
            ]
            for (physicalKey, residue) in residues {
                let flags = NSEvent.ModifierFlags(rawValue: chord.rawValue | UInt(leftBits | residue))
                let keys = ModifierKey.held(in: UInt64(flags.rawValue), globeDown: false)
                let context = "\(physicalKey), Include Shift \(includesShift)"
                expect(keys.count >= 3, "\(context): Hyper never looks like a lone physical key")
                let recorded = KeyShortcut(keyCode: kVK_ANSI_G, modifierFlags: flags)
                expect(recorded == combo(chord), "\(context): recording discards all device bits")
                if let recorded {
                    let binding = HotKeyBinding.combo(recorded)
                    expect(binding.recorderKeycaps == ["✦", "G"], "\(context): Hyper keeps its glyph")
                    expect(binding.recorderPrefix == nil, "\(context): Hyper has no L/R prefix")
                }

                for duration in [0.05, 0.8] {
                    var sided = ModifierKeyDetector()
                    var generic = DoubleTapDetector()
                    let modifiers = Set(keys.compactMap(\.modifier))
                    for time in [0.0, 1.0] {
                        expect(
                            sided.handle(keys, at: time) == .cancelled,
                            "\(context): Hyper cannot start dictation's lone-key hold")
                        expect(
                            sided.handle(keys, at: time + 0.01) == nil,
                            "\(context): repeated Hyper flags cannot start a hold")
                        expect(
                            sided.handle([], at: time + duration) == nil,
                            "\(context): Hyper release cannot complete a single or double tap")
                        expect(
                            generic.handle(
                                .modifiers(modifiers, hasOtherModifiers: false),
                                at: time) == nil, "\(context): Hyper is not a generic modifier tap")
                        expect(
                            generic.handle(
                                .modifiers([], hasOtherModifiers: false),
                                at: time + duration) == nil, "\(context): Hyper release never double-taps")
                    }
                }

                for survivor in ModifierKey.allCases {
                    var detector = ModifierKeyDetector()
                    _ = detector.handle([survivor], at: 0)
                    expect(
                        detector.handle(keys.union([survivor]), at: 0.05) == .cancelled,
                        "\(context): adding Hyper cancels \(survivor)'s pending hold")
                    expect(
                        detector.handle([survivor], at: 0.1) == .cancelled,
                        "\(context): releasing Hyper cannot restart \(survivor)'s hold")
                    expect(
                        detector.handle([], at: 0.15) == nil,
                        "\(context): unwinding Hyper cannot fire \(survivor)'s tap")
                    _ = detector.handle([survivor], at: 0.2)
                    expect(
                        detector.handle([], at: 0.25)
                            == .released(survivor, doubleTap: false, held: false),
                        "\(context): a fresh \(survivor) tap still works after Hyper")
                    _ = detector.handle(keys, at: 0.3)
                    _ = detector.handle([], at: 0.35)
                    _ = detector.handle([survivor], at: 0.4)
                    expect(
                        detector.handle([], at: 0.45)
                            == .released(survivor, doubleTap: false, held: false),
                        "\(context): Hyper interrupts an awaiting \(survivor) double tap")
                }
            }
        }
    }

    // MARK: - Firing

    /// 验证双击在第二次释放时触发，而非第二次按下。
    static func firing() {
        for modifier in DoubleTapModifier.allCases {
            var keyboard = Keyboard()
            keyboard.tap(modifier, at: 0)
            expect(keyboard.fired, [], "\(modifier.rawValue): one tap alone doesn't fire")
            keyboard.tap(modifier, at: 0.15)
            expect(keyboard.fired, [modifier], "\(modifier.rawValue): a clean double-tap fires")
        }

        // 触发发生在第二次释放，而不是第二次按下。
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.press([.command], at: 0.15)
        expect(keyboard.fired, [], "the second press alone doesn't fire")
        keyboard.release(at: 0.20)
        expect(keyboard.fired, [.command], "the second release fires")
    }

    // MARK: - Timing

    /// 验证长按上限、间隔上限与最慢合法双击的时间边界。
    static func timing() {
        var slowFirst = Keyboard()
        slowFirst.tap(.command, at: 0, hold: DoubleTapDetector.maxHold + 0.01)
        slowFirst.tap(.command, at: 0.5)
        expect(slowFirst.fired, [], "a held first press isn't a tap")

        var slowSecond = Keyboard()
        slowSecond.tap(.command, at: 0)
        slowSecond.tap(.command, at: 0.10, hold: DoubleTapDetector.maxHold + 0.01)
        expect(slowSecond.fired, [], "a held second press isn't a tap")

        var lateGap = Keyboard()
        lateGap.tap(.command, at: 0, hold: 0.05)
        lateGap.tap(.command, at: 0.05 + DoubleTapDetector.maxGap + 0.01)
        expect(lateGap.fired, [], "a second tap after the gap doesn't fire")

        // 恰好落在两个时间窗口之内：仍然算数的、最慢的双击。
        let epsilon = 0.001
        var atLimit = Keyboard()
        atLimit.tap(.command, at: 0, hold: DoubleTapDetector.maxHold - epsilon)
        atLimit.tap(
            .command, at: DoubleTapDetector.maxHold + DoubleTapDetector.maxGap - 2 * epsilon,
            hold: DoubleTapDetector.maxHold - epsilon)
        expect(atLimit.fired, [.command], "the slowest qualifying double-tap still fires")

        // 过晚的第二次点按会成为新的第一次点按，而不是被丢弃。
        var rolling = Keyboard()
        rolling.tap(.command, at: 0)
        rolling.tap(.command, at: 1.0)
        expect(rolling.fired, [], "the late tap doesn't fire")
        rolling.tap(.command, at: 1.15)
        expect(rolling.fired, [.command], "but it seeds the next pair")
    }

    // MARK: - Chords

    /// 验证组合键展开/收回不构成双击，混合修饰键会各自开启新配对。
    static func chords() {
        var joined = Keyboard()
        joined.tap(.command, at: 0)
        joined.press([.command], at: 0.15)
        joined.press([.command, .shift], at: 0.17)
        joined.press([.command], at: 0.19)
        joined.release(at: 0.21)
        expect(joined.fired, [], "a chord unwinding back to one modifier isn't a tap")

        var chorded = Keyboard()
        chorded.press([.command, .shift], at: 0)
        chorded.release(at: 0.05)
        chorded.press([.command, .shift], at: 0.10)
        chorded.release(at: 0.15)
        expect(chorded.fired, [], "double-tapping a two-modifier chord doesn't fire")

        var mixed = Keyboard()
        mixed.tap(.command, at: 0)
        mixed.tap(.shift, at: 0.15)
        expect(mixed.fired, [], "two different modifiers aren't a double-tap")
        mixed.tap(.shift, at: 0.30)
        expect(mixed.fired, [.shift], "but the second one starts its own pair")

        var withFn = Keyboard()
        withFn.press([.command], other: true, at: 0)
        withFn.release(other: true, at: 0.05)
        withFn.press([.command], other: true, at: 0.10)
        withFn.release(other: true, at: 0.15)
        // 像 Caps Lock 这样的锁定位只要一直按下，就会让每次按键都失效。
        expect(withFn.fired, [], "fn held alongside disqualifies the press")

        // 额外修饰键消失后，此前的失效状态随即清除。
        var recovered = Keyboard()
        recovered.press([.command], other: true, at: 0)
        recovered.release(at: 0.05)
        recovered.tap(.command, at: 0.10)
        recovered.tap(.command, at: 0.25)
        expect(recovered.fired, [.command], "a clean pair after the poisoned one still fires")
    }

    // MARK: - Interruptions

    /// 验证两次按键之间的其它输入（按键或点击）会取消当前配对。
    static func interruptions() {
        var typed = Keyboard()
        typed.tap(.command, at: 0)
        typed.otherInput(at: 0.08)
        typed.tap(.command, at: 0.15)
        expect(typed.fired, [], "a key press between taps cancels the pair")

        var shortcut = Keyboard()
        shortcut.press([.command], at: 0)
        shortcut.otherInput(at: 0.02)
        shortcut.release(at: 0.05)
        shortcut.tap(.command, at: 0.10)
        expect(shortcut.fired, [], "⌘K then ⌘ isn't a double-tap")

        var clicked = Keyboard()
        clicked.tap(.option, at: 0)
        clicked.otherInput(at: 0.10)
        clicked.tap(.option, at: 0.14)
        expect(clicked.fired, [], "a click between taps cancels the pair")
    }

    // MARK: - Repeats

    /// 验证三连按只触发一次，下一个完整配对可再次触发。
    static func repeats() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [.command], "the pair fires")
        keyboard.tap(.command, at: 0.30)
        expect(keyboard.fired, [.command], "a triple-tap doesn't fire twice")
        keyboard.tap(.command, at: 0.45)
        expect(keyboard.fired, [.command, .command], "the next full pair fires again")
    }

    // MARK: - Reset

    /// 验证 reset 会丢弃待配对的按击与半按住的修饰键。
    static func resetting() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.detector.reset()
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [], "reset drops the pending tap")

        // reset 也会遗忘仍被按住的修饰键，因此下一次按下仍被视为干净的开始。
        var stuck = Keyboard()
        stuck.press([.command], at: 0)
        stuck.detector.reset()
        stuck.tap(.command, at: 0.10)
        stuck.tap(.command, at: 0.25)
        expect(stuck.fired, [.command], "reset clears a half-held press")
    }
}
