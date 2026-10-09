// 文件职责：解析 AI 回复中的网页链接，按引用顺序汇总为可打开的来源引用（ChatReference）。
// 分层：Model；纯函数与值类型，不依赖 AppKit/SwiftUI，不产生任何副作用。
import Foundation

/// 回复指向的一个页面，作为读者可打开的来源显示在回复下方。
struct ChatReference: Equatable, Hashable, Sendable {
    let title: String
    let url: URL

    /// 去掉 `www.` 前缀的主机名；无主机时退回完整 URL 字符串。
    var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// 一条回复中的全部网页链接，按引用出现的顺序排列；代码示例里的 URL 不算来源。
enum ChatReferences {
    /// 最多保留的来源条数。
    static let limit = 8

    /// 从回复文本中按出现顺序提取来源引用，去重后截断到 `limit` 条。
    static func extract(from text: String) -> [ChatReference] {
        let prose = withoutCode(text)
        var found: [(offset: Int, reference: ChatReference)] = []
        var linked = Set<String>()
        for match in prose.matches(of: #/\[([^\]\n]+)\]\((https?://[^)\s]+)\)/#) {
            guard let url = URL(string: String(match.output.2)) else { continue }
            let label = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let title = label.hasPrefix("http") ? readable(url) : label
            linked.insert(key(url))
            found.append((offset(of: match.range, in: prose), ChatReference(title: title, url: url)))
        }
        // Markdown 链接之外的裸 URL：链接自身的地址已在上方计入。
        let unlinked = prose.replacing(#/\[[^\]\n]+\]\(https?://[^)\s]+\)/#) { match in
            String(repeating: " ", count: match.output.count)
        }
        for match in unlinked.matches(of: #/https?://[^\s<>"'`)\]]+/#) {
            let trimmed = String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?*_"))
            guard let url = URL(string: trimmed), url.host() != nil, !linked.contains(key(url)) else {
                continue
            }
            let reference = ChatReference(title: readable(url), url: url)
            found.append((offset(of: match.range, in: unlinked), reference))
        }
        var seen = Set<String>()
        return found.sorted { $0.offset < $1.offset }
            .map(\.reference)
            .filter { seen.insert(key($0.url)).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// 围栏代码与行内代码是示例，不是引用来源；先移除它们再扫描链接。
    private static func withoutCode(_ text: String) -> String {
        text.replacing(#/```[\s\S]*?(```|$)/#) { _ in "" }
            .replacing(#/`[^`\n]*`/#) { _ in "" }
    }

    /// 每个来源的编号，以 `key` 生成的 URL 键存储，便于引用找到对应标记。
    static func numbers(for references: [ChatReference]) -> [String: Int] {
        Dictionary(
            references.enumerated().map { (key($0.element.url), $0.offset + 1) },
            uniquingKeysWith: { first, _ in first })
    }

    /// 同一页面被引用两次（带或不带结尾斜杠）算作同一个来源。
    static func key(_ url: URL) -> String {
        var string = url.absoluteString.lowercased()
        while string.hasSuffix("/") { string.removeLast() }
        return string
    }

    /// 生成用于展示的简短标题：主机名（去掉 `www.`）加上去掉首尾斜杠的路径。
    private static func readable(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return path.isEmpty ? bare : "\(bare)/\(path)"
    }

    /// 计算 range 在 text 中的字符偏移量，用于按出现顺序排序。
    private static func offset(of range: Range<String.Index>, in text: String) -> Int {
        text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
