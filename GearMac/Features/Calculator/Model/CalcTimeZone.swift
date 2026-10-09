// 文件职责：把自然语言时区/时刻短语（如 `5pm ldn in sf`、`time diff paris`）解析为跨时区时刻结果，并维护城市、别名与国家到时区的映射表。
// 分层：Model；只依赖 Foundation，标签不使用需要 Locale 的 API，不 import AppKit/SwiftUI。
import Foundation

/// 另一座城市的钟表时间（见 docs/features/calculator.md）。
enum CalcTimeZone {
    /// 入口：识别并解析时区/时刻短语，返回跨时区结果；不匹配时返回 nil。
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, language: AppLanguage = .english
    ) -> CalcResult? {
        guard raw.count <= 128, raw.contains(where: \.isWhitespace) else { return nil }
        let inputWords = raw.split(whereSeparator: \.isWhitespace)
        if let query = currentTimeQuery(inputWords.map { $0.lowercased() }) {
            return evaluate(query, now: now, calendar: calendar)
        }
        guard inputWords.count >= 2,
            inputWords.contains(where: { connectors.contains($0.lowercased()) })
                || parseClock(inputWords[0].lowercased()) != nil
                || parseClock(inputWords.prefix(2).joined().lowercased()) != nil
        else {
            return nil
        }
        // 由最后一个词决定：`10 km to mi` 同样带连接词。
        guard endsInZoneOrDuration(inputWords[inputWords.count - 1].lowercased()) else { return nil }

        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }

        if let difference = offsetBetween(query, now: now, calendar: calendar) { return difference }

        // 末尾的 `± <n> <unit>` 用于平移结果，因此 `5pm ldn in sf + 2h` 仍算一条查询。
        let (zoneQuery, offset) = splitOffset(query)
        let words = zoneQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }

        let target: TimeZone
        let leading: [String]
        var ahead: (count: Int, component: Calendar.Component)?
        if let connector = words.lastIndex(where: { $0 == "in" || $0 == "to" || $0 == "at" }) {
            let targetWords = Array(words[(connector + 1)...])
            guard !targetWords.isEmpty else { return nil }
            // `time in 4 hours` 在放时区的位置放了时长，因此用本机时区作答。
            if let zone = zone(named: targetWords) {
                target = zone
            } else if let duration = parseDuration(targetWords.joined(separator: " ")) {
                target = calendar.timeZone
                ahead = duration
            } else {
                return nil
            }
            leading = Array(words[0..<connector])
        } else {
            var sourceWords = words
            if sourceWords[1] == "am" || sourceWords[1] == "pm" {
                let meridiem = sourceWords.remove(at: 1)
                sourceWords[0] += meridiem
            }
            guard parseClock(sourceWords[0]) != nil,
                zone(named: Array(sourceWords.dropFirst())) != nil
            else { return nil }
            leading = sourceWords
            target = calendar.timeZone
        }

        guard
            var source = sourceMoment(
                leading, allowZoneConnector: ahead == nil, now: now, calendar: calendar)
        else { return nil }
        if let ahead {
            guard let shifted = calendar.date(byAdding: ahead.component, value: ahead.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }
        if let offset {
            guard
                let shifted = calendar.date(byAdding: offset.component, value: offset.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }

        guard
            let dayNote = dayOffsetNote(
                source, target: target, calendar: calendar, language: language)
        else { return nil }
        let time = clockString(source.date, zone: target, calendar: calendar)

        return CalcResult(
            expression: clockString(source.date, zone: source.zone, calendar: calendar),
            sourceBadge: label(for: source.zone),
            targetBadge: label(for: target),
            payload: .value(display: time + dayNote, copyText: time))
    }

    /// 识别「time/timezone (...)」形式的当前时刻查询并规范化为标准短语；不匹配时返回 nil。
    private static func currentTimeQuery(_ words: [String]) -> String? {
        if words.first == "time" || words.first == "timezone" {
            var place = Array(words.dropFirst())
            if words.first == "timezone", place.first == "in" { place.removeFirst() }
            if zone(named: place) != nil { return "time in \(place.joined(separator: " "))" }
        }

        let destination = words.firstIndex(of: "to") ?? words.endIndex
        var place = Array(words[..<destination])
        if place.suffix(2) == ["time", "zone"] {
            place.removeLast(2)
        } else if place.last == "time" || place.last == "timezone" {
            place.removeLast()
        } else {
            return nil
        }
        guard zone(named: place) != nil else { return nil }
        guard destination < words.endIndex else { return "time in \(place.joined(separator: " "))" }
        let target = Array(words[(destination + 1)...])
        guard zone(named: target) != nil else { return nil }
        return "time \(place.joined(separator: " ")) to \(target.joined(separator: " "))"
    }

    /// 把末尾的 `+ 2h` / `- 30 min` 从它作用的时区短语中切分出来。
    private static func splitOffset(
        _ query: String
    ) -> (String, (count: Int, component: Calendar.Component)?) {
        for separator in [" + ", " - "] {
            guard let range = query.range(of: separator, options: .backwards) else { continue }
            let tail = String(query[range.upperBound...])
            guard let duration = parseDuration(tail, impliesHours: true) else { continue }
            let sign = separator == " - " ? -1 : 1
            return (String(query[..<range.lowerBound]), (duration.count * sign, duration.component))
        }
        return (query, nil)
    }

    /// `2h`、`90 min`、`2 hours`：只接受小于一天的单位，因为时区答案是一个钟表时刻。
    private static func parseDuration(
        _ text: String, impliesHours: Bool = false
    ) -> (count: Int, component: Calendar.Component)? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let digits = compact.prefix { $0.isNumber }
        guard let count = Int(digits), count < 100_000 else { return nil }
        switch String(compact.dropFirst(digits.count)) {
        case "h", "hr", "hrs", "hour", "hours": return (count, .hour)
        case "m", "min", "mins", "minute", "minutes": return (count, .minute)
        case "s", "sec", "secs", "second", "seconds": return (count, .second)
        // 时钟答案下，裸写的 `+ 5` 只能解释为小时。
        case "" where impliesHours: return (count, .hour)
        default: return nil
        }
    }

    /// 已解析的源时刻：具体日期与其所属时区。
    private struct SourceMoment {
        let date: Date
        let zone: TimeZone
    }

    /// 判断短语结尾是时区名、时长，还是已知城市后缀（用于确认这确实是一条时区查询）。
    private static func endsInZoneOrDuration(_ tail: String) -> Bool {
        // 先折叠变音符号：时区标识符不带重音，而 `zürich`、`são paulo` 带。
        let folded = tail.folding(options: [.diacriticInsensitive], locale: nil)
        if zoneIdentifier(named: folded) != nil { return true }
        // `time in 4 hours` 以单位词结尾，因此裸单位词也算时长结尾。
        if durationUnits.contains(folded) || parseDuration(folded, impliesHours: true) != nil {
            return true
        }
        // 多词城市（如 "new york"）在此只露出最后一个词，因此允许已知后缀。
        return citySuffixes.contains(folded)
    }

    /// 时长单位词集合。
    private static let durationUnits: Set<String> = [
        "h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes",
        "s", "sec", "secs", "second", "seconds"
    ]

    /// 各表中所有多词名称的最后一个词，使 `in new york` 也能命中。
    private static let citySuffixes: Set<String> = {
        var tails: Set<String> = []
        for names in [cities.keys, aliases.keys, CountryZoneData.zones.keys] {
            for name in names where name.contains(" ") {
                if let last = name.split(separator: " ").last { tails.insert(String(last)) }
            }
        }
        return tails
    }()

    /// 时区短语里可出现的连接词集合。
    private static let connectors: Set<String> = ["in", "to", "at", "diff", "difference"]

    /// `diff paris`、`time diff paris`：某时区相对 Mac 本机时区的偏移量。
    private static func offsetBetween(
        _ query: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first == "time" { words.removeFirst() }
        guard words.count >= 2, words[0] == "diff" || words[0] == "difference",
            let target = zone(named: Array(words.dropFirst()))
        else { return nil }

        let home = calendar.timeZone
        let minutes =
            (target.secondsFromGMT(for: now) - home.secondsFromGMT(for: now)) / 60
        let sign = minutes < 0 ? "-" : "+"
        let whole = abs(minutes) / 60
        let part = abs(minutes) % 60
        let text = part == 0 ? "\(sign)\(whole)h" : "\(sign)\(whole)h \(part)m"

        return CalcResult(
            expression: clockString(now, zone: home, calendar: calendar),
            sourceBadge: label(for: home),
            targetBadge: label(for: target),
            payload: .value(
                display: "\(clockString(now, zone: target, calendar: calendar)) (\(text))",
                copyText: text))
    }

    /// 解析源时刻短语（时刻或 time/now/clock + 时区），支持 `in <时长>` 平移；解析失败返回 nil。
    private static func sourceMoment(
        _ words: [String], allowZoneConnector: Bool, now: Date, calendar: Calendar
    ) -> SourceMoment? {
        var words = words.filter { !["what", "whats", "the", "is", "it", "current"].contains($0) }

        // `time in 4 hours in sf`：前半段自带 `in <duration>`。
        var ahead: (count: Int, component: Calendar.Component)?
        if let connector = words.lastIndex(where: { $0 == "in" || $0 == "at" }),
            connector + 1 < words.count,
            let duration = parseDuration(words[(connector + 1)...].joined(separator: " "))
        {
            ahead = duration
            words = Array(words[0..<connector])
        }

        guard var head = words.first else { return nil }
        var rest = Array(words.dropFirst())
        if rest.first == "am" || rest.first == "pm" {
            guard !head.hasSuffix("am"), !head.hasSuffix("pm") else { return nil }
            head += rest.removeFirst()
        }
        guard head == "time" || head == "now" || head == "clock" || parseClock(head) != nil else {
            return nil
        }

        if allowZoneConnector, rest.first == "in" || rest.first == "at" {
            rest.removeFirst()
            guard !rest.isEmpty else { return nil }
        }
        guard let zone = rest.isEmpty ? calendar.timeZone : self.zone(named: rest) else { return nil }
        if head == "time" || head == "now" || head == "clock" {
            guard let ahead else { return SourceMoment(date: now, zone: zone) }
            guard let shifted = calendar.date(byAdding: ahead.component, value: ahead.count, to: now)
            else { return nil }
            return SourceMoment(date: shifted, zone: zone)
        }

        guard let clock = parseClock(head) else { return nil }
        var source = calendar
        source.timeZone = zone
        let day = source.dateComponents([.year, .month, .day], from: now)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.timeZone = zone
        guard let date = source.date(from: components) else { return nil }
        let resolved = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard resolved.year == components.year, resolved.month == components.month,
            resolved.day == components.day, resolved.hour == components.hour,
            resolved.minute == components.minute
        else { return nil }
        guard let ahead else { return SourceMoment(date: date, zone: zone) }
        guard let shifted = source.date(byAdding: ahead.component, value: ahead.count, to: date)
        else { return nil }
        return SourceMoment(date: shifted, zone: zone)
    }

    /// 解析 `5`、`5:30`、`5pm`、`17:00` 等时刻写法；带 am/pm 时限定 1–12 时，否则要求含冒号且 0–23 时。
    private static func parseClock(_ word: String) -> (hour: Int, minute: Int)? {
        var text = word
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        // 单独一个 ":" 切分后为空，因此首段不保证存在。
        guard let first = parts.first, let hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }

        guard let meridiem else {
            // 裸数字是搜索词（"time in 5"），因此只有写成时刻形式才算。
            guard text.contains(":"), (0...23).contains(hour) else { return nil }
            return (hour, minute)
        }
        guard (1...12).contains(hour) else { return nil }
        return (meridiem == "pm" ? (hour % 12) + 12 : hour % 12, minute)
    }

    /// 把词序列解析为 `TimeZone`：折叠变音符号后依次查别名、城市、国家表。
    private static func zone(named words: [String]) -> TimeZone? {
        // `são paulo`、`zürich` 是城市的自然拼写，而时区标识符不是。
        let phrase = words.joined(separator: " ")
            .folding(options: [.diacriticInsensitive], locale: nil)
        return zoneIdentifier(named: phrase).flatMap(TimeZone.init(identifier:))
    }

    /// 人工维护的别名优先于城市，城市优先于同拼写的国家。
    private static func zoneIdentifier(named phrase: String) -> String? {
        aliases[phrase] ?? cities[phrase] ?? CountryZoneData.zones[phrase]
    }

    /// Foundation 已内置 IANA 数据库，因此这里的城市表无需生成。
    private static let cities: [String: String] = {
        var table: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            table[city.replacingOccurrences(of: "_", with: " ").lowercased()] = identifier
        }
        return table
    }()

    /// 人工维护：`abbreviationDictionary` 不可用，它的 `BDT` 指的是孟加拉塔卡。
    private static let aliasGroups: [String: [String]] = [
        "UTC": ["utc", "zulu"],
        "GMT": ["gmt"],
        "America/New_York": [
            "est", "edt", "et", "usa", "nyc", "new york city", "boston", "washington", "dc", "miami",
            "atlanta",
            "philadelphia", "jfk", "atl", "bos", "mia", "ewr", "iad", "charlotte", "nashville", "orlando",
            "tampa", "pittsburgh", "cleveland", "cincinnati", "columbus", "baltimore", "raleigh",
            "indianapolis", "louisville"
        ],
        "America/Chicago": [
            "cst", "cdt", "ct", "austin", "dallas", "houston", "ord", "dfw", "iah", "minneapolis", "st louis",
            "kansas city", "milwaukee", "new orleans", "memphis", "oklahoma city", "san antonio"
        ],
        "America/Denver": ["mst", "mdt", "mt", "den", "salt lake city", "albuquerque", "boise"],
        "America/Los_Angeles": [
            "pst", "pdt", "pt", "la", "sf", "san francisco", "silicon valley", "seattle", "las vegas", "sfo",
            "lax", "sea", "san diego", "san jose", "portland", "sacramento", "fresno", "oakland"
        ],
        "Europe/Paris": [
            "cet", "cest", "cdg", "ory", "lyon", "marseille", "toulouse", "nice", "bordeaux", "nantes",
            "lille", "strasbourg"
        ],
        "Europe/London": [
            "bst", "ldn", "lhr", "lgw", "manchester", "birmingham", "liverpool", "leeds", "glasgow",
            "edinburgh", "bristol", "cardiff", "cambridge", "oxford", "belfast"
        ],
        "Asia/Kolkata": [
            "ist", "kolkata", "bengaluru", "bangalore", "mumbai", "delhi", "new delhi", "chennai",
            "hyderabad", "bom", "del", "blr", "pune", "ahmedabad", "jaipur", "surat", "lucknow", "kanpur",
            "nagpur", "goa", "kochi", "indore", "thane", "bhopal", "visakhapatnam", "vizag", "patna",
            "vadodara", "ghaziabad", "ludhiana", "agra", "nashik", "faridabad", "meerut", "rajkot",
            "varanasi", "srinagar", "aurangabad", "amritsar", "navi mumbai", "allahabad", "prayagraj",
            "ranchi", "howrah", "coimbatore", "jabalpur", "gwalior", "vijayawada", "jodhpur", "madurai",
            "raipur", "chandigarh", "guwahati", "mysore", "mysuru", "gurgaon", "gurugram", "noida", "cochin",
            "trivandrum", "thiruvananthapuram", "panaji", "dehradun", "udaipur", "pondicherry", "puducherry",
            "jamshedpur", "bhubaneswar", "cuttack", "siliguri", "dhanbad", "kota", "shimla", "tirupati"
        ],
        "Asia/Tokyo": [
            "jst", "osaka", "kyoto", "nrt", "hnd", "kix", "yokohama", "nagoya", "sapporo", "fukuoka", "kobe",
            "hiroshima", "sendai", "okinawa", "nara"
        ],
        "Asia/Seoul": ["kst", "icn", "busan", "incheon", "daegu"],
        "Australia/Sydney": ["aest", "aedt", "syd", "canberra", "newcastle"],
        "Asia/Singapore": ["sgp", "sin"],
        "Asia/Ho_Chi_Minh": ["saigon", "hcmc", "hanoi", "haiphong", "hue", "da nang"],
        "Europe/Berlin": [
            "munich", "frankfurt", "hamburg", "cologne", "fra", "muc", "txl", "ber", "hannover", "hanover",
            "stuttgart", "dusseldorf", "dortmund", "essen", "leipzig", "dresden", "bremen", "nuremberg",
            "nurnberg", "bonn", "mannheim", "karlsruhe", "freiburg", "munster", "augsburg", "kiel", "koln",
            "munchen"
        ],
        "Europe/Rome": [
            "milan", "fco", "mxp", "naples", "turin", "florence", "venice", "bologna", "genoa", "palermo",
            "verona"
        ],
        "Europe/Madrid": ["barcelona", "bcn", "valencia", "seville", "malaga", "bilbao", "zaragoza"],
        "Europe/Zurich": [
            "geneva", "zrh", "gva", "basel", "bern", "lausanne", "lucerne", "luzern", "winterthur",
            "st gallen", "lugano"
        ],
        "Europe/Moscow": ["st petersburg", "svo", "led"],
        "Europe/Kyiv": ["kyiv", "lviv", "odesa"],
        "Asia/Tel_Aviv": ["tel aviv", "tlv"],
        "Asia/Shanghai": [
            "shenzhen", "beijing", "guangzhou", "pvg", "pek", "chengdu", "tianjin", "wuhan", "xian",
            "hangzhou", "nanjing", "qingdao", "suzhou", "shenyang", "kunming", "xiamen"
        ],
        "Australia/Melbourne": ["melbourne", "mel"],
        "Australia/Brisbane": ["brisbane", "bne", "gold coast"],
        "Australia/Perth": ["perth", "per"],
        "America/Sao_Paulo": [
            "rio", "rio de janeiro", "gru", "brasilia", "salvador", "curitiba", "porto alegre",
            "belo horizonte", "recife"
        ],
        "America/Mexico_City": ["cdmx", "mexico city", "mex", "guadalajara", "puebla"],
        "Europe/Vienna": [
            "vie", "graz", "salzburg", "linz", "innsbruck", "klagenfurt", "villach", "wels", "st polten",
            "dornbirn", "bregenz", "wien"
        ],
        "Europe/Amsterdam": ["ams", "rotterdam", "the hague", "den haag", "eindhoven", "utrecht"],
        "Europe/Copenhagen": ["cph", "aarhus", "odense"],
        "Europe/Oslo": ["osl", "bergen", "trondheim"],
        "Europe/Stockholm": ["arn", "gothenburg", "malmo"],
        "Europe/Helsinki": ["hel", "tampere", "turku"],
        "Europe/Dublin": ["dub", "cork", "galway"],
        "Europe/Lisbon": ["lis", "porto"],
        "Europe/Athens": ["ath", "thessaloniki"],
        "Europe/Prague": ["prg", "brno", "ostrava"],
        "Europe/Warsaw": ["waw", "krakow", "gdansk", "wroclaw", "poznan", "lodz"],
        "Europe/Budapest": ["bud"],
        "Europe/Brussels": ["bru", "antwerp", "ghent", "bruges"],
        "Asia/Dubai": ["uae", "dxb", "auh", "sharjah"],
        "Asia/Qatar": ["doh", "doha"],
        "Asia/Hong_Kong": ["hkg"],
        "Asia/Bangkok": ["bkk", "phuket", "chiang mai"],
        "Asia/Kuala_Lumpur": ["kul", "penang", "johor bahru"],
        "Asia/Jakarta": ["cgk", "surabaya", "medan", "bandung", "denpasar", "bali"],
        "Asia/Manila": ["mnl", "cebu", "davao"],
        "Pacific/Auckland": ["akl", "wellington", "christchurch"],
        "America/Toronto": ["yyz", "yul", "ottawa", "quebec", "montreal"],
        "America/Vancouver": ["yvr", "victoria"],
        "America/Phoenix": ["phx"],
        "America/Argentina/Buenos_Aires": ["eze", "rosario", "mendoza"],
        "America/Santiago": ["scl", "valparaiso"],
        "America/Bogota": ["bog", "medellin", "cali", "cartagena"],
        "America/Lima": ["lim", "arequipa"],
        "Africa/Johannesburg": ["jnb", "cpt", "durban", "pretoria", "soweto"],
        "Africa/Cairo": ["cai", "alexandria", "giza"],
        "Africa/Nairobi": ["nbo", "mombasa"],
        "Africa/Lagos": ["los", "abuja", "kano", "ibadan"],
        "Africa/Casablanca": ["cmn", "marrakech", "rabat", "fes", "tangier"],
        "Europe/Istanbul": ["ankara", "izmir"],
        "Asia/Karachi": ["lahore", "islamabad", "faisalabad", "rawalpindi", "multan", "peshawar"],
        "America/Guayaquil": ["quito"],
        "Europe/Malta": ["valletta"],
        "Asia/Dhaka": ["chittagong", "chattogram"],
        "Asia/Riyadh": ["jeddah", "mecca", "medina", "dammam"],
        "Asia/Taipei": ["kaohsiung", "taichung"],
        "Asia/Kuwait": ["kuwait city"],
        "Asia/Bahrain": ["manama"],
        "Asia/Jerusalem": ["haifa"],
        "America/Edmonton": ["calgary"]
    ]

    /// 由上面的分组一次性拍平而来；日常编辑的是分组形式。
    private static let aliases: [String: String] = {
        var table: [String: String] = [:]
        table.reserveCapacity(aliasGroups.values.reduce(0) { $0 + $1.count })
        for (zone, names) in aliasGroups {
            for name in names { table[name] = zone }
        }
        return table
    }()

    /// 不使用 `localizedName`（它需要 `Locale`，在 `Model/` 中被禁止）。
    static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    /// 按时区与日历把日期格式化为钟表时间字符串（`jmm` 模板）。
    private static func clockString(_ date: Date, zone: TimeZone, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, template: "jmm")
    }

    /// 生成相对日期的后缀说明（明天/昨天/几天前/几天后）；同一天返回空串。
    private static func dayOffsetNote(
        _ source: SourceMoment, target: TimeZone, calendar: Calendar, language: AppLanguage
    ) -> String? {
        var here = calendar
        here.timeZone = source.zone
        var there = calendar
        there.timeZone = target
        // 在同一时区比较民用日期，避免时差与夏令时压缩天数差。
        var dates = calendar
        dates.timeZone = .gmt
        guard
            let from = dates.date(from: here.dateComponents([.era, .year, .month, .day], from: source.date)),
            let to = dates.date(from: there.dateComponents([.era, .year, .month, .day], from: source.date)),
            let days = dates.dateComponents([.day], from: from, to: to).day
        else { return nil }
        switch days {
        case 0: return ""
        case 1: return L10n.string(CalculatorKey.dayNoteTomorrow, language: language)
        case -1: return L10n.string(CalculatorKey.dayNoteYesterday, language: language)
        case ..<0:
            return String(
                format: L10n.string(CalculatorKey.dayNoteDaysAgo, language: language), -days)
        default:
            return String(
                format: L10n.string(CalculatorKey.dayNoteInDays, language: language), days)
        }
    }
}
