// 文件职责：snippet Markdown 文件（YAML frontmatter + 正文）的解析与序列化，以及文件名 slug 生成。
// 分层：Model；纯字符串处理，不进行文件 IO。
import Foundation

/// snippet 文本格式的编解码器：frontmatter 元数据加正文。
struct SnippetMarkdownSerializer {
    /// frontmatter 解析失败的错误，携带文件位置、行号与原因。
    enum ParseError: Error, LocalizedError, Equatable {
        case invalidFrontmatter(fileURL: URL, line: Int, reason: String)

        /// 面向用户的错误描述，格式为「路径:行号: 原因」。
        var errorDescription: String? {
            switch self {
            case .invalidFrontmatter(let fileURL, let line, let reason):
                return "\(fileURL.path):\(line): \(reason)"
            }
        }
    }

    /// 解析文件内容；无 frontmatter 时把整个内容当正文，名称回退到文件名。
    static func parse(content: String, fileURL: URL) throws -> Snippet {
        let lines = sourceLines(in: content)
        guard lines.first?.text == "---" else {
            return Snippet(name: defaultName(for: fileURL), text: content)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0.text == "---" }) else {
            throw parseError(fileURL, line: 1, "Missing closing frontmatter delimiter")
        }

        var name: String?
        var keyword: String?
        var isEnabled = true
        var showsConfirmation = false
        var seenKeys = Set<String>()

        for lineIndex in 1..<closingIndex {
            let line = lines[lineIndex]
            let lineNumber = lineIndex + 1
            guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let separator = line.text.firstIndex(of: ":") else {
                throw parseError(fileURL, line: lineNumber, "Expected a key and value separated by ':'")
            }

            let rawKey = line.text[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line.text[line.text.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard let key = canonicalKey(for: rawKey) else {
                throw parseError(fileURL, line: lineNumber, "Unsupported frontmatter key '\(rawKey)'")
            }
            guard seenKeys.insert(key).inserted else {
                throw parseError(fileURL, line: lineNumber, "Duplicate frontmatter key '\(key)'")
            }

            switch key {
            case "name":
                let decoded = try decodeScalar(rawValue, fileURL: fileURL, line: lineNumber)
                // 空名称视为未指定，仍可回退到文件名作为展示名。
                name = decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : decoded
            case "keyword":
                keyword = try decodeScalar(rawValue, fileURL: fileURL, line: lineNumber)
            case "enabled":
                isEnabled = try decodeBoolean(rawValue, fileURL: fileURL, line: lineNumber)
            case "show_confirmation":
                showsConfirmation = try decodeBoolean(rawValue, fileURL: fileURL, line: lineNumber)
            default:
                preconditionFailure("Canonical keys are exhaustively handled")
            }
        }

        let bodyStart = lines[closingIndex].endIncludingTerminator
        return Snippet(
            name: name ?? defaultName(for: fileURL),
            text: String(content[bodyStart...]),
            keyword: keyword,
            isEnabled: isEnabled,
            showsConfirmation: showsConfirmation
        )
    }

    /// 序列化为 frontmatter 加正文的 Markdown 文本。
    static func serialize(_ snippet: Snippet) -> String {
        var lines = [
            "---",
            "name: \(encodeScalar(snippet.name))"
        ]
        if let keyword = snippet.keyword {
            lines.append("keyword: \(encodeScalar(keyword))")
        }
        lines.append("enabled: \(snippet.isEnabled)")
        lines.append("show_confirmation: \(snippet.showsConfirmation)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + snippet.text
    }

    /// 由名称生成文件名 slug：非字母数字转为连字符，结果为空时回退为 "snippet"。
    static func slug(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var slug = name.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if slug.isEmpty { slug = "snippet" }
        return slug
    }

    /// 内容中的一行：行文本与包含换行符的结束位置。
    private struct SourceLine {
        let text: Substring
        let endIncludingTerminator: String.Index
    }

    /// 按 CR/LF/CRLF 切分内容，并保留每行的结束位置。
    private static func sourceLines(in content: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        var lineStart = content.startIndex
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]
            guard character == "\n" || character == "\r" || character == "\r\n" else {
                index = content.index(after: index)
                continue
            }

            var terminatorEnd = content.index(after: index)
            if character == "\r", terminatorEnd < content.endIndex, content[terminatorEnd] == "\n" {
                terminatorEnd = content.index(after: terminatorEnd)
            }
            lines.append(SourceLine(text: content[lineStart..<index], endIncludingTerminator: terminatorEnd))
            lineStart = terminatorEnd
            index = terminatorEnd
        }

        if lineStart < content.endIndex || lines.isEmpty {
            lines.append(SourceLine(text: content[lineStart...], endIncludingTerminator: content.endIndex))
        }
        return lines
    }

