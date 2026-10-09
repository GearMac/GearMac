// 文件职责：将 Raycast 的 `quicklinks` 数据映射为 GearMac 的 Quicklink，处理参数占位符与应用路径到 bundle id 的转换。
// 分层：Model；纯解析逻辑，文件读取与 bundle 查询通过注入的回调完成。
import Foundation

/// 将 Raycast 的 `quicklinks` 数据块映射为 `Quicklink`。详见 docs/features/raycast-import.md。
enum RaycastQuicklinkImport {
    /// `openWith` 可能是应用路径或平台 id，两者都通过注入的查找回调解析。
    static func parse(
        _ value: Any?,
        bundleIDForAppPath: (String) -> String? = bundleID(at:)
    ) -> [Quicklink] {
        let root: [String: Any]
        let entries: [[String: Any]]
        if let dict = value as? [String: Any] {
            root = dict
            entries = dict["quicklinks"] as? [[String: Any]] ?? []
        } else if let array = value as? [[String: Any]] {
            root = [:]
            entries = array
        } else {
            return []
        }

        var platforms: [String: String] = [:]
        for row in root["openWithPlatforms"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? String,
                let path = row["macos"] as? String,
                !id.isEmpty, !path.isEmpty
            else { continue }
            platforms[id] = path
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()

        return entries.compactMap { entry in
            guard let name = trimmed(entry["name"]), let rawLink = trimmed(entry["link"]) else {
                return nil
            }
            let link = rewrittenLink(rawLink)
            guard !link.isEmpty else { return nil }
            return Quicklink(
                name: name,
                link: link,
                openWithBundleID: openWithBundleID(
                    in: entry, platforms: platforms, bundleIDForAppPath: bundleIDForAppPath),
                createdAt: date(entry["createdAt"] as? String, fractional: fractional, whole: whole))
        }
    }

    /// `{Query}` 是 Raycast 的参数占位符；GearMac 编辑器只写入 `{argument}`。
    static func rewrittenLink(_ link: String) -> String {
        var result = ""
        var position = link.startIndex
        while position < link.endIndex,
            let opening = link[position...].firstIndex(of: "{"),
            let closing = link[link.index(after: opening)...].firstIndex(of: "}")
        {
            result += link[position..<opening]
            let body = String(link[link.index(after: opening)..<closing])
            result += rewrittenToken(body)
            position = link.index(after: closing)
        }
        result += link[position...]
        return result
    }

    /// 将单个占位符内部的 query 命令重写为 `{argument...}`。
    private static func rewrittenToken(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandEnd =
            trimmed.firstIndex(where: { $0.isWhitespace || $0 == "=" || $0 == "|" })
            ?? trimmed.endIndex
        guard trimmed[..<commandEnd].lowercased() == "query" else { return "{\(body)}" }
        return "{argument\(trimmed[commandEnd...])}"
    }

    /// 从条目中解析打开方式所属的 bundle id。
    private static func openWithBundleID(
        in entry: [String: Any],
        platforms: [String: String],
        bundleIDForAppPath: (String) -> String?
    ) -> String? {
        guard let raw = trimmed(entry["openWith"]) ?? trimmed(entry["applicationId"]) else {
            return nil
        }
        let path = raw.hasPrefix("/") ? raw : platforms[raw]
        return path.flatMap(bundleIDForAppPath)
    }

    /// 读取指定路径应用的 bundle id。
    private static func bundleID(at path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }

    /// 依次尝试带/不带小数秒的 ISO8601 格式解析日期，失败时返回当前时间。
    private static func date(
        _ string: String?, fractional: ISO8601DateFormatter, whole: ISO8601DateFormatter
    ) -> Date {
        guard let string else { return Date() }
        return fractional.date(from: string) ?? whole.date(from: string) ?? Date()
    }

    /// 去除首尾空白；非字符串或结果为空时返回 nil。
    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
