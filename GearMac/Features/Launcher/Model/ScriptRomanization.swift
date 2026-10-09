// 文件职责：把中文、日文、韩文、西里尔文等名称转写为拉丁读法，供查询折叠使用，并按文字类型分派规则。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 其他文字的名称会被输入成什么，按文字分派处理，因为 ICU 对它们都无法直接胜任。
enum ScriptRomanization {
    /// 值得单独制定规则的文字；其余文字 ICU 的通用转换已能很好处理。
    enum Script: Sendable {
        case han
        case japanese
        case hangul
        case cyrillic
        case other
    }

    /// 以单个空格分隔的词，并已折叠；名称本就是拉丁字母时返回 nil。
    static func latin(_ name: String) -> String? {
        guard let script = script(of: name) else { return nil }
        let reading: String? =
            switch script {
            case .han: transform(name, .mandarinToLatin)
            // 只对假名做罗马化：ICU 会把汉字按普通话读，得到的词是错误的。
            case .japanese: transform(dropping(name, in: hanRanges), .toLatin)
            case .hangul, .other: transform(name, .toLatin)
            case .cyrillic: cyrillicReading(of: name)
            }
        guard let reading else { return nil }
        let spaced = reading.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let folded = FuzzyMatch.normalized(spaced)
        return folded.isEmpty || folded == FuzzyMatch.normalized(name) ? nil : folded
    }

    /// 第一个拥有专属规则的文字；假名优先于汉字，使日文标题能被正确分派。
    static func script(of name: String) -> Script? {
        var hasHan = false
        var hasHangul = false
        var hasCyrillic = false
        var hasOther = false
        for scalar in name.unicodeScalars {
            if contains(kanaRanges, scalar) { return .japanese }
            if contains(hanRanges, scalar) {
                hasHan = true
            } else if contains(
                hangulRanges, scalar)
            {
                hasHangul = true
            } else if contains(cyrillicRanges, scalar) {
                hasCyrillic = true
            } else if scalar.value > 0x24F, scalar.properties.isAlphabetic {
                hasOther = true
            }
        }
        if hasHan { return .han }
        if hasHangul { return .hangul }
        if hasCyrillic { return .cyrillic }
        return hasOther ? .other : nil
    }

    /// ICU 的西里尔转写是学术式的——`Яндекс` 会变成 `Ândeks`，而非用户输入的 `yandex`。
    private static func cyrillicReading(of name: String) -> String {
        var result = ""
        for character in name.lowercased() {
            if let latin = cyrillicLatin[character] {
                result += latin
            } else if character.isLetter || character.isNumber {
                result.append(character)
            } else {
                result.append(" ")
            }
        }
        return result
    }

    /// 西里尔字母到用户实际输入形式的拉丁映射表。
    private static let cyrillicLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "ґ": "g", "д": "d", "е": "e", "ё": "yo", "є": "ye",
        "ж": "zh", "з": "z", "и": "i", "і": "i", "ї": "yi", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ў": "u", "ф": "f",
        "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
        "э": "e", "ю": "yu", "я": "ya"
    ]

    /// 调用 ICU 的字符串转换，并做与全局一致的折叠。
    private static func transform(_ value: String, _ transform: StringTransform) -> String? {
        value.applyingTransform(transform, reverse: false)?
            .folding(options: FuzzyMatch.folding, locale: nil)
    }

    /// 剔除指定码位范围内的字符，用于从日文标题中去掉汉字。
    private static func dropping(_ value: String, in ranges: [ClosedRange<UInt32>]) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { !contains(ranges, $0) }))
    }

    /// 判断码位是否落在给定范围内。
    private static func contains(_ ranges: [ClosedRange<UInt32>], _ scalar: Unicode.Scalar) -> Bool {
        ranges.contains { $0.contains(scalar.value) }
    }

    /// 汉字专用区、基本区与兼容表意文字。
    private static let hanRanges: [ClosedRange<UInt32>] = [
        0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF
    ]
    /// 平假名、片假名与片假名语音扩展。
    private static let kanaRanges: [ClosedRange<UInt32>] = [
        0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF
    ]
    /// 谚文字母、兼容字母与音节区。
    private static let hangulRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF
    ]
    /// 西里尔文基本区与其扩展。
    private static let cyrillicRanges: [ClosedRange<UInt32>] = [0x0400...0x052F]
}