    /// 把原始 key 归一化为受支持的规范键名，无法识别则返回 nil。
    private static func canonicalKey(for rawKey: String) -> String? {
        let key = rawKey.lowercased()
        switch key {
        case "name", "keyword", "enabled", "show_confirmation":
            return key
        default:
            return nil
        }
    }

    /// 解析双引号字符串标量，处理转义并拒绝后引号之后的多余内容。
    private static func decodeScalar(_ value: String, fileURL: URL, line: Int) throws -> String {
        let scalars = value.unicodeScalars
        guard scalars.first == "\"" else {
            throw parseError(fileURL, line: line, "String values must use double quotes")
        }

        var decoded = ""
        var index = scalars.index(after: scalars.startIndex)
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\"" {
                let trailing = scalars[scalars.index(after: index)...]
                guard trailing.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                    throw parseError(fileURL, line: line, "Unexpected text after quoted value")
                }
                return decoded
            }
            if scalar == "\\" {
                let escapeIndex = scalars.index(after: index)
                guard escapeIndex < scalars.endIndex else {
                    throw parseError(fileURL, line: line, "Unterminated escape sequence")
                }
                switch scalars[escapeIndex] {
                case "\\": decoded.append("\\")
                case "\"": decoded.append("\"")
                case "n": decoded.append("\n")
                case "r": decoded.append("\r")
                case "t": decoded.append("\t")
                default:
                    throw parseError(fileURL, line: line, "Unsupported escape sequence")
                }
                index = scalars.index(after: escapeIndex)
                continue
            }
            guard scalar != "\n" && scalar != "\r" && scalar != "\t" else {
                throw parseError(fileURL, line: line, "Control characters must be escaped")
            }
            decoded.unicodeScalars.append(scalar)
            index = scalars.index(after: index)
        }
        throw parseError(fileURL, line: line, "Unterminated quoted value")
    }

    /// 解析布尔标量，仅接受 `true` 或 `false`。
    private static func decodeBoolean(_ value: String, fileURL: URL, line: Int) throws -> Bool {
        switch value {
        case "true": return true
        case "false": return false
        default:
            throw parseError(fileURL, line: line, "Boolean values must be exactly 'true' or 'false'")
        }
    }

    /// 把字符串编码为带转义的双引号标量。
    private static func encodeScalar(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": encoded += "\\\\"
            case "\"": encoded += "\\\""
            case "\n": encoded += "\\n"
            case "\r": encoded += "\\r"
            case "\t": encoded += "\\t"
            default: encoded.unicodeScalars.append(scalar)
            }
        }
        encoded.append("\"")
        return encoded
    }

    /// 无 frontmatter 名称时的回退展示名：去扩展名、连字符转空格、首字母大写。
    private static func defaultName(for fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized(with: Locale(identifier: "en_US_POSIX"))
    }

    /// 构造 frontmatter 解析错误。
    private static func parseError(_ fileURL: URL, line: Int, _ reason: String) -> ParseError {
        .invalidFrontmatter(fileURL: fileURL, line: line, reason: reason)
    }
}
