// 文件职责：定义可本地化键协议（LocalizableKey）、单条译文（L10nEntry）与按语言的解析函数。
// 分层：Model（本地化）；仅 Foundation。每个功能自带键类型与词表，互不引用，便于并行维护。
import Foundation

/// 一条译文：英文与简体中文。
struct L10nEntry: Sendable {
    let en: String
    let zh: String

    init(_ en: String, _ zh: String) {
        self.en = en
        self.zh = zh
    }
}

/// 可本地化键：一个功能把自己的键写成 `enum`，并给出对应词表。
///
/// 约定：`rawValue` 为点号命名空间（如 `"settings.tab.general"`），在整个应用内唯一；
/// 词表以 `rawValue` 为键。新增文案时，键与两种语言一起补在自己的词表里。
protocol LocalizableKey: Sendable {
    var rawValue: String { get }
    static var table: [String: L10nEntry] { get }
}

/// 文案解析：按语言取译文，缺键时回退英文，再回退键名本身。
enum L10n {
    /// 取某键在指定语言下的译文。`language` 会被解析为具体语言。
    static func string<K: LocalizableKey>(_ key: K, language: AppLanguage) -> String {
        entry(key.rawValue, in: K.table, language: language)
    }

    /// 在给定词表中按语言解析；缺键回退英文，再回退键名。
    static func entry(
        _ rawValue: String, in table: [String: L10nEntry], language: AppLanguage
    ) -> String {
        guard let entry = table[rawValue] else { return rawValue }
        switch language.resolved() {
        case .chinese: return entry.zh
        default: return entry.en
        }
    }
}
