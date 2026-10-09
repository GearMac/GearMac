// 文件职责：定义“哪场会议值得展示、是否到时间”的统一判定窗口，提供议程过滤、卡片选取、可加入选取与倒计时文案。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，时间均以注入的 `now` 为准。
import Foundation

/// 哪场会议值得展示、以及是否已到时间。每次读取时钟都使用注入的 `now`。
struct UpcomingWindow: Sendable {
    let leadMinutes: Int

    /// 提前量对应的秒数。
    private var lead: TimeInterval { TimeInterval(leadMinutes * 60) }

    /// 规則只在此处维护，使卡片、快捷键、日程与启动器不会出现差异。
    static func agenda(from events: [MeetingEvent], now: Date) -> [MeetingEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    /// 宽限期不会超过会议本身，使站立会到点即从卡片消失。
    func carded(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        Self.agenda(from: events, now: now).first {
            $0.link != nil && now >= $0.start - lead && now < min($0.start + lead, $0.end)
        }
    }

    /// 先回答卡片，使快捷键总是加入屏幕上正在展示的那场会议。
    func joinable(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        if let carded = carded(from: events, now: now) { return carded }
        let linked = Self.agenda(from: events, now: now).filter { $0.link != nil }
        return linked.first { $0.isInProgress(now: now) } ?? linked.first { $0.start > now }
    }

    /// 把距开始的时长转为倒计时文案，已开始则返回「Now」。
    static func countdown(to start: Date, now: Date, language: AppLanguage = .english) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 {
            return String(
                format: L10n.string(CalendarKey.timeInFormat, language: language),
                duration(delta, rounding: .up, language: language))
        }
        return L10n.string(CalendarKey.timeNow, language: language)
    }

    /// 行内胶囊标签的内容。
    struct RowPill: Equatable, Sendable {
        let text: String
        let isImminent: Bool
    }

    /// 行的胶囊标签：当天倒计时到午夜后改用日期，使明天的会议不会被误认为今天。
    static func rowPill(
        for event: MeetingEvent, now: Date, calendar: Calendar,
        language: AppLanguage = .english
    ) -> RowPill? {
        if event.isInProgress(now: now) {
            return RowPill(
                text: L10n.string(CalendarKey.timeNow, language: language), isImminent: true)
        }
        let delta = event.start.timeIntervalSince(now)
        guard delta > 0 else { return nil }
        let isImminent = delta <= 60 * 60
        guard isImminent || calendar.isDate(event.start, inSameDayAs: now) else {
            return RowPill(text: dayLabel(event.start, calendar: calendar), isImminent: false)
        }
        return RowPill(
            text: countdown(to: event.start, now: now, language: language), isImminent: isImminent)
    }

    /// 非今天的日期标签（星期缩写 + 月日）。
    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        date.formatted(calendar.formatStyle.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// 会议已进行超过五分钟后，菜单栏改称剩余时间。
    static func menuBarCountdown(
        for event: MeetingEvent, now: Date, language: AppLanguage = .english
    ) -> String {
        if now < event.start { return countdown(to: event.start, now: now, language: language) }
        if now < event.start.addingTimeInterval(5 * 60) {
            return L10n.string(CalendarKey.timeNow, language: language)
        }
        if now < event.end {
            return String(
                format: L10n.string(CalendarKey.timeLeftFormat, language: language),
                duration(event.end.timeIntervalSince(now), rounding: .down, language: language))
        }
        return L10n.string(CalendarKey.timeNow, language: language)
    }

    /// 把秒数转为「N min」或「N hr」形式的可读时长。
    private static func duration(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule,
        language: AppLanguage = .english
    ) -> String {
        let minutes = max(1, Int((interval / 60).rounded(rounding)))
        guard minutes > 60 else {
            return String(
                format: L10n.string(CalendarKey.timeMinutesFormat, language: language), minutes)
        }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        return String(format: L10n.string(CalendarKey.timeHoursFormat, language: language), hours)
    }
}
