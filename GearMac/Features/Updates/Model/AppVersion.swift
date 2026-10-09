// 文件职责：解析并比较发布版本号，支持 `MAJOR.MINOR.PATCH` 与可选的 `-beta.N` 后缀。
// 分层：Model（值类型，Sendable，CustomStringConvertible/Codable）；不依赖 AppKit/SwiftUI，仅导入 Foundation。
import Foundation

/// 一个已发布版本：`MAJOR.MINOR.PATCH`，可选 `-beta.N`，按 semver 优先级排序。
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// 稳定版为 nil；稳定版的优先级高于同一三元组的任何预发布版。
    let beta: Int?

    /// 解析版本字符串；格式非法时返回 nil。
    init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        // 发布 tag 带前导 `v`，而 `CFBundleShortVersionString` 从不带。
        if body.first == "v" { body = body.dropFirst() }

        let halves = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = halves[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
            let major = Self.number(numbers[0]),
            let minor = Self.number(numbers[1]),
            let patch = Self.number(numbers[2])
        else { return nil }

        if halves.count == 2 {
            // `beta` 是唯一会真正发布的预发布通道，因此其他后缀一律无法解析。
            let suffix = halves[1].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 2, suffix[0] == "beta", let count = Self.number(suffix[1])
            else { return nil }
            beta = count
        } else {
            beta = nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var isPrerelease: Bool { beta != nil }

    var description: String {
        let triple = "\(major).\(minor).\(patch)"
        return beta.map { "\(triple)-beta.\($0)" } ?? triple
    }

    /// 按 semver 优先级比较：先比三段数字，稳定版高于预发布版。
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.beta, rhs.beta) {
        case (nil, nil): return false
        // 预发布版最终会走向正式版，因此在排序上低于正式版，绝不会高于它。
        case (.some, nil): return true
        case (nil, .some): return false
        case (.some(let left), .some(let right)): return left < right
        }
    }

    /// 拒绝带符号或补零的字段，避免 `Int` 静默地重新解释它们。
    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

/// 以版本字符串作为单一 JSON 值进行编解码。
extension AppVersion: Codable {
    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = AppVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Not a version: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
