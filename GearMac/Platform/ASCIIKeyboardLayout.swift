// 文件职责：借助 Carbon/AppKit 查询当前 ASCII 键盘布局，把按键码与修饰键翻译为实际字符，用于把快捷键还原为逻辑按键。
// 分层：Service；访问输入源仅为即时查询，不持有跨调用状态。
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 命名空间：在“当前 ASCII 键盘布局”上做按键到字符的翻译。
enum ASCIIKeyboardLayout {
    /// 默认不带修饰键：返回该键的基础字符，也就是快捷键字形所显示的字符。
    @MainActor static func character(for keyCode: Int, modifiers: UInt32 = 0) -> String? {
        withCurrentLayout { character(for: keyCode, modifiers: modifiers, in: $0) }
    }

    /// 返回区间内每个键的基础字符，只在一次布局查询中完成转换。
    @MainActor static func baseCharacters(for keyCodes: Range<Int>) -> [Int: String] {
        withCurrentLayout { layout in
            keyCodes.reduce(into: [:]) { characters, keyCode in
                characters[keyCode] = character(for: keyCode, modifiers: 0, in: layout)
            }
        } ?? [:]
    }

    /// 获取当前 ASCII 输入源并调用 `body`，把布局指针的生命周期限制在此闭包内。
    @MainActor private static func withCurrentLayout<Result>(
        _ body: (UnsafePointer<UCKeyboardLayout>) -> Result?
    ) -> Result? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        // 这些字节属于 `source`，它会被保留到 `body` 返回为止。
        return withExtendedLifetime(source) {
            body(
                unsafeBitCast(
                    CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self))
        }
    }

    /// 在给定布局上做一次 `UCKeyTranslate`，返回按键产生的字符。
    private static func character(
        for keyCode: Int, modifiers: UInt32, in keyLayout: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// 布局拥有自己的 Command 键表：「Dvorak – QWERTY ⌘」只有通过该表才能把 ⌘K 还原为 QWERTY。
    @MainActor static func character(for event: NSEvent) -> String? {
        character(
            for: Int(event.keyCode),
            modifiers: event.modifierFlags.contains(.command) ? UInt32(cmdKey >> 8) : 0)
    }

    /// SwiftUI 暴露的是输入源字符；此处借助 AppKit 还原出逻辑 ASCII 按键。
    @MainActor static func keyEquivalent(fallingBackTo key: KeyEquivalent) -> KeyEquivalent {
        guard let event = NSApp.currentEvent,
            !event.modifierFlags.isDisjoint(with: [.command, .control])
        else { return lowercased(key) }
        return recovered(key, layoutCharacter: character(for: event)?.lowercased().first)
    }

    /// 还原逻辑本身，作用于调用方已转换好的布局字符。
    static func recovered(_ key: KeyEquivalent, layoutCharacter: Character?) -> KeyEquivalent {
        guard !isNamedKey(key), let layoutCharacter,
            layoutCharacter.unicodeScalars.allSatisfy(\.isASCII)
        else { return lowercased(key) }
        return KeyEquivalent(layoutCharacter)
    }

    /// 方向键与翻页键：`UCKeyTranslate` 会用该判断也接受的 ASCII 控制字符回答这些键。
    private static func isNamedKey(_ key: KeyEquivalent) -> Bool {
        key.character.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
    }

    /// Shift 会把 SwiftUI 的按键变为大写，但每个组合键都按小写字母书写。
    private static func lowercased(_ key: KeyEquivalent) -> KeyEquivalent {
        key.character.lowercased().first.map { KeyEquivalent($0) } ?? key
    }

    /// 判断某个 `KeyEquivalent` 在当前布局下是否对应给定字符。
    @MainActor static func matches(_ key: KeyEquivalent, character: Character) -> Bool {
        keyEquivalent(fallingBackTo: key) == KeyEquivalent(character)
    }
}
