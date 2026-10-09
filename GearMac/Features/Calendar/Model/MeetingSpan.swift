// 文件职责：定义议程读取的时间跨度枚举（今天/今明两天/未来七天），及其区间计算与描述文案。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，区间按传入 Calendar 的时区计算。
import Foundation

/// GearMac 读取的天数（含今天），使查询范围与描述它的每句话保持一致。
enum MeetingSpan: Int, CaseIterable, Identifiable, Sendable {
    case today = 1
    case todayAndTomorrow = 2
    case nextSevenDays = 7

    /// `CaseIterable` 要求的具体类型标识。
    var id: Int { rawValue }

    /// 该跨度的展示标题（英文）；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .today: return "Today"
        case .todayAndTomorrow: return "Today and Tomorrow"
        case .nextSevenDays: return "Next 7 Days"
        }
    }

    /// 按界面语言给出的展示标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: CalendarKey =
            switch self {
            case .today: .spanToday
            case .todayAndTomorrow: .spanTodayAndTomorrow
            case .nextSevenDays: .spanNextSevenDays
            }
        return L10n.string(key, language: language)
    }

    /// 按界面语言给出的所有格描述。
    func localizedPossessivePhrase(_ language: AppLanguage) -> String {
        let key: CalendarKey =
            switch self {
            case .today: .spanPossessiveToday
            case .todayAndTomorrow: .spanPossessiveTodayAndTomorrow
            case .nextSevenDays: .spanPossessiveNextSevenDays
            }
        return L10n.string(key, language: language)
    }

    /// 按界面语言给出的选择式描述。
    func localizedOrPhrase(_ language: AppLanguage) -> String {
        let key: CalendarKey =
            switch self {
            case .today: .spanOrToday
            case .todayAndTomorrow: .spanOrTodayAndTomorrow
            case .nextSevenDays: .spanOrNextSevenDays
            }
        return L10n.string(key, language: language)
    }

    /// 从今天零点到跨度结束日的零点，使用日历自身的时区。
    func interval(from now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.dateInterval(of: .day, for: now)?.start,
            let end = calendar.date(byAdding: .day, value: rawValue, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// 所有格描述（如「today's and tomorrow's」），用于命名所读取事件的句子（英文）。
    var possessivePhrase: String {
        switch self {
        case .today: return "today's"
        case .todayAndTomorrow: return "today's and tomorrow's"
        case .nextSevenDays: return "the next 7 days'"
        }
    }

    /// 选择式描述（如「today or tomorrow」），用于用「and」会读起来不通的句子（英文）。
    var orPhrase: String {
        switch self {
        case .today: return "today"
        case .todayAndTomorrow: return "today or tomorrow"
        case .nextSevenDays: return "in the next 7 days"
        }
    }
}
