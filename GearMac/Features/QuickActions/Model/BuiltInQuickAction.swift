// 文件职责：定义四个内置快捷动作（修语法、改写、翻译、总结）及其标题、图标与行为元数据。
// 分层：Model；纯声明式枚举，不依赖 AppKit/SwiftUI。
import Foundation

/// 内置快捷动作的种类，行为差异通过下方计算属性描述。
enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case translate
    case summarize
    case decide

    var id: String { rawValue }

    /// 面向用户的标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .fixGrammar: return L10n.string(QuickActionsKey.builtInFixGrammar, language: language)
        case .rewrite: return L10n.string(QuickActionsKey.builtInRewrite, language: language)
        case .translate: return L10n.string(QuickActionsKey.builtInTranslate, language: language)
        case .summarize: return L10n.string(QuickActionsKey.builtInSummarize, language: language)
        case .decide: return L10n.string(QuickActionsKey.builtInDecide, language: language)
        }
    }

    /// 英语标题：供尚未接入界面语言的调用方（如启动器命令目录）使用。
    var title: String { localizedTitle(.english) }

    var symbol: String {
        switch self {
        case .fixGrammar: return "textformat"
        case .rewrite: return "wand.and.sparkles"
        case .translate: return "translate"
        case .summarize: return "text.line.3.summary"
        case .decide: return "checklist"
        }
    }

    /// 处理过程中展示给用户的标题文案。
    func localizedProgressTitle(_ language: AppLanguage) -> String {
        switch self {
        case .fixGrammar:
            return L10n.string(QuickActionsKey.progressFixGrammar, language: language)
        case .rewrite: return L10n.string(QuickActionsKey.progressRewrite, language: language)
        case .translate: return L10n.string(QuickActionsKey.progressTranslate, language: language)
        case .summarize: return L10n.string(QuickActionsKey.progressSummarize, language: language)
        case .decide: return L10n.string(QuickActionsKey.progressDecide, language: language)
        }
    }

    /// 英语处理中标题：供尚未接入界面语言的调用方使用。
    var progressTitle: String { localizedProgressTitle(.english) }

    /// 是否在当前系统上可用：翻译依赖 macOS 26 的 Translation 会话构造器，旧系统不展示该动作。
    /// 本属性是该功能域唯一的系统判断点，所有展示入口（主列表、启动器、设置页）都复用它。
    var isAvailable: Bool {
        if case .translate = self { return isTranslationAvailable }
        return true
    }

    /// 翻译需要 `TranslationSession(installedSource:)`，仅 macOS 26 提供。
    private var isTranslationAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 是否始终先预览结果（总结因会丢失原文而固定预览）。
    var alwaysPreviews: Bool { self == .summarize || self == .decide }

    /// 默认是否直接替换原文（修语法默认直接替换，无预览）。
    var replacesDirectlyByDefault: Bool { self == .fixGrammar }

    /// 结果是否以 diff（原文/改后对比）形式展示。
    var showsDiff: Bool { self == .fixGrammar || self == .rewrite }

    /// 是否走 Apple 翻译框架而非模型。
    var usesTranslationFramework: Bool { self == .translate }

    /// 是否允许自定义指令覆盖；Decide 的问题集在 AI 设置里编辑，不共用这个入口。
    var takesInstructionOverride: Bool {
        self == .fixGrammar || self == .rewrite || self == .summarize
    }
}
