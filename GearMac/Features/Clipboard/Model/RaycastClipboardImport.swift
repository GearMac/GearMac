// 文件职责：解析 Raycast 导出的剪贴板 JSON，并转换为本应用的 ClipboardItem 列表。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，不写盘，仅通过注入的闭包访问时间与文件系统。
import Foundation

/// Raycast 剪贴板导出数据的解析入口。
enum RaycastClipboardImport {
    /// 解析顶层 `clipboardEntries`；返回解析出的条目与引用文件已缺失的数量。
    static func parse(
        _ value: Any?, now: () -> Date, fileExists: (String) -> Bool
    ) -> (items: [ClipboardItem], missing: Int) {
        guard let entries = (value as? [String: Any])?["clipboardEntries"] as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for entry in entries {
            let createdAt = parseDate(entry["createdAt"] as? String, using: dateParser) ?? now()
            let pinnedAt = isPinned(entry["pinned"]) ? createdAt : nil
            let reps = (entry["items"] as? [[String: Any]] ?? [])
                .flatMap { ($0["representations"] as? [[String: Any]]) ?? [] }

            if let text = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("text/plain") == true
            })?["content"] as? String, !text.isEmpty {
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: nil, pinnedAt: pinnedAt))
                continue
            }

            if let path = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("image/") == true
                    && ($0["contentType"] as? String) == "url"
            })?["content"] as? String {
                guard fileExists(path) else {
                    missing += 1
                    continue
                }
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .image, text: nil, imagePath: path, createdAt: createdAt,
                        sourceBundleID: nil, pinnedAt: pinnedAt))
            }
        }
        return (items, missing)
    }

    /// 按带毫秒的 ISO8601 解析日期，失败时退回标准 ISO8601 形式。
    private static func parseDate(_ string: String?, using parser: ISO8601DateFormatter) -> Date? {
        guard let string else { return nil }
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// 仅当该值确实是布尔类型（而非数字等其它类型）时返回 true。
    private static func isPinned(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return false }
        return number.boolValue
    }
}
