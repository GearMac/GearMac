// 文件职责：词典功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 词典页面、动作菜单与空态文案的键。
enum DictionaryKey: String, LocalizableKey {
    case copyDefinition = "dictionary.action.copyDefinition"
    case openInDictionary = "dictionary.action.openInDictionary"
    case emptyPrompt = "dictionary.empty.prompt"
    case emptyNoDefinition = "dictionary.empty.noDefinition"

    static let table: [String: L10nEntry] = [
        DictionaryKey.copyDefinition.rawValue: L10nEntry("Copy Definition", "复制释义"),
        DictionaryKey.openInDictionary.rawValue: L10nEntry("Open in Dictionary", "在词典中打开"),
        DictionaryKey.emptyPrompt.rawValue: L10nEntry(
            "Type a word to define", "输入要查询的单词"),
        DictionaryKey.emptyNoDefinition.rawValue: L10nEntry(
            "No definition found", "未找到释义"),
    ]
}
