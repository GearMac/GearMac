// 文件职责：定义从 EventKit 拍平出来的单次会议事件模型（含时间、日历、链接与颜色）及其 entryID 编解码。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，以 sRGB 分量代替平台颜色类型。
import Foundation

/// 一次日历事件实例，从 EventKit 拍平而来，使任何 EventKit 专有类型都不会抵达视图层。
struct MeetingEvent: Identifiable, Hashable, Sendable {
    /// 每次实例唯一：重复事件的各个实例共享同一个 event identifier。
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isDeclined: Bool
    let calendarID: String
    let calendarName: String
    let calendarColor: CalendarColor?
    /// EventKit 的 `calendarItemIdentifier` —— Calendar.app 的 `ical://` URL 唯一接受的句柄。
    let calendarItemID: String
    let link: MeetingLink?

    private static let entryPrefix = "meeting:"

    /// 带前缀的列表项标识，供 UI 列表使用。
    var entryID: String { Self.entryPrefix + id }

    /// 从列表项标识还原事件 id，前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryPrefix) else { return nil }
        return String(entryID.dropFirst(entryPrefix.count))
    }

    /// 事件在给定时刻是否正在进行中。
    func isInProgress(now: Date) -> Bool { start <= now && now < end }

    /// 存储层在事件没有标题时写入的占位文案；界面按语言替换它，因此此处保持英文。
    static let missingTitlePlaceholder = "(No Title)"

    /// 展示用标题：占位文案按界面语言替换，其余标题原样返回。
    func localizedTitle(_ language: AppLanguage) -> String {
        title == Self.missingTitlePlaceholder
            ? L10n.string(CalendarKey.eventNoTitle, language: language) : title
    }
}

extension MeetingEvent {
    /// 所属日历的颜色，以 sRGB 分量表示，使 Model 无需依赖 AppKit。
    struct CalendarColor: Hashable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }
}
