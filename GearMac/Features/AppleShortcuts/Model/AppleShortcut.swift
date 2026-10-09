// 文件职责：定义快捷指令模型，负责从 `shortcuts list` 输出解析列表、entryID 与 UUID 互转，以及识别被引用但已失效的快捷指令。
// 分层：Model；保持纯净，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// Shortcuts app 拥有的快捷指令；GearMac 只保留定位与运行它所需的最小信息。
struct AppleShortcut: Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "apple-shortcut:"
    static let sfSymbol = "square.2.layers.3d"

    let id: UUID
    let name: String

    /// 该快捷指令在条目体系中的唯一标识 entryID。
    var entryID: String { Self.entryID(for: id) }

    /// 由 UUID 生成对应的 entryID（前缀 + 小写 UUID 字符串）。
    static func entryID(for id: UUID) -> String { entryIDPrefix + id.uuidString.lowercased() }

    /// 从 entryID 反解出 UUID；前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// 解析 `shortcuts list --show-identifiers` 的输出：每行一个 `Name (UUID)`，按名称排序并去重。
    static func parseList(_ output: String) -> [AppleShortcut] {
        var seen: Set<UUID> = []
        return output.split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 仍被已保存的偏好或绑定引用、但快捷指令库中已不存在的快捷指令 ID。
    static func staleIDs(
        referencedBy keys: some Sequence<String>, bound: some Sequence<UUID>, live: [AppleShortcut]
    ) -> Set<UUID> {
        // 空库与「工具读取结果为空」无法区分，因此空库不清理任何失效引用。
        guard !live.isEmpty else { return [] }
        let referenced = Set(keys.lazy.compactMap(id(fromEntryID:))).union(bound)
        return referenced.subtracting(live.map(\.id))
    }

    /// 以行尾的标识符为锚点解析，因此名称本身可以包含括号。
    private static func parseLine(_ line: Substring) -> AppleShortcut? {
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
        let identifier = line[line.index(after: open)..<line.index(before: line.endIndex)]
        let name = line[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = UUID(uuidString: String(identifier)) else { return nil }
        return AppleShortcut(id: id, name: name)
    }
}
