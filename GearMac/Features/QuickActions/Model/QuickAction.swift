// 文件职责：用一个枚举统一内置与自建快捷动作，向上提供统一的 id、标题、图标与行为查询。
// 分层：Model；纯声明式枚举，不依赖 AppKit/SwiftUI。
import Foundation

/// 快捷动作的统一抽象：要么是内置动作，要么是自建动作。
enum QuickAction: Hashable, Identifiable, Sendable {
    case builtIn(BuiltInQuickAction)
    case custom(CustomQuickAction)

    static let fixGrammar = QuickAction.builtIn(.fixGrammar)
    static let rewrite = QuickAction.builtIn(.rewrite)
    static let translate = QuickAction.builtIn(.translate)
    static let summarize = QuickAction.builtIn(.summarize)
    static let decide = QuickAction.builtIn(.decide)

    static let allBuiltIn: [QuickAction] = BuiltInQuickAction.allCases.filter(\.isAvailable).map(QuickAction.builtIn)

    /// 稳定标识：内置用 rawValue，自建用 entryID。
    var id: String {
        switch self {
        case .builtIn(let action): return action.rawValue
        case .custom(let action): return action.entryID
        }
    }

    /// 若为内置动作则返回其枚举值，否则 nil。
    var builtInAction: BuiltInQuickAction? {
        guard case .builtIn(let action) = self else { return nil }
        return action
    }

    /// 若为自建动作则返回其数据结构，否则 nil。
    var customAction: CustomQuickAction? {
        guard case .custom(let action) = self else { return nil }
        return action
    }

    /// 面向用户的标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .builtIn(let action): return action.localizedTitle(language)
        case .custom(let action): return action.name
        }
    }

    /// 英语标题：供尚未接入界面语言的调用方使用。
    var title: String { localizedTitle(.english) }

    var symbol: String {
        switch self {
        case .builtIn(let action): return action.symbol
        case .custom(let action): return action.symbol
        }
    }

    /// 处理过程中展示给用户的标题。
    func localizedProgressTitle(_ language: AppLanguage) -> String {
        switch self {
        case .builtIn(let action): return action.localizedProgressTitle(language)
        case .custom(let action): return action.name + "…"
        }
    }

    /// 英语处理中标题：供尚未接入界面语言的调用方使用。
    var progressTitle: String { localizedProgressTitle(.english) }

    var alwaysPreviews: Bool { builtInAction?.alwaysPreviews ?? false }

    var showsDiff: Bool { builtInAction?.showsDiff ?? false }

    var usesTranslationFramework: Bool { builtInAction?.usesTranslationFramework ?? false }
}
