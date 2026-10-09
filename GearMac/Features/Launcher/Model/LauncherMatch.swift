// 文件职责：实现启动器查询与文本的对齐评分（`SearchText` 折叠、`LauncherMatch` 最佳对齐、`SearchSensitivity` 宽松度阈值）。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 仅在索引变化时折叠一次，绝不在每次按键时重复折叠。
struct SearchText: Sendable, Hashable {
    /// 采用 UTF-16，因为评分器在每次按键时都要按索引遍历它。
    let units: [UInt16]
    /// 分隔符未标记的词首位置，例如小写字母后的大写字母。
    let humps: [Int]

    var isEmpty: Bool { units.isEmpty }
    var string: String { String(decoding: units, as: UTF16.self) }

    /// `transliterated` 按输入方式读取其他文字：把 `微信` 读作 `wei xin`。
    init(_ raw: String, transliterated: Bool) {
        let latin = transliterated ? ScriptRomanization.latin(raw) : nil
        units = Array((latin ?? FuzzyMatch.normalized(raw)).utf16)
        humps = latin == nil ? Self.humps(in: raw) : []
    }

    /// 由已有单位和词首位置直接构造，供拼接等场景使用。
    init(units: [UInt16], humps: [Int] = []) {
        self.units = units
        self.humps = humps
    }

    /// 把两段文本拼成一个短语，使 `brew search` 能命中 `Brew` 下的 `Search`。
    func joined(with other: SearchText) -> SearchText {
        SearchText(
            units: units + [LauncherMatch.space] + other.units,
            humps: humps + other.humps.map { $0 + units.count + 1 })
    }

    private static let lowercase = UInt8(ascii: "a")...UInt8(ascii: "z")
    private static let uppercase = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let digit = UInt8(ascii: "0")...UInt8(ascii: "9")

    /// 仅处理 ASCII：其折叠保持所有索引不变，而非 ASCII 折叠可能使索引位移。
    private static func humps(in raw: String) -> [Int] {
        var humps: [Int] = []
        var (beforePrevious, previous): (UInt8, UInt8) = (0, 0)
        for (offset, byte) in raw.utf8.enumerated() {
            guard byte < 0x80 else { return [] }
            switch (beforePrevious, previous, byte) {
            case (_, lowercase, uppercase), (_, digit, lowercase), (_, digit, uppercase):
                humps.append(offset)
            // 该小写字母前的大写字母结束了一个缩写并开启一个新词。
            case (uppercase, uppercase, lowercase):
                humps.append(offset - 1)
            default:
                break
            }
            (beforePrevious, previous) = (previous, byte)
        }
        return humps
    }
}

/// 查询在一段文本上的最佳对齐结果，其中词首得分高于其他任意字母。
enum LauncherMatch {
    /// 一次匹配的两种结果：完全相等或带分数的部分对齐。
    enum Outcome: Sendable, Equatable {
        case exact
        /// `skipped` 统计没有可落地位置的查询分隔符数量。
        case scored(score: Int, skipped: Int)

        /// 用于排序的数值；完全命中为 `Int.max`。
        var value: Int {
            switch self {
            case .exact: Int.max
            case .scored(let score, _): score
            }
        }
    }

    /// 查询分隔符的 UTF-16 码位（空格）。
    static let space: UInt16 = 0x20

    /// 少于该字母数时，预检查的开销高于它本可跳过的对齐开销。
    private static let precheckThreshold = 2

    /// 在目标文本中寻找查询的最佳对齐；任一所欠字母无法匹配则返回 nil。
    static func match(_ query: SearchText, in target: SearchText) -> Outcome? {
        let q = query.units
        let t = target.units
        guard !q.isEmpty else { return nil }
        if q == t { return .exact }
        let letters = q.reduce(0) { isSeparator($1) ? $0 : $0 + 1 }
        guard letters <= t.count else { return nil }
        if letters > precheckThreshold, !isRoughSubsequence(q, of: t) { return nil }
        return align(q, t, humps: target.humps, letters: letters)
    }

