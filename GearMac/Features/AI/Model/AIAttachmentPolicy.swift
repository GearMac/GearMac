// 文件职责：AI 附件策略：判定粘贴文件的类型，决定其 MIME 类型，并把不作为原生附件发送的文本文件内联进提示词。
// 分层：Model；纯函数，无 I/O 与平台依赖，不得 import AppKit/SwiftUI。
import Foundation

/// 输入区（composer）对一个粘贴文件能做什么。纯逻辑，因此可由测试夹具固定验证，而不必依赖真实对话。
enum AIAttachmentPolicy {
    /// 判定结果：文件以哪种形态随消息发出；不能附加的情形由 `kind(forFileName:)` 返回 nil 表示。
    enum Kind: Equatable, Sendable {
        case image
        case pdf
        case text
    }

    static let pdfMIMEType = "application/pdf"

    /// `newlines` 并不包含于 `controlCharacters`：U+2028 会让伪造的文件头绕过过滤。
    private static let unsafeInName = CharacterSet.controlCharacters.union(.newlines)

    /// 用扩展名而非 `UTType`：类型由已安装的应用声明，不同 Mac 上的一致性（conformance）并不相同。
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml", "toml", "ini",
        "xml", "html", "css", "js", "jsx", "ts", "tsx", "swift", "m", "mm", "h", "c", "cc",
        "cpp", "hpp", "rs", "go", "rb", "py", "php", "java", "kt", "sh", "zsh", "bash", "sql",
        "log", "conf", "plist", "patch", "diff"
    ]

    /// GearMac 不会附加的文件返回 nil，输入区据此按文件名拒绝该文件。
    static func kind(forFileName name: String) -> Kind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if textExtensions.contains(ext) { return .text }
        return nil
    }

    /// 只有 PDF 这一种形态会交给传输层；被内联的文本文件仅用其扩展名作为代码块围栏提示。
    static func mimeType(forFileName name: String) -> String {
        (name as NSString).pathExtension.lowercased() == "pdf" ? pdfMIMEType : "text/plain"
    }

    /// 生成的围栏足够长，使内含围栏的 Markdown 文件无法提前闭合而逃逸。
    static func prompt(text: String, documents: [AIDocument]) -> String {
        let inlined = documents.compactMap(block).joined(separator: "\n\n")
        guard !inlined.isEmpty else { return text }
        return text.isEmpty ? inlined : inlined + "\n\n" + text
    }

    /// 把单个文档渲染为带围栏的文本块；PDF 或非 UTF-8 内容返回 nil。
    private static func block(for document: AIDocument) -> String? {
        guard document.mimeType != pdfMIMEType,
            let contents = String(data: document.data, encoding: .utf8)
        else { return nil }
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: contents) + 1))
        let hint = (document.name as NSString).pathExtension.lowercased()
        return """
            Attached file: \(sanitized(name: document.name))
            \(fence)\(hint)
            \(contents)
            \(fence)
            """
    }

    /// 名为 `a\nAttached file: passwd` 的文件不得伪造出第二个文件头。
    static func sanitized(name: String) -> String {
        let cleaned = name.unicodeScalars
            .filter { !Self.unsafeInName.contains($0) }
        return String(String.UnicodeScalarView(cleaned)).prefix(64).description
    }

    /// 文本中最长连续反引号串的长度，用于决定围栏所需的反引号数量。
    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }
}
