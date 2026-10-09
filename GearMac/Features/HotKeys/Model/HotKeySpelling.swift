// 文件职责：把快捷键绑定向设置文件中的可读文本（如 "ctrl+shift+a"、"double-tap cmd"、"hyper+s"）双向转换。
// 分层：Model；纯解析与格式化，依赖 Carbon 虚拟键码常量。
import Carbon.HIToolbox
import Foundation

/// 人在 settings.json 中输入的绑定文本形式。参见 docs/features/settings-file.md。
struct HotKeySpelling: Sendable {
    /// 设置了 Hyper 键时，Hyper 组合键对应的 Carbon 修饰位，使其能再次拼写为 `hyper`。
    let hyperModifiers: Int?
    private let characterByCode: [Int: String]
    private let codeByCharacter: [String: Int]

    /// `characters` 是本机每个键的基础字符，即其键帽上显示的字符。
    init(characters: [Int: String], hyperModifiers: Int?) {
        var characterByCode: [Int: String] = [:]
        var codeByCharacter: [String: Int] = [:]
        // 按升序处理，使两个键都能输入的字符在两个方向上统一以小键码表示。
        for (code, character) in characters.sorted(by: { $0.key < $1.key }) {
            let name = character.lowercased()
            guard Self.namedKeys[code] == nil, Self.isSpellable(name), codeByCharacter[name] == nil
            else { continue }
            characterByCode[code] = name
            codeByCharacter[name] = code
        }
        self.characterByCode = characterByCode
        self.codeByCharacter = codeByCharacter
        self.hyperModifiers = hyperModifiers
    }

    /// 把绑定格式化为设置文件中的文本。
    func text(for binding: HotKeyBinding) -> String {
        switch binding {
        case .combo(let shortcut): text(for: shortcut)
        case .doubleTap(let modifier): "double-tap " + Self.name(of: modifier)
        case .modifier(let key): Self.name(of: key)
        case .doubleModifier(let key): "double-tap " + Self.name(of: key)
        case .globe: "globe"
        case .doubleGlobe: "double-tap globe"
        }
    }

    /// 对录制器会拒绝的任何内容返回 nil，使设置文件无法绑定应用本身无法绑定的键。
    func binding(from text: String) -> HotKeyBinding? {
        let spelled = text.trimmingCharacters(in: .whitespaces).lowercased()
        if spelled == "globe" { return .globe }
        if let key = Self.modifierKey(named: spelled) { return key.singleBinding }
        if spelled.hasPrefix(Self.doubleTapPrefix) {
            let modifier = String(spelled.dropFirst(Self.doubleTapPrefix.count))
            if modifier == "globe" { return .doubleGlobe }
            if let key = Self.modifierKey(named: modifier) { return key.doubleBinding }
            return Self.doubleTapModifier(named: modifier).map(HotKeyBinding.doubleTap)
        }
        return shortcut(from: spelled).map(HotKeyBinding.combo)
    }

    // MARK: - Combos

    /// 把组合键格式化为文本（还原 Hyper 与各修饰键，并附上按键名）。
    private func text(for shortcut: KeyShortcut) -> String {
        var modifiers = shortcut.carbonModifiers
        var parts: [String] = []
        if let hyperModifiers, modifiers & hyperModifiers == hyperModifiers {
            parts.append(Self.hyperName)
            modifiers &= ~hyperModifiers
        }
        for (mask, name) in Self.writtenModifiers where modifiers & mask != 0 {
            parts.append(name)
        }
        parts.append(keyName(for: shortcut.carbonKeyCode))
        return parts.joined(separator: "+")
    }