    /// 判断某个 UTF-16 码位是否为查询分隔符。
    static func isSeparator(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09, 0x0A, 0x20, 0x28, 0x29, 0x2D, 0x2E, 0x2F, 0x5B, 0x5D: true
        default: false
        }
    }

    /// 查询分隔符可以向前跳过，因此这里只排除文本中确实缺失的字母。
    private static func isRoughSubsequence(_ q: [UInt16], of t: [UInt16]) -> Bool {
        var position = 0
        for unit in q {
            if isSeparator(unit) {
                if position < t.count, isSeparator(t[position]) { position += 1 }
                continue
            }
            guard let found = t[position...].firstIndex(of: unit) else { return false }
            position = found + 1
        }
        return true
    }

    /// 每个查询字符对应一行；通过滚动最大值使每行与文本长度呈线性关系。
    private static func align(_ q: [UInt16], _ t: [UInt16], humps: [Int], letters: Int) -> Outcome? {
        let width = t.count
        var previous = [Int](repeating: .min, count: width)
        var current = [Int](repeating: .min, count: width)
        // 上一保留行匹配到的第一列；下一行从它之后开始。
        var anchor = -1
        var rowStart = 0
        var rowEnd = 0
        var matched = 0
        var skipped = 0

        for unit in q {
            let unitIsSeparator = isSeparator(unit)
            let lower = anchor + 1
            // 已匹配的分隔符也计入待匹配字母，因此上界可能越过末尾。
            let upper = min(width, width - (letters - 1 - matched))
            var first = -1
            var gapBest = Int.min
            if lower < upper {
                for column in lower..<upper {
                    if anchor >= 0, column - 2 >= anchor { gapBest = max(gapBest, previous[column - 2]) }
                    let candidate = t[column]
                    let same = candidate == unit
                    let bothSeparators = !same && unitIsSeparator && isSeparator(candidate)
                    guard same || bothSeparators else {
                        current[column] = .min
                        continue
                    }
                    let points =
                        bothSeparators
                        ? 1 : (anchor < 0 && column == 0 ? 4 : wordPoints(t, column, humps: humps))
                    if anchor < 0 {
                        current[column] = points
                    } else {
                        var best = Int.min
                        let adjacent = previous[column - 1]
                        if adjacent != .min { best = adjacent + points }
                        if gapBest != .min { best = max(best, gapBest + points - 1) }
                        current[column] = best
                    }
                    if first < 0 { first = column }
                }
            }
            if first >= 0 {
                anchor = first
                matched += 1
                rowStart = lower
                rowEnd = upper
                swap(&previous, &current)
            } else if unitIsSeparator {
                skipped += 1
            } else {
                return nil
            }
        }
        guard anchor >= 0 else { return nil }
        let best = previous[rowStart..<rowEnd].max() ?? .min
        return best == .min ? nil : .scored(score: best, skipped: skipped)
    }

    private static func wordPoints(_ t: [UInt16], _ column: Int, humps: [Int]) -> Int {
        (isSeparator(t[column - 1]) && !isSeparator(t[column])) || humps.contains(column) ? 3 : 2
    }
}

/// 模糊命中要显示出来的宽松程度。
enum SearchSensitivity: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    static let `default`: Self = .medium

    var id: String { rawValue }

    /// 该宽松度档位的展示名称。
    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// `queryLength` 使用结果评分时所用的单位长度。
    func accepts(_ outcome: LauncherMatch.Outcome, queryLength: Int) -> Bool {
        guard case .scored(let score, let skipped) = outcome else { return true }
        let length = queryLength - skipped
        switch self {
        case .low: return true
        case .medium: return Double(score) >= 1.5 * Double(length - 2) + 4
        case .high: return score > 2 * length
        }
    }
}
