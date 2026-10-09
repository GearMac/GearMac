// 文件职责：解析输入框开头的 `@slug`，将本轮对话限定到某个 MCP 服务器。
// 分层：Model；不得 import AppKit/SwiftUI，纯函数无副作用。
import Foundation

/// 开头的 `@slug` 把本轮对话限定到某个服务器；未知的 handle 只当作普通文本，而非地址。
enum MCPComposerAddress {
    /// 解析文本开头的 `@slug`：返回（slug, 剩余文本）；未命中时 slug 为 nil 且返回原文本。
    static func parse(_ text: String, slugs: Set<String>) -> (slug: String?, rest: String) {
        let trimmed = text.drop { $0 == " " }
        guard trimmed.first == "@" else { return (nil, text) }
        let handle = trimmed.dropFirst().prefix { !$0.isWhitespace }
        let slug = handle.lowercased()
        guard slugs.contains(slug) else { return (nil, text) }
        let rest = trimmed.dropFirst(handle.count + 1)
        return (slug, String(rest.drop { $0 == " " }))
    }
}