    /// 解析组合键文本（形如 "ctrl+shift+a"），返回 KeyShortcut。
    private func shortcut(from spelled: String) -> KeyShortcut? {
        var tokens = spelled.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // "cmd++" 指的是加号键本身，按 "+" 切分会留下两个空 token。
        if tokens.count > 2, tokens.suffix(2).allSatisfy(\.isEmpty) {
            tokens.removeLast(2)
            tokens.append("+")
        }
        guard let keyToken = tokens.popLast(), let keyCode = keyCode(named: keyToken) else {
            return nil
        }
        var modifiers = 0
        for token in tokens {
            if token == Self.hyperName, let hyperModifiers {
                modifiers |= hyperModifiers
            } else if let mask = Self.modifierMasks[token] {
                modifiers |= mask
            } else {
                return nil
            }
        }
        let commanding = modifiers & (cmdKey | optionKey | controlKey | kEventKeyModifierFnMask)
        guard commanding != 0 || KeyShortcut.isFunctionKey(keyCode) else { return nil }
        return KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers)
    }

    /// 由键码得到按键名称（优先具名键，其次基础字符，最后回退为原始键码）。
    private func keyName(for keyCode: Int) -> String {
        Self.namedKeys[keyCode] ?? characterByCode[keyCode] ?? Self.rawKeyPrefix + String(keyCode)
    }

    /// 由按键名称得到键码（支持具名键、基础字符与 `key-<code>` 原始形式）。
    private func keyCode(named name: String) -> Int? {
        if let code = Self.codeByName[name] ?? codeByCharacter[name] { return code }
        guard name.hasPrefix(Self.rawKeyPrefix),
            let code = Int(name.dropFirst(Self.rawKeyPrefix.count)), Self.keyCodes.contains(code)
        else { return nil }
        return code
    }

    // MARK: - Vocabulary

    private static let hyperName = "hyper"
    private static let doubleTapPrefix = "double-tap "
    private static let rawKeyPrefix = "key-"
    private static let keyCodes = 0..<128

    /// 按应用的 🌐⌃⌥⇧⌘ 顺序排列，使拼写出的组合键读起来与键帽一致。
    private static let writtenModifiers: [(mask: Int, name: String)] = [
        (kEventKeyModifierFnMask, "fn"), (controlKey, "ctrl"), (optionKey, "option"),
        (shiftKey, "shift"), (cmdKey, "cmd")
    ]

    private static let modifierMasks: [String: Int] = [
        "fn": kEventKeyModifierFnMask,
        "ctrl": controlKey, "control": controlKey,
        "option": optionKey, "opt": optionKey, "alt": optionKey,
        "shift": shiftKey,
        "cmd": cmdKey, "command": cmdKey
    ]

    /// 字符不可见，或与需要区分的其他键共用字符的按键。
    private static let namedKeys: [Int: String] = [
        kVK_Space: "space", kVK_Return: "return", kVK_ANSI_KeypadEnter: "enter", kVK_Tab: "tab",
        kVK_Delete: "delete", kVK_ForwardDelete: "forward-delete", kVK_Escape: "escape",
        kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up", kVK_DownArrow: "down",
        kVK_Home: "home", kVK_End: "end", kVK_PageUp: "page-up", kVK_PageDown: "page-down",
        kVK_Help: "help",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
        kVK_F13: "f13", kVK_F14: "f14", kVK_F15: "f15", kVK_F16: "f16", kVK_F17: "f17",
        kVK_F18: "f18", kVK_F19: "f19", kVK_F20: "f20",
        kVK_ANSI_Keypad0: "keypad-0", kVK_ANSI_Keypad1: "keypad-1", kVK_ANSI_Keypad2: "keypad-2",
        kVK_ANSI_Keypad3: "keypad-3", kVK_ANSI_Keypad4: "keypad-4", kVK_ANSI_Keypad5: "keypad-5",
        kVK_ANSI_Keypad6: "keypad-6", kVK_ANSI_Keypad7: "keypad-7", kVK_ANSI_Keypad8: "keypad-8",
        kVK_ANSI_Keypad9: "keypad-9", kVK_ANSI_KeypadDecimal: "keypad-decimal",
        kVK_ANSI_KeypadPlus: "keypad-plus", kVK_ANSI_KeypadMinus: "keypad-minus",
        kVK_ANSI_KeypadMultiply: "keypad-multiply", kVK_ANSI_KeypadDivide: "keypad-divide",
        kVK_ANSI_KeypadEquals: "keypad-equals", kVK_ANSI_KeypadClear: "keypad-clear"
    ]

    private static let codeByName = Dictionary(
        uniqueKeysWithValues: namedKeys.map { ($0.value, $0.key) })

    /// 判断一个字符是否可作为按键名拼写（可打印且非空白）。
    private static func isSpellable(_ name: String) -> Bool {
        !name.isEmpty
            && name.unicodeScalars.allSatisfy {
                $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace
            }
    }

    /// 把双击修饰键转为拼写名称。
    private static func name(of modifier: DoubleTapModifier) -> String {
        switch modifier {
        case .control: "ctrl"
        case .option: "option"
        case .shift: "shift"
        case .command: "cmd"
        }
    }

    /// 把具体修饰键（含侧别）转为拼写名称。
    private static func name(of key: ModifierKey) -> String {
        guard let side = key.side, let modifier = key.modifier else { return "globe" }
        return side.lowercased() + " " + name(of: modifier)
    }

    /// 由 "left cmd" 这类文本解析出具体修饰键。
    private static func modifierKey(named name: String) -> ModifierKey? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, let modifier = doubleTapModifier(named: String(parts[1])) else {
            return nil
        }
        return ModifierKey.allCases.first {
            $0.side?.lowercased() == String(parts[0]) && $0.modifier == modifier
        }
    }

    /// 由修饰键名称解析出可双击的修饰键类型。
    private static func doubleTapModifier(named name: String) -> DoubleTapModifier? {
        switch modifierMasks[name] {
        case controlKey: .control
        case optionKey: .option
        case shiftKey: .shift
        case cmdKey: .command
        default: nil
        }
    }
}
