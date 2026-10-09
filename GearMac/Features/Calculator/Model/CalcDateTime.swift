// 文件职责：把自然语言的日期/时间查询（如 `tomorrow at 9am`、`3 days ago`、`monday in 3 weeks`）解析为计算结果。
// 分层：Model；不访问系统当前时间，`now` 与 `calendar` 均由调用方注入。
import Foundation

/// 日期/时间类查询的解析入口：识别各类自然语言句式并产出 CalcResult。
enum CalcDateTime {
    /// 一个不带运算的重复日期/时间短语应落在过去、未来还是最近的一次。
    private enum MomentBias { case future, past, nearest }

    /// 主入口：先做一次关键词扫描判断是否像日期/时间表达式，再按语法依次尝试解析。
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, language: AppLanguage = .english
    )
        -> CalcResult?
    {
        let echo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = echo.lowercased()
        guard !lowered.isEmpty else { return nil }

        // 只扫一遍词：应用搜索在每次按键都会付出这份开销。
        let signals = keywordSignals(lowered)
        let hasDigit = signals.contains(.digit)
        let hasUntil = signals.contains(.until)
        let hasSince = signals.contains(.since)
        let hasArith = signals.contains(.arithmetic) && signals.contains(.moment)
        let hasFromAgo = signals.contains(.fromAgo)
        let hasIn = signals.contains(.inWord)
        let hasTimestamp = signals.contains(.timestamp)
        // 指名的时刻需要限定词：单独的 `tomorrow` 会被当作应用搜索。
        let isBareMoment =
            signals.contains(.at) || signals.contains(.nextOrLast)
            || (hasDigit && signals.contains(.dayName) && namesADay(lowered))
            || CalcTimestamp.looksLikeISO(lowered)
        guard hasUntil || hasSince || hasArith || hasFromAgo || hasIn || isBareMoment || hasTimestamp else {
            return nil
        }

        let query = lowered.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if hasTimestamp || query.hasSuffix(" to date") && CalcTimestamp.looksLikeISO(query),
            let result = parseTimestamp(
                query, echo: echo, now: now, calendar: calendar, language: language)
        {
            return result
        }
        if hasUntil,
            let result = parseUntil(
                query, echo: echo, now: now, calendar: calendar, language: language)
        {
            return result
        }
        if hasSince,
            let result = parseSince(
                query, echo: echo, now: now, calendar: calendar, language: language)
        {
            return result
        }
        if hasArith,
            let result = parseArithmetic(
                query, echo: echo, now: now, calendar: calendar, language: language)
        {
            return result
        }
        if hasFromAgo, let result = parseOffset(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasIn, let result = parseWeekdayIn(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if isBareMoment, let result = bareMoment(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        return nil
    }

    /// 唯一能单独作答的词：它们各自指向一个时刻，而 `monday`、`july` 是会重现的。
    static func namedMoment(_ word: String, now: Date, calendar: Calendar) -> CalcResult? {
        let lowered = word.lowercased()
        switch lowered {
        case "now", "today", "tomorrow", "yesterday":
            return bareMoment(lowered, echo: word, now: now, calendar: calendar)
        case "time":
            let clock = CalcDateFormatters.string(
                from: now, calendar: calendar, zone: calendar.timeZone, template: "jmm")
            return CalcResult(
                expression: word,
                sourceBadge: dateString(now, now: now, calendar: calendar),
                targetBadge: CalcTimeZone.label(for: calendar.timeZone),
                payload: .value(display: clock, copyText: clock))
        default:
            return nil
        }
    }

    /// 关键词扫描得到的信号位集合：标记输入中出现了哪些语法线索。
    private struct Signals: OptionSet {
        let rawValue: Int
        static let digit = Signals(rawValue: 1 << 0)
        static let until = Signals(rawValue: 1 << 1)
        static let since = Signals(rawValue: 1 << 2)
        static let arithmetic = Signals(rawValue: 1 << 3)
        static let fromAgo = Signals(rawValue: 1 << 4)
        static let inWord = Signals(rawValue: 1 << 5)
        static let at = Signals(rawValue: 1 << 6)
        static let nextOrLast = Signals(rawValue: 1 << 7)
        static let timestamp = Signals(rawValue: 1 << 8)
        static let moment = Signals(rawValue: 1 << 9)
        static let dayName = Signals(rawValue: 1 << 10)
    }

    /// 对整段查询做一次关键词扫描，返回其包含的信号。
    private static func keywordSignals(_ query: String) -> Signals {
        var signals: Signals = []
        let words = query.split(whereSeparator: \.isWhitespace)
        for (index, word) in words.enumerated() {
            let isFirst = index == 0
            let isLast = index == words.count - 1
            switch word {
            case "till", "until", "til": if !isFirst, !isLast { signals.insert(.until) }
            case "since": if !isFirst, !isLast { signals.insert(.since) }
            case "+", "-": if !isFirst, !isLast { signals.insert(.arithmetic) }
            case "from": if !isFirst, !isLast { signals.insert(.fromAgo) }
            case "ago": if !isFirst { signals.insert(.fromAgo) }
            case "in": if !isFirst, !isLast { signals.insert(.inWord) }
            case "at": if !isFirst, !isLast { signals.insert(.at) }
            case "next", "last": if isFirst { signals.insert(.nextOrLast) }
            case "unix", "timestamp": signals.formUnion([.timestamp, .moment])
            default: break
            }
            var dots = 0
            var dashes = 0
            for byte in word.utf8 {
                if (48...57).contains(byte) { signals.insert(.digit) }
                if byte == 46 { dots += 1 }
                if byte == 45 { dashes += 1 }
                if byte == 58 || byte == 47 { signals.insert(.moment) }
            }
            if dots >= 2 { signals.formUnion([.dayName, .moment]) }
            if dashes >= 2 { signals.insert(.moment) }
            for letters in word.utf8.split(whereSeparator: { !(97...122).contains($0) }) {
                let name = String(bytes: letters, encoding: .utf8)!
                if monthByName[name] != nil { signals.formUnion([.dayName, .moment]) }
                if weekdayByName[name] != nil { signals.insert(.moment) }
                switch name {
                case "now", "today", "tomorrow", "yesterday", "noon", "midnight", "am", "pm":
                    signals.insert(.moment)
                default: break
                }
            }
        }
        return signals
    }

    /// 月份名旁边的日号，应用搜索不可能长这样——如 `25. aug`、`aug 25`。
    private static func namesADay(_ query: String) -> Bool {
        let atoms = atomize(query)
        guard atoms.count == 2 || atoms.count == 3 else { return atoms.count == 1 && isDottedDate(atoms) }
        let months = atoms.filter { monthByName[$0] != nil }.count
        let days = atoms.filter { ordinalDay($0) != nil }.count
        return months == 1 && days == atoms.count - 1
    }

    /// 单独的 `25.8.27`：三个点分部分，不可能读作一个数字。
    private static func isDottedDate(_ atoms: [String]) -> Bool {
        guard let only = atoms.first else { return false }
        let parts = only.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].count == 2 || parts[2].count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }

    /// `next monday`、`tomorrow`、`tomorrow at 9am`——完全不靠运算指名一个时刻。
    private static func bareMoment(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        guard let moment = parseMoment(query, now: now, calendar: calendar, bias: .nearest)
        else { return nil }
        let date = moment.date
        let hasTime = moment.hasTime
        let text = answerString(date, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(date, calendar: calendar),
            payload: .value(display: text, copyText: text))
    }

    /// `9am`、`5:30pm`、`14:00` 当作墙钟时间解析，不应用偏置。
    private static func parseMeridiemClock(_ text: String) -> (hour: Int, minute: Int)? {
        if text == "noon" { return (12, 0) }
        if text == "midnight" { return (0, 0) }
        var body = text
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body.removeLast(2)
        }
        body = body.trimmingCharacters(in: .whitespaces)
        guard let (hour, minute) = parseClock(body) else { return nil }
        guard let meridiem else {
            return (0...23).contains(hour) ? (hour, minute) : nil
        }
        guard (1...12).contains(hour) else { return nil }
        return (meridiem == "pm" ? (hour % 12) + 12 : hour % 12, minute)
    }

    /// `monday in 3 weeks`——该星期几，落在时长抵达的那一周内。
    private static func parseWeekdayIn(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        guard let range = query.range(of: " in ") else { return nil }
        let head = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard let weekday = weekdayByName[head],
            let durations = parseDurations(String(query[range.upperBound...])),
            durations.count == 1, let duration = durations.first,
            !duration.subDay, !duration.businessDays,
            let landing = calendar.date(
                byAdding: duration.component, value: duration.count,
                to: calendar.startOfDay(for: now))
        else { return nil }

        // 取抵达那一周内的星期几，使 `monday in 3 weeks` 就是那一周的周一。
        guard let week = calendar.dateInterval(of: .weekOfYear, for: landing),
            let result = shift(
                week.start, days: (weekday - calendar.firstWeekday + 7) % 7, calendar: calendar)
        else { return nil }

        let text = answerString(result, hasTime: false, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(display: text, copyText: text))
    }

    /// `5 weekdays from now`、`3 days from today`、`2 weeks ago`——时长在前面。
    private static func parseOffset(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let durationText: String
        let anchorText: String
        let sign: Int
        if let range = query.range(of: " from ") {
            durationText = String(query[..<range.lowerBound])
            anchorText = String(query[range.upperBound...])
            sign = 1
        } else if query.hasSuffix(" ago") {
            durationText = String(query.dropLast(4))
            anchorText = ""
            sign = -1
        } else {
            return nil
        }

        guard let durations = parseDurations(durationText) else { return nil }
        let subDay = durations.contains(where: \.subDay)
        let anchorPhrase = anchorText.isEmpty ? (subDay ? "now" : "today") : anchorText
        guard let anchor = parseMoment(anchorPhrase, now: now, calendar: calendar),
            let shifted = shift(anchor, by: durationText, op: sign < 0 ? "-" : "+", calendar: calendar)
        else { return nil }
        let result = shifted.date
        let hasTime = shifted.hasTime && (subDay || anchorPhrase != "now")
        let display = answerString(result, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(
                anchor.date, hasTime: hasTime, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(
                display: display, copyText: display))
    }

    /// 解析 `... until/till ...` 形式的区间数量。
    private static func parseUntil(
        _ query: String, echo: String, now: Date, calendar: Calendar, language: AppLanguage
    ) -> CalcResult? {
        guard let connector = [" until ", " till ", " til "].first(where: query.contains) else { return nil }
        return parseInterval(
            query, connector: connector, past: false, echo: echo, now: now, calendar: calendar,
            language: language)
    }

    /// 解析 `... since ...` 形式（锚点在过去）的区间数量。
    private static func parseSince(
        _ query: String, echo: String, now: Date, calendar: Calendar, language: AppLanguage
    ) -> CalcResult? {
        parseInterval(
            query, connector: " since ", past: true, echo: echo, now: now, calendar: calendar,
            language: language)
    }

    /// 以指定连接词拆分区间，按 `past` 决定基准时间在前还是在后。
    private static func parseInterval(
        _ query: String, connector: String, past: Bool, echo: String, now: Date, calendar: Calendar,
        language: AppLanguage
    ) -> CalcResult? {
        let parts = query.components(separatedBy: connector)
        guard parts.count == 2, let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar, bias: past ? .past : .future)
        else { return nil }
        let reference = unit.subDay ? now : calendar.startOfDay(for: now)
        let target = unit.subDay ? moment.date : calendar.startOfDay(for: moment.date)
        let start = past ? target : reference
        let end = past ? reference : target
        let value: Double
        switch unit.kind {
        case .day, .week:
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            value = Double(days) / (unit.kind == .week ? 7 : 1)
        case .subSecond:
            value = end.timeIntervalSince(start) / unit.seconds
        }
        let word = L10n.string(
            abs(value) == 1 ? unit.singularKey : unit.pluralKey, language: language)
        return CalcResult(
            expression: echo,
            sourceBadge: unit.subDay
                ? timeString(start, calendar: calendar) : dateString(start, now: now, calendar: calendar),
            targetBadge: unit.subDay
                ? timeString(end, calendar: calendar) : dateString(end, now: now, calendar: calendar),
            payload: .number(value, suffix: " \(word)"))
    }

    // MARK: - Grammars C & D: moment ± duration / moment − moment

    /// 解析带运算的时刻表达式：语法 C（时刻 ± 时长）与语法 D（时刻 − 时刻）。
    private static func parseArithmetic(
        _ query: String, echo: String, now: Date, calendar: Calendar, language: AppLanguage
    ) -> CalcResult? {
        var expression = query
        var targetUnit: UnitDef?
        for connector in [" to ", " in "] {
            if let range = expression.range(of: connector, options: .backwards),
                let unit = CalcUnits.byName[String(expression[range.upperBound...])], unit.category == .time
            {
                targetUnit = unit
                expression = String(expression[..<range.lowerBound])
                break
            }
        }
        let (left, operation, tail) = splitTerm(expression[...])
        guard let op = operation else { return nil }
        let right = String(tail)
        let firstTerm = splitTerm(tail).term
        let shifts = parseDurations(firstTerm) != nil || Double(firstTerm) != nil
        guard var base = parseMoment(left, now: now, calendar: calendar, bias: shifts ? .nearest : .future)
        else { return nil }
        if !shifts, base.hasTime {
            guard let local = parseMoment(left, now: now, calendar: calendar, bias: .nearest) else {
                return nil
            }
            base = local
        }

        // C：时刻 ± 时长，从左到右链式运算——第一个项之后的每一项都继续平移。
        if targetUnit == nil, let shifted = applyShifts(op, right, to: base, calendar: calendar) {
            let display = answerString(
                shifted.date, hasTime: shifted.hasTime, now: now, calendar: calendar)
            return CalcResult(
                expression: echo,
                sourceBadge: momentString(
                    base.date, hasTime: base.hasTime, now: now, calendar: calendar),
                targetBadge: weekdayName(shifted.date, calendar: calendar),
                payload: .value(display: display, copyText: display))
        }

        // D：时刻 − 时刻。两个不含字母的操作数（`5/2 - 1/2`）归计算器处理。
        guard op == "-",
            targetUnit != nil || base.hasTime || left.contains(where: \.isLetter)
                || right.contains(where: \.isLetter) || left.contains("-") || isDottedDate(atomize(left)),
            let other = parseMoment(
                right, now: now, calendar: calendar, bias: base.hasTime ? .nearest : .future)
        else {
            return nil
        }
        let hasTime = base.hasTime || other.hasTime
        let seconds = base.date.timeIntervalSince(other.date)
        let payload: CalcResult.Payload
        if let unit = targetUnit {
            payload = .measurement(seconds / unit.factor, unit: unit)
        } else if hasTime {
            let text = CalcFormatter.timespan(seconds, language: language)
            payload = .value(display: text, copyText: text)
        } else {
            let days =
                calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: other.date),
                    to: calendar.startOfDay(for: base.date)
                ).day ?? 0
            let text =
                "\(days) "
                + L10n.string(
                    abs(days) == 1 ? CalculatorKey.durationDay : CalculatorKey.durationDays,
                    language: language)
            payload = .value(display: text, copyText: text)
        }
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(base.date, hasTime: base.hasTime, now: now, calendar: calendar),
            targetBadge: targetUnit?.name
                ?? momentString(other.date, hasTime: other.hasTime, now: now, calendar: calendar),
            payload: payload)
    }

    /// 除非每个项都是时长，否则返回 nil，使语法 D 仍能看到尾随的时刻。
    private static func applyShifts(
        _ firstOperator: Character, _ tail: String, to base: Moment, calendar: Calendar
    ) -> Moment? {
        var moment = base
        var op = firstOperator
        var rest = Substring(tail)

        while true {
            let (term, nextOperator, remainder) = splitTerm(rest)
            guard let shifted = shift(moment, by: term, op: op, calendar: calendar) else {
                return nil
            }
            moment = shifted
            guard let nextOperator else { return moment }
            op = nextOperator
            rest = remainder
        }
    }

    /// 截到下一个带空格的 `+` / `-` 之前的文本、该运算符，以及其后的剩余部分。
    private static func splitTerm(
        _ text: Substring
    ) -> (term: String, nextOperator: Character?, remainder: Substring) {
        let plus = text.range(of: " + ")
        let minus = text.range(of: " - ")
        let next: (Range<Substring.Index>, Character)?
        switch (plus, minus) {
        case (let p?, let m?): next = p.lowerBound < m.lowerBound ? (p, "+") : (m, "-")
        case (let p?, nil): next = (p, "+")
        case (nil, let m?): next = (m, "-")
        default: next = nil
        }
        guard let (range, op) = next else { return (String(text), nil, text) }
        return (String(text[..<range.lowerBound]), op, text[range.upperBound...])
    }

    /// 把一个项作用到某个时刻：拼写的时长，或按该时刻自身单位理解的纯数字。
    private static func shift(
        _ moment: Moment, by term: String, op: Character, calendar: Calendar
    ) -> Moment? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        let phrase = Double(trimmed) == nil ? trimmed : "\(trimmed) \(moment.hasTime ? "hours" : "days")"
        guard let durations = parseDurations(phrase) else { return nil }
        var result = moment
        for duration in durations {
            let signed = op == "-" ? -duration.count : duration.count
            let date =
                duration.businessDays
                ? addBusinessDays(signed, to: result.date, calendar: calendar)
                : calendar.date(byAdding: duration.component, value: signed, to: result.date)
            guard let date, (1...9999).contains(calendar.component(.year, from: date)) else { return nil }
            result = Moment(date: date, hasTime: result.hasTime || duration.subDay)
        }
        return result
    }

    // MARK: - Moment parsing

    /// 一个已解析的时刻及其是否带时间信息。
    private struct Moment {
        let date: Date
        /// 短语是否指名了钟点（"9am"、"now"）——决定时间徽标是否展示。
        let hasTime: Bool
    }

    /// 解析时间戳查询：`<时刻> to unix|timestamp` 或 ISO/epoch 时间戳转日期。
    private static func parseTimestamp(
        _ query: String, echo: String, now: Date, calendar: Calendar, language: AppLanguage
    ) -> CalcResult? {
        if let range = query.range(of: " to ", options: .backwards),
            let scale = CalcTimestamp.scale(String(query[range.upperBound...]))
        {
            let source = String(query[..<range.lowerBound])
            let (term, op, tail) = splitTerm(source[...])
            guard var moment = parseMoment(term, now: now, calendar: calendar, bias: .nearest) else {
                return nil
            }
            if let op {
                guard let shifted = applyShifts(op, String(tail), to: moment, calendar: calendar) else {
                    return nil
                }
                moment = shifted
            }
            let timestamp = moment.date.timeIntervalSince1970 * scale
            let rounded = timestamp.rounded()
            let tolerance = moment.date.timeIntervalSinceReferenceDate.ulp * scale
            let whole = abs(timestamp - rounded) <= tolerance ? rounded : timestamp.rounded(.down)
            guard let value = Int64(exactly: whole)
            else { return nil }
            let text = String(value)
            return CalcResult(
                expression: echo,
                sourceBadge: L10n.string(CalculatorKey.badgeDate, language: language),
                targetBadge: L10n.string(
                    scale == 1 ? CalculatorKey.badgeUnixSeconds : CalculatorKey.badgeUnixMilliseconds,
                    language: language),
                payload: .value(display: CalcFormatter.grouped(text), copyText: text))
        }
        let source = query.hasSuffix(" to date") ? String(query.dropLast(8)) : query
        guard CalcTimestamp.isoDate(source) != nil || CalcTimestamp.epochDate(source) != nil else {
            return nil
        }
        return bareMoment(source, echo: echo, now: now, calendar: calendar)
    }

    /// 把短语解析为一个具体时刻，`bias` 决定同名日期取过去/未来/最近的那次。
    private static func parseMoment(
        _ phrase: String, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        if let date = CalcTimestamp.isoDate(phrase) ?? CalcTimestamp.epochDate(phrase) {
            return Moment(date: date, hasTime: true)
        }
        if let range = phrase.range(of: " at ") {
            let dayPhrase = String(phrase[..<range.lowerBound])
            let atoms = atomize(dayPhrase)
            let recurring =
                weekdayByName[dayPhrase] != nil || monthByName[dayPhrase] != nil
                || (atoms.count == 2 && namesADay(dayPhrase))
                || (atoms.count == 1 && dayPhrase.split(separator: "/").count == 2)
            guard let clock = parseMeridiemClock(String(phrase[range.upperBound...])),
                let day = parseMoment(
                    dayPhrase, now: now, calendar: calendar,
                    bias: recurring && bias != .nearest ? .future : bias)
            else { return nil }
            var anchor = day.date
            if recurring, bias != .nearest,
                let candidate = calendar.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: anchor),
                bias == .future ? candidate <= now : candidate > now
            {
                guard let reference = shift(now, days: bias == .future ? 1 : -1, calendar: calendar),
                    let shifted = parseMoment(dayPhrase, now: reference, calendar: calendar, bias: bias)
                else { return nil }
                anchor = shifted.date
            }
            guard
                let date = calendar.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: anchor),
                calendar.isDate(date, inSameDayAs: anchor),
                calendar.component(.hour, from: date) == clock.hour,
                calendar.component(.minute, from: date) == clock.minute
            else { return nil }
            return Moment(date: date, hasTime: true)
        }
        let atoms = atomize(phrase)
        switch atoms.count {
        case 1:
            return parseSingle(atoms[0], now: now, calendar: calendar, bias: bias)
        case 2:
            return parsePair(atoms[0], atoms[1], now: now, calendar: calendar, bias: bias)
        case 3:
            return parseTriple(atoms[0], atoms[1], atoms[2], calendar: calendar)
        default:
            return nil
        }
    }

    /// `august 26 2026` / `26 august 2026`——月份名同时带日和年。
    private static func parseTriple(
        _ a: String, _ b: String, _ c: String, calendar: Calendar
    ) -> Moment? {
        guard let year = Int(c) else { return nil }
        let month: Int
        let day: Int
        if let named = monthByName[a], let value = ordinalDay(b) {
            (month, day) = (named, value)
        } else if let named = monthByName[b], let value = ordinalDay(a) {
            (month, day) = (named, value)
        } else {
            return nil
        }
        guard let date = makeDate(fullYear(year), month, day, calendar) else { return nil }
        return Moment(date: date, hasTime: false)
    }

    /// 解析单个原子：今天/明天/昨天、正午/午夜、星期名、月份名或数字日期。
    private static func parseSingle(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        switch atom {
        case "now": return Moment(date: now, hasTime: true)
        case "today": return Moment(date: sod, hasTime: false)
        case "tomorrow":
            return shift(sod, days: 1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "yesterday":
            return shift(sod, days: -1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "noon": return clockMoment(hour: 12, minute: 0, now: now, calendar: calendar, bias: bias)
        case "midnight":
            return clockMoment(hour: 0, minute: 0, now: now, calendar: calendar, bias: bias)
        default: break
        }
        if let weekday = weekdayByName[atom] {
            return nextWeekday(
                weekday, offsetToFuture: false, past: bias == .past, now: now, calendar: calendar)
        }
        if let month = monthByName[atom] {
            return monthDayMoment(month: month, day: 1, now: now, calendar: calendar, bias: bias)
        }
        return parseDateAtom(atom, now: now, calendar: calendar, bias: bias)
    }

    /// 解析两个原子：数字+月份、钟点+am/pm、next/last+星期或月份。
    private static func parsePair(
        _ a: String, _ b: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        // 数字 + 月份  /  月份 + 数字  →  该月中的某一天
        if let month = monthByName[b], let day = ordinalDay(a) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if let month = monthByName[a], let day = ordinalDay(b) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        // 钟点 + am/pm  →  今天的时间（已过则顺延到明天）
        if b == "am" || b == "pm", let (hour, minute) = parseClock(a) {
            guard (1...12).contains(hour) else { return nil }
            let adjusted = b == "pm" ? (hour % 12) + 12 : hour % 12
            return clockMoment(
                hour: adjusted, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        // next / last  +  星期或月份
        if a == "next" || a == "last" {
            if let weekday = weekdayByName[b] {
                return nextWeekday(
                    weekday, offsetToFuture: a == "next", past: a == "last", now: now,
                    calendar: calendar)
            }
            if let month = monthByName[b] {
                return monthDayMoment(
                    month: month, day: 1, now: now, calendar: calendar,
                    bias: a == "last" ? .past : .future)
            }
        }
        return nil
    }

    /// 带自身分隔符的单个数字原子：`14:00`、`2027-04-09`、`9/4`、`9/4/2027`。
    private static func parseDateAtom(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        if atom.contains(":") {
            guard let (hour, minute) = parseClock(atom) else { return nil }
            return clockMoment(hour: hour, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        let separator: Character = atom.contains("-") ? "-" : atom.contains("/") ? "/" : "."
        let parts = atom.split(separator: separator)
        guard (2...3).contains(parts.count), let first = Int(parts[0]), let second = Int(parts[1]) else {
            return nil
        }
        if separator == "/", parts.count == 2 {
            return monthDayMoment(month: first, day: second, now: now, calendar: calendar, bias: bias)
        }
        guard parts.count == 3, let third = Int(parts[2]) else { return nil }
        let year: Int
        let month: Int
        let day: Int
        switch separator {
        case "-":
            guard first > 31 else { return nil }
            (year, month, day) = (first, second, third)
        case "/":
            (year, month, day) = (fullYear(third), first, second)
        default:
            guard parts[2].count == 2 || parts[2].count == 4 else { return nil }
            (year, month, day) = (fullYear(third), second, first)
        }
        guard let date = makeDate(year, month, day, calendar) else { return nil }
        return Moment(date: date, hasTime: false)
    }

    // MARK: - Moment builders

    /// 构建当天某个钟点对应的时刻，并按 `bias` 向前/向后顺延。
    private static func clockMoment(
        hour: Int, minute: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let sod = calendar.startOfDay(for: now)
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sod)
        else { return nil }
        switch bias {
        case .future:
            if date <= now, let next = shift(date, days: 1, calendar: calendar) { date = next }
        case .past:
            if date > now, let prev = shift(date, days: -1, calendar: calendar) { date = prev }
        case .nearest:
            break
        }
        return Moment(date: date, hasTime: true)
    }

    /// `month` 月指定的一天，按 `bias` 解析到今年、明年或去年。
    private static func monthDayMoment(
        month: Int, day: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = makeDate(year, month, day, calendar) else { return nil }
        let sod = calendar.startOfDay(for: now)
        switch bias {
        case .future:
            if thisYear >= sod { return Moment(date: thisYear, hasTime: false) }
            guard let nextYear = makeDate(year + 1, month, day, calendar) else { return nil }
            return Moment(date: nextYear, hasTime: false)
        case .past:
            if thisYear <= sod { return Moment(date: thisYear, hasTime: false) }
            guard let lastYear = makeDate(year - 1, month, day, calendar) else { return nil }
            return Moment(date: lastYear, hasTime: false)
        // 相差几天的那个日期，比一年后的同一天更可能是用户想说的。
        case .nearest:
            return Moment(date: thisYear, hasTime: false)
        }
    }

    /// 算到下一个（或上一个）指定星期几。
    private static func nextWeekday(
        _ weekday: Int, offsetToFuture: Bool, past: Bool = false, now: Date, calendar: Calendar
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        let today = calendar.component(.weekday, from: sod)
        if past {
            var back = (today - weekday + 7) % 7
            if back == 0 { back = 7 }
            return shift(sod, days: -back, calendar: calendar).map {
                Moment(date: $0, hasTime: false)
            }
        }
        var ahead = (weekday - today + 7) % 7
        if ahead == 0 && offsetToFuture { ahead = 7 }
        return shift(sod, days: ahead, calendar: calendar).map { Moment(date: $0, hasTime: false) }
    }

    // MARK: - Durations

    /// 时长单位的大类：不足一天、天、周。
    private enum DurKind { case subSecond, day, week }

    /// 一个时长单位的秒数、单复数词条与所属大类。
    private struct DurUnit {
        let seconds: Double
        let singularKey: CalculatorKey
        let pluralKey: CalculatorKey
        let kind: DurKind
        var subDay: Bool { kind == .subSecond }
    }

    /// 从短语末尾的词识别时长单位（`s`/`min`/`h`/`day`/`wk` 等）。
    private static func durationUnit(_ phrase: String) -> DurUnit? {
        guard let last = phrase.split(separator: " ").last.map(String.init) else { return nil }
        switch last {
        case "s", "sec", "secs", "second", "seconds":
            return DurUnit(
                seconds: 1, singularKey: .durationSecond, pluralKey: .durationSeconds,
                kind: .subSecond)
        case "min", "mins", "minute", "minutes":
            return DurUnit(
                seconds: 60, singularKey: .durationMinute, pluralKey: .durationMinutes,
                kind: .subSecond)
        case "h", "hr", "hrs", "hour", "hours":
            return DurUnit(
                seconds: 3600, singularKey: .durationHour, pluralKey: .durationHours,
                kind: .subSecond)
        case "d", "day", "days":
            return DurUnit(
                seconds: 86400, singularKey: .durationDay, pluralKey: .durationDays, kind: .day)
        case "wk", "week", "weeks":
            return DurUnit(
                seconds: 604800, singularKey: .durationWeek, pluralKey: .durationWeeks, kind: .week)
        default:
            return nil
        }
    }

    /// 一段已解析的时长：数量、对应日历分量与特殊标志。
    private struct DurationPhrase {
        let count: Int
        let component: Calendar.Component
        let subDay: Bool
        /// 跳过周末日而不计入，使结果落在周一至周五。
        var businessDays = false
    }

    /// 把短语解析为一组时长（`3 days 2 hours`），无法完全解析则返回 nil。
    private static func parseDurations(_ phrase: String) -> [DurationPhrase]? {
        let atoms = atomize(phrase)
        var durations: [DurationPhrase] = []
        var index = 0
        while index + 1 < atoms.count {
            guard let amount = Double(atoms[index]), amount.isFinite else { return nil }
            var name = atoms[index + 1]
            index += 2
            if index < atoms.count, businessDayPhrases.contains(name + atoms[index]) {
                name += atoms[index]
                index += 1
            }
            let component: Calendar.Component
            let count: Double
            let subDay: Bool
            let businessDays = businessDayPhrases.contains(name)
            if businessDays {
                component = .day
                count = amount
                subDay = false
            } else if ["mo", "month", "months", "yr", "year", "years"].contains(name) {
                component = name.hasPrefix("mo") ? .month : .year
                count = amount
                subDay = false
            } else if let unit = durationUnit(name) {
                component = unit.subDay ? .second : .day
                count = amount * (unit.subDay ? unit.seconds : unit.seconds / 86400)
                subDay = unit.subDay
                guard subDay || amount.rounded() == amount else { return nil }
            } else {
                return nil
            }
            guard let value = Int(exactly: count), value != .min else { return nil }
            durations.append(
                DurationPhrase(count: value, component: component, subDay: subDay, businessDays: businessDays)
            )
        }
        return index == atoms.count && !durations.isEmpty ? durations : nil
    }

    // MARK: - Formatting

    /// 把时刻格式化为「日期[ at 时间]」。
    private static func momentString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    )
        -> String
    {
        let day = dateString(date, now: now, calendar: calendar)
        return hasTime ? "\(day) at \(timeString(date, calendar: calendar))" : day
    }

    /// 星期会移到徽标上，因此作答的时刻以日期本身开头。
    private static func answerString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    ) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = format(
            date, calendar: calendar, pattern: sameYear ? "d MMMM" : "d MMMM, yyyy")
        return hasTime ? "\(day) at \(timeString(date, calendar: calendar))" : day
    }

    /// 格式化日期，同年省略年份。
    private static func dateString(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(
            date, calendar: calendar, pattern: sameYear ? "EEEE, d MMMM" : "EEEE, d MMMM, yyyy")
    }

    /// 格式化时间；秒为 0 时省略秒位。
    private static func timeString(_ date: Date, calendar: Calendar) -> String {
        let template = calendar.component(.second, from: date) == 0 ? "jmm" : "jmmss"
        return CalcDateFormatters.string(
            from: date, calendar: calendar, zone: calendar.timeZone, template: template)
    }

    /// 答案自身的星期名，日期格式本身不会拼出来。
    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        format(date, calendar: calendar, pattern: "EEEE")
    }

    /// 按 pattern 与日历所在时区格式化日期。
    private static func format(_ date: Date, calendar: Calendar, pattern: String) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, pattern: pattern)
    }

    // MARK: - Low-level helpers

    /// 拆成字母段与数字段；":"、"/"、"-"、"." 留在数字段内部。
    private static func atomize(_ text: String) -> [String] {
        var atoms: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            if !current.isEmpty { atoms.append(current) }
            current = ""
        }
        for ch in text {
            if ch == " " {
                flush()
                continue
            }
            let isNumeric = ch.isNumber || ch == ":" || ch == "/" || ch == "-" || ch == "."
            let isLetter = ch.isLetter
            if current.isEmpty {
                current.append(ch)
                currentIsNumber = isNumeric && !isLetter
            } else if isLetter && currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = false
            } else if isNumeric && !isLetter && !currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = true
            } else {
                current.append(ch)
            }
        }
        flush()
        return atoms
    }

    /// 日号，兼容德语/奥地利日期写法中的序数点：`28. aug`。
    private static func ordinalDay(_ atom: String) -> Int? {
        Int(atom.hasSuffix(".") ? String(atom.dropLast()) : atom)
    }

    /// 解析 `h:mm` 或纯小时数为时/分，分钟越界时返回 nil。
    private static func parseClock(_ atom: String) -> (hour: Int, minute: Int)? {
        if atom.contains(":") {
            let parts = atom.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                (0...59).contains(minute)
            else {
                return nil
            }
            return (hour, minute)
        }
        guard let hour = Int(atom) else { return nil }
        return (hour, 0)
    }

    /// 由年/月/日构造日期，并反向校验各分量未被日历规整，非法日期返回 nil。
    @inline(never) private static func makeDate(
        _ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar
    )
        -> Date?
    {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day,
            calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }

    private static func shift(_ date: Date, days: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// 整周一下子跳完；只有周末对齐与剩余天数才逐天行走。
    private static func addBusinessDays(_ count: Int, to date: Date, calendar: Calendar) -> Date? {
        guard (-10_000...10_000).contains(count) else { return nil }
        let step = count < 0 ? -1 : 1
        var remaining = abs(count)
        var cursor = date
        while remaining > 0, isWeekend(cursor, calendar: calendar) {
            guard let next = shift(cursor, days: step, calendar: calendar) else { return nil }
            cursor = next
            if !isWeekend(cursor, calendar: calendar) { remaining -= 1 }
        }
        guard let jumped = shift(cursor, days: remaining / 5 * 7 * step, calendar: calendar) else {
            return nil
        }
        cursor = jumped
        remaining %= 5
        while remaining > 0 {
            guard let next = shift(cursor, days: step, calendar: calendar) else { return nil }
            cursor = next
            if !isWeekend(cursor, calendar: calendar) { remaining -= 1 }
        }
        return cursor
    }

    /// 判断该日是否为周末（星期日或星期六）。
    private static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// 像日期选择器那样展开两位数年份；四位数年份原样返回。
    private static func fullYear(_ year: Int) -> Int {
        if year >= 100 { return year }
        return year <= 68 ? 2000 + year : 1900 + year
    }

    /// 月份名（全拼与常见缩写）到月份数字的映射。
    private static let monthByName: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4,
        "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]

    /// 表示工作日的各种拼接写法。
    private static let businessDayPhrases: Set<String> = [
        "businessday", "businessdays", "workday", "workdays", "workingday", "workingdays",
        "weekday", "weekdays"
    ]

    /// 公历星期编号（星期日 = 1）。
    private static let weekdayByName: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]
}
