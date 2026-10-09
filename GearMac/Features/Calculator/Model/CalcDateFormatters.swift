// 文件职责：为计算结果提供复用的 DateFormatter 缓存，按 pattern/template、时区、locale、小时制与日历标识组合键值格式化日期。
// 分层：Model；无副作用，仅维护线程安全的内存缓存。
import Foundation

/// 跨调用复用：新建一个 formatter 约 160 µs，而复用只需约 0.5 µs。
enum CalcDateFormatters {
    /// 格式布局：固定 pattern 或交由 locale 解析的 template。
    private enum Layout: Hashable {
        case pattern(String)
        case template(String)
    }

    /// 缓存键：除布局、时区、locale 与日历外还包含小时制。
    private struct Key: Hashable {
        let layout: Layout
        let zone: String
        let locale: String
        /// 不属于 `locale.identifier`，否则 24 小时制切换会命中旧 formatter。
        let hourCycle: Locale.HourCycle
        let calendar: Calendar.Identifier
    }

    /// 整体清空而非逐项淘汰：键只是少量 pattern 加一个时区。
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: DateFormatter] = [:]

    /// 按固定 pattern 格式化日期，如 `EEEE, d MMMM`。
    static func string(from date: Date, calendar: Calendar, zone: TimeZone, pattern: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .pattern(pattern))
    }

    /// 用于时钟时间：模板中的 `j` 交由 locale 与 24 小时制在 `h a` 和 `HH` 之间选择。
    static func string(from date: Date, calendar: Calendar, zone: TimeZone, template: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .template(template))
    }

    /// 真正执行缓存查找与格式化，缓存未命中时新建 DateFormatter 并写入。
    private static func string(
        from date: Date, calendar: Calendar, zone: TimeZone, layout: Layout
    ) -> String {
        let locale = calendar.locale ?? Locale(identifier: "en_US")
        let key = Key(
            layout: layout, zone: zone.identifier, locale: locale.identifier,
            hourCycle: locale.hourCycle, calendar: calendar.identifier)

        lock.lock()
        defer { lock.unlock() }
        if let formatter = cache[key] { return formatter.string(from: date) }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        // 跟随注入日历的 locale，使星期/月份名称与用户语言一致。
        formatter.locale = locale
        switch layout {
        case .pattern(let pattern): formatter.dateFormat = pattern
        case .template(let template):
            formatter.setLocalizedDateFormatFromTemplate(template)
            // ICU 会在 AM/PM 前放 U+202F；换成普通空格，使粘贴出的答案保持纯文本。
            formatter.dateFormat = formatter.dateFormat.replacing("\u{202F}", with: " ")
        }
        // 只有一张时区表加少量 pattern，上限受语法可格式化范围所限。
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = formatter
        return formatter.string(from: date)
    }
}
