// 文件职责：定义以 Carbon 编码表示的快捷键值类型，负责修饰键/键码与 NSEvent、展示符号之间的双向转换。
// 分层：Model（纯值类型），位于 HotKeys/Service；其 Carbon 编码同时也是磁盘存储格式，不持有副作用。
import AppKit
import Carbon.HIToolbox

/// 以 Carbon 编码表示的快捷键，同时也是磁盘上的存储形态。参见 docs/features/hotkeys.md。
struct KeyShortcut: Hashable, Sendable {
    let carbonKeyCode: Int
    let carbonModifiers: Int

    /// 用 Carbon 键码与修饰键构造（修饰键会被掩码规范化）。
    init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        // 掩码只保留支持的修饰键，避免设备位影响相等性判断。
        self.carbonModifiers = carbonModifiers & Self.allModifiers
    }

    /// 从一次按键按下捕获快捷键，否则返回 nil：除功能键外必须包含 ⌘⌥⌃🌐 之一。
    init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .control, .shift, .function])
        let hasCommandingModifier = !flags.isDisjoint(with: [.command, .option, .control, .function])
        guard hasCommandingModifier || Self.isFunctionKey(keyCode) else { return nil }
        self.init(carbonKeyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: flags))
    }

    /// ✦ 代表的修饰键组合，未设置 Hyper 键时为 nil；用闭包以便开关变化时重新渲染键帽。
    @MainActor static var displayedHyperChord: () -> NSEvent.ModifierFlags? = { nil }

    /// 按规范顺序（🌐⌃⌥⇧⌘）每个键帽对应一个字符串，按键字形放在最后。
    @MainActor var keycaps: [String] {
        Self.collapsedModifierSymbols(from: modifierFlags, hyperChord: Self.displayedHyperChord())
            + [keyGlyph]
    }

    /// 由 Carbon 修饰键转换得到的 NSEvent 修饰键。
    var modifierFlags: NSEvent.ModifierFlags { Self.modifierFlags(from: carbonModifiers) }

    /// 把 Carbon 修饰键位转换为 NSEvent 修饰键。
    static func modifierFlags(from carbonModifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        if carbonModifiers & kEventKeyModifierFnMask != 0 { flags.insert(.function) }
        return flags
    }

    /// 把 NSEvent 修饰键转换为 Carbon 修饰键位。
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.function) { carbon |= kEventKeyModifierFnMask }
        return carbon
    }

    // MARK: - The Hyper chord

    /// ⌃⌥⌘，启用 Include Shift 时加上 ⇧——这是唯一写明该和弦的地方。
    static func hyperChord(includesShift: Bool) -> NSEvent.ModifierFlags {
        includesShift ? [.control, .option, .shift, .command] : [.control, .option, .command]
    }

    /// 把按另一套 Hyper 组合录制的和弦重新指向当前设置。参见 docs/features/hotkeys.md。
    func retargetingHyper(includesShift: Bool) -> KeyShortcut {
        let stale = Self.hyperChord(includesShift: !includesShift)
        guard modifierFlags.isSuperset(of: stale) else { return self }
        let retargeted =
            modifierFlags.subtracting(stale).union(Self.hyperChord(includesShift: includesShift))
        return KeyShortcut(
            carbonKeyCode: carbonKeyCode, carbonModifiers: Self.carbonModifiers(from: retargeted))
    }

    /// 在已配置 Hyper 和弦时，把 `modifierSymbols` 中的该和弦折叠为 "✦"。
    static func collapsedModifierSymbols(
        from flags: NSEvent.ModifierFlags, hyperChord: NSEvent.ModifierFlags?
    ) -> [String] {
        guard let hyperChord, flags.isSuperset(of: hyperChord) else {
            return modifierSymbols(from: flags)
        }
        return [HyperKeyPhysicalKey.hyperGlyph] + modifierSymbols(from: flags.subtracting(hyperChord))
    }

    /// 按固定顺序 🌐⌃⌥⇧⌘ 排列的修饰键符号。
    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.function) { symbols.append("🌐︎") }
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// 判断键码是否为功能键。
    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    /// 受支持的全部修饰键位的并集。
    private static let allModifiers = cmdKey | optionKey | controlKey | shiftKey | kEventKeyModifierFnMask

    // MARK: - Key glyph

    /// 无字符按键使用固定映射表，其余按当前键盘布局转换。
    @MainActor private var keyGlyph: String {
        if let special = Self.specialKeyGlyphs[carbonKeyCode] { return special }
        if let name = Self.functionKeyNames[carbonKeyCode] { return name }
        return ASCIIKeyboardLayout.character(for: carbonKeyCode)?.uppercased() ?? "?"
    }

    /// 无字符按键的显示字形表。
    private static let specialKeyGlyphs: [Int: String] = [
        kVK_Return: "↵", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "?⃝"
    ]

    /// 功能键键码到名称的映射。
    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

}

// 解码走带掩码的初始化器。参见 docs/features/hotkeys.md#persistence。
extension KeyShortcut: Codable {
    /// 持久化使用的键名。
    private enum CodingKeys: String, CodingKey {
        case carbonKeyCode, carbonModifiers
    }

    /// 从解码容器还原快捷键。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            carbonKeyCode: try container.decode(Int.self, forKey: .carbonKeyCode),
            carbonModifiers: try container.decode(Int.self, forKey: .carbonModifiers)
        )
    }
}
