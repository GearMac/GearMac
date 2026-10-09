// 文件职责：对话保留期选项（7 天/30 天/3 个月/永久）及其过期时间线计算。
// 分层：Model；纯时间计算，不得 import AppKit/SwiftUI。
import Foundation

/// 以天数为原始值；`forever` 取负值，使未设置键读出的 0 不落在任何 case 上。
enum AIRetention: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case threeMonths = 90
    case forever = -1

    var id: Int { rawValue }

    /// 设置界面中的选项名称。
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .week: return L10n.string(AIKey.retentionWeek, language: language)
        case .month: return L10n.string(AIKey.retentionMonth, language: language)
        case .threeMonths: return L10n.string(AIKey.retentionThreeMonths, language: language)
        case .forever: return L10n.string(AIKey.retentionForever, language: language)
        }
    }

    /// 早于该时刻的对话已过期不应保留；
    /// `forever` 时返回 `nil`，表示没有任何内容会过期。
    func cutoff(from now: Date) -> Date? {
        self == .forever ? nil : now.addingTimeInterval(-TimeInterval(rawValue) * 86_400)
    }
}
