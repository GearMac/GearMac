// 文件职责：把 Raycast 导出的 snippet 数据（`[[String: Any]]`）解析为 GearMac 的 `Snippet` 模型。
// 分层：Model；纯解析，不读写文件系统、不触碰 UI。
import Foundation

/// Raycast snippet 导入解析器：从 JSON 对象数组中筛选合法条目并转换为 `Snippet`。
enum RaycastSnippetImport {
    /// 解析顶层 JSON 值；非数组，或条目缺少有效 `title`/`text` 时跳过该条目。
    static func parse(_ value: Any?) -> [Snippet] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["title"] as? String,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let text = entry["text"] as? String
            else { return nil }

            let rawKeyword = entry["keyword"] as? String
            let keyword = rawKeyword?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Snippet(
                name: name,
                text: text,
                keyword: keyword?.isEmpty == false ? keyword : nil)
        }
    }
}
