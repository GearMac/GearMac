// 文件职责：表示并格式化菜单快捷键，把 AX 修饰位与字符转换为菜单键帽显示。
// 分层：Model；纯值类型，不 import AppKit/SwiftUI，不承担副作用。
import Foundation

/// 一条菜单项的快捷键：字符与四个修饰键标志。
struct MenuSearchShortcut: Hashable, Sendable {
    let character: String
    let hasCommand: Bool
    let hasShift: Bool
    let hasOption: Bool
    let hasControl: Bool

    // AX 修饰位（经实际验证）：0 位 Shift，1 位 Option，2 位 Control，3 位清除默认隐含的 ⌘。
    /// 从 AX 的字符与修饰位构造快捷键；字符为空或出现未知位时返回 nil。
    static func commandEquivalent(character: String, modifiers: Int) -> Self? {
        guard !character.isEmpty, modifiers & ~0b1111 == 0 else { return nil }
        return Self(
            character: character,
            hasCommand: modifiers & 0b1000 == 0,
            hasShift: modifiers & 0b001 != 0,
            hasOption: modifiers & 0b010 != 0,
            hasControl: modifiers & 0b100 != 0)
    }

    // AX 会把非输入键上报为控制字符或文本字体无法绘制的 PUA 码位；改为用名称表示。
    /// 用于展示的字符：特殊键转换为对应的键帽符号或 F 键名称。
    var displayCharacter: String {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return character.uppercased() }
        if let glyph = Self.glyphs[scalar.value] { return glyph }
        guard Self.functionKeys.contains(scalar.value) else { return character.uppercased() }
        return "F\(scalar.value - Self.functionKeys.lowerBound + 1)"
    }

    // 按键帽顺序与 macOS 菜单一致，使一行读起来就像它来自的菜单。
    /// 快捷键的各键帽符号，按修饰键在前、主键在后的顺序。
    var keycaps: [String] {
        guard !character.isEmpty else { return [] }
        var caps: [String] = []
        if hasControl { caps.append("⌃") }
        if hasOption { caps.append("⌥") }
        if hasShift { caps.append("⇧") }
        if hasCommand { caps.append("⌘") }
        caps.append(displayCharacter)
        return caps
    }

    /// 拼接后的快捷键展示文本；无键帽时返回 nil。
    var displayString: String? {
        let caps = keycaps
        return caps.isEmpty ? nil : caps.joined()
    }

    /// 功能键对应的 PUA 码位区间，用于换算为 F1…F19。
    private static let functionKeys: ClosedRange<UInt32> = 0xF704...0xF726

    /// 控制字符与特殊键码位到键帽符号的映射表。
    private static let glyphs: [UInt32: String] = [
        0x03: "⌤", 0x08: "⌫", 0x09: "⇥", 0x0D: "↩", 0x19: "⇤", 0x1B: "⎋", 0x20: "␣",
        0x7F: "⌫", 0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→", 0xF728: "⌦",
        0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟", 0xF739: "⌧", 0xF746: "?"
    ]
}
