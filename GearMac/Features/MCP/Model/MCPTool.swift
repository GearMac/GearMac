// 文件职责：描述服务器对外公布的工具，并把工具名与调用结果规范化成模型可读的形式。
// 分层：Model；不得 import AppKit/SwiftUI，仅做数据结构与名称/输出转换。
import Foundation

/// 服务器对外公布的一个工具，并保留它来自哪个服务器。
struct MCPTool: Equatable, Sendable {
    let serverID: UUID
    let serverSlug: String
    let serverTitle: String
    let name: String
    let description: String
    let inputSchema: JSONValue

    /// 模型看到的名字。线上名必须同时满足两家提供方的字符规则。
    var wireName: String { MCPToolName.compose(slug: serverSlug, tool: name) }

    /// 转换为交付给模型的 AITool 表示。
    var aiTool: AITool {
        AITool(
            name: wireName, description: description, parameters: inputSchema,
            origin: serverTitle, title: name)
    }

    /// 服务器列出的全部工具，丢弃畸形到无法调用的条目。
    static func list(
        _ result: JSONValue, serverID: UUID, serverSlug: String, serverTitle: String
    ) -> [MCPTool] {
        (result.objectValue?["tools"]?.arrayValue ?? []).compactMap { entry in
            guard let tool = entry.objectValue, let name = tool["name"]?.stringValue,
                !name.isEmpty
            else { return nil }
            return MCPTool(
                serverID: serverID, serverSlug: serverSlug, serverTitle: serverTitle, name: name,
                description: tool["description"]?.stringValue ?? "",
                inputSchema: tool["inputSchema"] ?? .object(["type": .string("object")]))
        }
    }
}

/// 唯一把服务器 slug 与工具自身名称合并为提供方安全标识符的地方。
enum MCPToolName {
    /// slug 与工具名之间的分隔符。
    static let separator = "__"
    /// OpenAI 的上限，也是两者中更严格的一个。
    static let maxLength = 64

    /// 组合出线上名；超长时从工具名一侧截断，保留用于路由的 slug。
    static func compose(slug: String, tool: String) -> String {
        let tail = sanitize(tool)
        let room = maxLength - separator.count - sanitize(slug).count
        // slug 是路由调用的依据，因此让位的是工具自身名称那一半。
        return sanitize(slug) + separator + String(tail.suffix(max(room, 1)))
    }

    /// 还原出用于路由的 slug；不含分隔符的名字从不属于本应用。
    static func parse(_ wireName: String) -> (slug: String, tool: String)? {
        guard let range = wireName.range(of: separator) else { return nil }
        let slug = String(wireName[..<range.lowerBound])
        guard !slug.isEmpty else { return nil }
        return (slug, String(wireName[range.upperBound...]))
    }

    /// 把非 ASCII 字母/数字/连字符的字符替换为下划线。
    private static func sanitize(_ value: String) -> String {
        let cleaned = value.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
                ? character : "_"
        }
        return String(cleaned)
    }
}

/// `tools/call` 的返回，展平为模型可读的文本。
enum MCPToolOutput {
    /// 展平工具结果：拼接文本块，或退回结构化内容；同时给出是否为错误。
    static func flatten(_ result: JSONValue) -> (content: String, isError: Bool) {
        let object = result.objectValue ?? [:]
        let isError = object["isError"]?.boolValue ?? false
        let blocks = (object["content"]?.arrayValue ?? []).compactMap(describe)
        guard blocks.isEmpty else {
            return (blocks.joined(separator: "\n"), isError)
        }
        // 服务器可能只返回结构化内容；模型将其按 JSON 读取。
        guard let structured = object["structuredContent"],
            let data = try? JSONSerialization.data(withJSONObject: structured.jsonObject),
            let text = String(bytes: data, encoding: .utf8)
        else {
            return ("The tool returned no content.", isError)
        }
        return (text, isError)
    }

    /// 只保留文本模型可处理的内容；图片或二进制只标注名称而不内联。
    private static func describe(_ block: JSONValue) -> String? {
        guard let block = block.objectValue else { return nil }
        switch block["type"]?.stringValue {
        case "text":
            return block["text"]?.stringValue
        case "resource":
            let resource = block["resource"]?.objectValue ?? [:]
            return resource["text"]?.stringValue
                ?? resource["uri"]?.stringValue.map { "[resource \($0)]" }
        case "resource_link":
            return block["uri"]?.stringValue.map { "[resource \($0)]" }
        case "image", "audio":
            return "[\(block["type"]?.stringValue ?? "binary") content omitted]"
        default:
            return nil
        }
    }
}
