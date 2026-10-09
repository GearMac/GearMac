// 文件职责：定义创建事件弹窗收集的草稿数据及其校验、起止时间计算与偏移/时长文案标签。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，不触及日历。
import Foundation

/// Create Event 弹窗收集的数据，此时还未对日历做任何改动。
struct EventDraft: Sendable, Equatable {
    var title: String = ""
    /// 事件距离现在多少分钟后开始；0 表示「Now」。
    var startOffsetMinutes: Int = 0
    var durationMinutes: Int = 30

    /// 可供选择的开始偏移（分钟）。
    static let startOffsets = [0, 15, 30, 60]
    /// 可供选择的时长（分钟）。
    static let durations = [15, 30, 45, 60]

    /// 标题为空是唯一不能写入的情况；其余字段都有默认值。
    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 去除首尾空白后的标题。
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 给定当前时间时的开始时间。
    func start(from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(startOffsetMinutes * 60))
    }

    /// 给定当前时间时的结束时间。
    func end(from now: Date) -> Date {
        start(from: now).addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    /// 把开始偏移分钟数转为展示标签，0 时特殊显示为「Now」。
    static func label(startOffset minutes: Int) -> String {
        minutes == 0 ? "Now" : label(duration: minutes)
    }

    /// 把分钟数转为展示标签：不足一小时显示分钟，否则显示小时。
    static func label(duration minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr"
    }

    /// 把开始偏移分钟数转为按界面语言展示的标签，0 时特殊显示为「Now」。
    static func localizedLabel(startOffset minutes: Int, language: AppLanguage) -> String {
        minutes == 0
            ? L10n.string(CalendarKey.draftNow, language: language)
            : localizedLabel(duration: minutes, language: language)
    }

    /// 把分钟数转为按界面语言展示的标签：不足一小时显示分钟，否则显示小时。
    static func localizedLabel(duration minutes: Int, language: AppLanguage) -> String {
        String(
            format: L10n.string(
                minutes < 60 ? CalendarKey.draftMinutesFormat : CalendarKey.draftHoursFormat,
                language: language),
            minutes < 60 ? minutes : minutes / 60)
    }
}
