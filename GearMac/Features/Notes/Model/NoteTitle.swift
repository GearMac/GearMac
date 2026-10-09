// 文件职责：从笔记源文本推导标题：判断未命名、提取首行可见文本并限制展示宽度。
// 分层：Model；纯函数、不依赖 AppKit/SwiftUI。
import Foundation

/// 笔记标题即其文件名；用户尚未命名的笔记借用首行来展示。
enum NoteTitle {
    static let untitled = "Untitled"

    /// 足够宽，即使每个字符都是四字节也能覆盖扫描到的前缀。
    static let headByteCount = 4096

    /// 解析首行时扫描的最大字符数。
    private static let scanLimit = 1024
    /// 首行展示的最大字符数。
    private static let displayLimit = 120

    /// 仅对 `create` 自动生成的名称（`Untitled`、`Untitled 2` …）为真，用户手输的不算。
    static func isUnnamed(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let suffix = title.dropFirst(untitled.count)
        guard !suffix.isEmpty else { return true }
        let digits = suffix.dropFirst()
        return suffix.hasPrefix(" ") && !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// 第一行含可见文本的内容，去除其 Markdown 标记并限为一行。
    static func firstLine(of source: String) -> String? {
        let head = String(source.prefix(scanLimit))
        let text = head as NSString
        let markdown = NoteMarkdownParser.parse(head)
        for line in markdown.lines {
            let title = visibleText(of: line, in: markdown, text: text)
            guard !title.isEmpty else { continue }
            return String(title.prefix(displayLimit))
        }
        return nil
    }

    /// 行在渲染后读出的形式（无论开关状态）：语法标记永远不会成为标题。
    private static func visibleText(
        of line: NoteMarkdown.Line, in markdown: NoteMarkdown, text: NSString
    ) -> String {
        switch line.kind {
        case .blank, .rule, .fenceOpen, .fenceClose: return ""
        default: break
        }
        var visible = ""
        var cursor = line.contentRange.location
        let markers = markdown.inlines(of: line).flatMap(\.markerRanges)
        for marker in markers.sorted(by: { $0.location < $1.location }) {
            visible += text.substring(with: NSRange(cursor..<marker.location))
            cursor = NSMaxRange(marker)
        }
        visible += text.substring(with: NSRange(cursor..<NSMaxRange(line.contentRange)))
        return visible.trimmingCharacters(in: .whitespaces)
    }
}
