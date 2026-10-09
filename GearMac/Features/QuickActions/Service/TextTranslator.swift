// 文件职责：基于 Apple Translation 框架与 NaturalLanguage 实现文本翻译及语言可用性查询。
// 分层：Service；仅使用已安装的语言对，未安装的语言由用户在系统设置里下载。
import Foundation
import NaturalLanguage
import Translation

/// `TranslationError` 是 macOS 26.4 才有的，而部署下限为 26.0，因此这里的失败保持纯 `Error`。
enum TextTranslator {
    /// 翻译可能出现的失败原因。
    enum Failure: LocalizedError, Equatable {
        case undetectableSource
        case unsupported
        case notInstalled(language: String)
        case failed

        var errorDescription: String? {
            switch self {
            case .undetectableSource:
                return "The language of the selected text could not be identified."
            case .unsupported:
                return "Apple's translator does not support this language pair."
            case .notInstalled(let language):
                return "\(language) needs to be downloaded before it can be used."
            case .failed:
                return "The text could not be translated."
            }
        }

        /// 按界面语言解析的面向用户错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .undetectableSource:
                return L10n.string(QuickActionsKey.translateUndetectable, language: language)
            case .unsupported:
                return L10n.string(QuickActionsKey.translateUnsupported, language: language)
            case .notInstalled(let target):
                return String(
                    format: L10n.string(QuickActionsKey.translateNotInstalled, language: language),
                    target)
            case .failed:
                return L10n.string(QuickActionsKey.translateFailed, language: language)
            }
        }
    }

    /// `TranslationSession(installedSource:)` 需要一个语言对象，而可用性接口只报状态。
    static func sourceLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: dominant.rawValue)
    }

    /// 仅限已安装的语言对：缺失的语言要到系统设置里下载，绝不在这里触发。
    /// 入口展示已由 `BuiltInQuickAction.isAvailable` 过滤；此处兜底拦截存量动作或外部触发
    /// （URL scheme、旧快捷指令）绕过菜单直接到达的路径。
    static func translate(_ text: String, to target: Locale.Language) async throws -> String {
        guard #available(macOS 26.0, *) else { throw Failure.unsupported }
        guard let source = sourceLanguage(of: text) else { throw Failure.undetectableSource }
        guard !source.isEquivalent(to: target) else { return text }
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw Failure.notInstalled(language: displayName(of: target))
        case .unsupported:
            throw Failure.unsupported
        @unknown default:
            throw Failure.unsupported
        }
        do {
            let session = TranslationSession(installedSource: source, target: target)
            return try await session.translate(text).targetText
        } catch {
            throw Failure.failed
        }
    }

    /// 取最小形式而非最大形式：最大形式会把 `es` 写成“西班牙语（拉丁洲、西班牙）”塞进菜单。
    static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    /// 用框架自带的语言列表，使选择器不会提供一个到点才失败的组合。
    static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
            .sorted { displayName(of: $0) < displayName(of: $1) }
    }
}
