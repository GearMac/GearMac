// 文件职责：解析日期选择器中的预设项与手输日期表达式（如 "tomorrow at 10am"），并生成候选行。
// 分层：Model；纯函数式逻辑，时钟与日历均作为参数注入，不 import AppKit/SwiftUI。
import Foundation

/// 预设项与手输日期（如 "tomorrow at 10am"）；时钟与日历均由外部注入。
enum ExtensionDateExpression {
    /// 选择器中的一行：名称、它代表的日期，以及该日期的可读描述。
    struct Suggestion: Equatable, Identifiable {
        let title: String
        /// nil 表示清空该字段，这正是 "No Date" 的含义。
        let date: Date?
        /// 右侧列：解析出的日期；清空行则为空。
        let detail: String?

        var id: String { title }
    }

    /// 选择器在未输入任何内容时打开即显示的项。
    static func presets(now: Date, calendar: Calendar, includesTime: Bool) -> [Suggestion] {
        var rows: [Suggestion] = [Suggestion(title: "No Date", date: nil, detail: nil)]
        let today = calendar.startOfDay(for: now)
        let offsets: [(String, Int)] = [("Today", 0), ("Tomorrow", 1), ("Yesterday", -1)]
        for (title, days) in offsets {
            guard let date = calendar.date(byAdding: .day, value: days, to: today) else { continue }
            rows.append(
                Suggestion(title: title, date: date, detail: detail(for: date, calendar: calendar)))
        }
        // 接下来四个工作日，使得不输日期也能选到整周。
        for offset in 2...5 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let name = weekdayName(date, calendar: calendar)
            rows.append(
                Suggestion(title: name, date: date, detail: detail(for: date, calendar: calendar)))
        }
        _ = includesTime
        return rows
    }

    /// 针对已输入文本的行：先是对它的解析结果，再是与之匹配的预设项。
    static func suggestions(
        query: String, now: Date, calendar: Calendar, includesTime: Bool
    ) -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let presets = presets(now: now, calendar: calendar, includesTime: includesTime)
        guard !trimmed.isEmpty else { return presets }

        var rows: [Suggestion] = []
        if let parsed = parse(trimmed, now: now, calendar: calendar) {
            rows.append(
                Suggestion(
                    title: trimmed, date: parsed,
                    detail: detail(for: parsed, calendar: calendar, includesTime: includesTime)))
        }
        // 输入文本点名的预设项仍然值得提供，但不能重复。
        for preset in presets where preset.title.localizedCaseInsensitiveContains(trimmed) {
            guard !rows.contains(where: { $0.date == preset.date }) else { continue }
            rows.append(preset)
        }
        return rows
    }

    /// "tomorrow"、"next friday"、"in 3 days"、"5 sep"，均可选附带 "at 10am"。
    static func parse(_ expression: String, now: Date, calendar: Calendar) -> Date? {
        let lowered = expression.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }

        // 时间部分附在短语其余部分所解析出的那一天上。
        let (dayPhrase, time) = splitTime(lowered, calendar: calendar)
        guard let day = parseDay(dayPhrase, now: now, calendar: calendar) else { return nil }
        guard let time else { return day }
        return calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    // MARK: - Days

    /// 解析日期短语（不含时间部分）。
    private static func parseDay(_ phrase: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let words = phrase.split(separator: " ").map(String.init)
        // 日期短语为空意味着 "today at <time>"，即裸时间所表达的含义。
        guard !words.isEmpty else { return today }

        switch words.joined(separator: " ") {
        case "today", "now": return today
        case "tomorrow", "tmr": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }

        // "in 3 days" / "in 2 weeks" / "in 1 month"
        if words.first == "in", words.count >= 3, let amount = Int(words[1]) {
            return calendar.date(byAdding: unit(words[2]), value: amount, to: today)
        }
        // "3 days" 省略介词时含义相同。
        if words.count >= 2, let amount = Int(words[0]) {
            if let unit = knownUnit(words[1]) {
                return calendar.date(byAdding: unit, value: amount, to: today)
            }
            // "5 sep"——一个日号加一个月名。
            if let month = monthNumber(words[1]) {
                return date(day: amount, month: month, onOrAfter: today, calendar: calendar)
            }
        }
        // "sep 5"，同一个日期的另一种写法。
        if words.count >= 2, let month = monthNumber(words[0]), let amount = Int(words[1]) {
            return date(day: amount, month: month, onOrAfter: today, calendar: calendar)
        }
        // "next friday" / "friday"——两种写法都指向即将到来的那个；"next" 仅额外跳过同日匹配。
        let wantsNext = words.first == "next"
        let name = wantsNext ? words.dropFirst().joined(separator: " ") : words.joined(separator: " ")
        if let weekday = weekdayNumber(name, calendar: calendar) {
            return nextDate(weekday: weekday, after: today, calendar: calendar)
        }
        return nil
    }

    /// 始终向前：星期名指的是即将到来的那一天，而非刚过去的那一天。
    private static func nextDate(weekday: Int, after today: Date, calendar: Calendar) -> Date? {
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return nil
    }

    /// 只给日号和月份时指下一个该日期，因此 12 月的 "5 jan" 会落到明年。
    private static func date(
        day: Int, month: Int, onOrAfter today: Date, calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year], from: today)
        components.month = month
        components.day = day
        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate >= today { return candidate }
        return calendar.date(byAdding: .year, value: 1, to: candidate)
    }

    /// 把单位词解析为 `Calendar.Component`；无法识别时默认按天处理。
    private static func unit(_ word: String) -> Calendar.Component {
        knownUnit(word) ?? .day
    }

    /// 把单位词（单复数）映射为 `Calendar.Component`；无法识别时返回 nil。
    private static func knownUnit(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    // MARK: - Times

    private struct Time {
        let hour: Int
        let minute: Int
    }

    /// 拆分 "<日期短语> at <时间>"，同时兼顾结尾处裸写的 "10am"。
    private static func splitTime(_ phrase: String, calendar: Calendar) -> (String, Time?) {
        if let range = phrase.range(of: " at ") {
            let day = String(phrase[phrase.startIndex..<range.lowerBound])
            let rest = String(phrase[range.upperBound...])
            return (day, parseTime(rest))
        }
        // 短语末尾带时间、但没有 "at"——例如 "tomorrow 10am"。
        let words = phrase.split(separator: " ").map(String.init)
        if let last = words.last, let time = parseTime(last), words.count > 1 {
            return (words.dropLast().joined(separator: " "), time)
        }
        if let only = words.first, words.count == 1, let time = parseTime(only) {
            return ("", time)
        }
        return (phrase, nil)
    }

    /// "10am"、"10:30"、"22:15"、"7 pm"。
    private static func parseTime(_ text: String) -> Time? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        var body = cleaned
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body = String(body.dropLast(2))
        }
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, var hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else if parts.count == 1 {
            // 裸数字只有在写成时间形式（"10:00"）时才算时间，单独的 "10" 不算。
            return nil
        }
        return Time(hour: hour, minute: minute)
    }

    // MARK: - Naming

    /// 返回某个日期对应的完整星期名（如 "Friday"）。
    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return calendar.weekdaySymbols[index]
    }

    /// 把星期名（完整或缩写）转为 `Calendar` 的星期序号（1 表示周日）；无法识别时返回 nil。
    private static func weekdayNumber(_ name: String, calendar: Calendar) -> Int? {
        let symbols = calendar.weekdaySymbols.map { $0.lowercased() }
        if let index = symbols.firstIndex(of: name) { return index + 1 }
        let short = calendar.shortWeekdaySymbols.map { $0.lowercased() }
        if let index = short.firstIndex(of: name) { return index + 1 }
        return nil
    }

    /// 把月名（完整或至少三字母的前缀缩写）转为月份序号；无法识别时返回 nil。
    private static func monthNumber(_ name: String) -> Int? {
        let months = [
            "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december"
        ]
        if let index = months.firstIndex(of: name) { return index + 1 }
        if let index = months.firstIndex(where: { $0.hasPrefix(name) && name.count >= 3 }) {
            return index + 1
        }
        return nil
    }

    /// 解析出的日期在选择器右侧列的呈现方式。
    static func detail(
        for date: Date, calendar: Calendar, includesTime: Bool = false
    ) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        let day = date.formatted(format)
        guard includesTime else { return day }
        var timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
        timeFormat.calendar = calendar
        timeFormat.timeZone = calendar.timeZone
        return day + "  " + date.formatted(timeFormat)
    }
}
