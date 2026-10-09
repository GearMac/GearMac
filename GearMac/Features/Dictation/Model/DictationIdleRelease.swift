// 文件职责：定义听写模型闲置多久后从内存中释放的选项。
// 分层：Model/纯枚举（Int 原始值即分钟数）；不执行副作用。
import Foundation

/// 闲置释放时长；rawValue 为分钟数，never 为 0 表示不释放。
enum DictationIdleRelease: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case oneMinute = 1
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case twentyMinutes = 20
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Self { self }
    /// 设置界面中的显示标题（按 rawValue 拼出分钟数）。
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .never: return L10n.string(DictationKey.idleNever, language: language)
        case .oneMinute: return L10n.string(DictationKey.idleOneMinute, language: language)
        case .oneHour: return L10n.string(DictationKey.idleOneHour, language: language)
        default:
            return String(
                format: L10n.string(DictationKey.idleMinutes, language: language), rawValue)
        }
    }
}
