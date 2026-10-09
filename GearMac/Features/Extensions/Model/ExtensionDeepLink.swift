// 文件职责：解析 `raycast://extensions/...` 与 `gearmac://...` 形式的深层链接，提取扩展名、命令名、参数与启动方式。
// 分层：Model；纯解析逻辑，不 import AppKit/SwiftUI。
import Foundation

/// 一个 `extensions` 深层链接：`raycast://extensions/<owner>/<extension>/<command>?arguments={…}`。
/// `gearmac://` 是其镜像写法，以使我方链接不依赖 Raycast 赢得该 scheme。
struct ExtensionDeepLink: Sendable, Equatable {
    let ownerOrAuthor: String?
    let extensionName: String
    let commandName: String
    let arguments: [String: String]
    let fallbackText: String?
    let launchType: ExtensionLaunchType

    /// `owner/ext` 排在前面，使带作用域的 manifest 优先于仅同名 slug 的冲突。
    var extensionCandidates: [String] {
        guard let ownerOrAuthor, !ownerOrAuthor.isEmpty else { return [extensionName] }
        return ["\(ownerOrAuthor)/\(extensionName)", extensionName]
    }

    /// 判断给定的 manifest 名称是否指向本链接所描述的扩展（忽略大小写与 owner 前缀）。
    func matches(manifestName: String) -> Bool {
        let lowered = manifestName.lowercased()
        if extensionCandidates.contains(where: { $0.lowercased() == lowered }) { return true }
        return manifestName.split(separator: "/").last?.lowercased() == extensionName.lowercased()
    }

    /// 判断该 URL 的 scheme 是否属于本应用处理的几种深层链接。
    static func claims(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["raycast", "gearmac", "com.raycast", "raycastinternal"].contains(scheme)
    }

    /// host 与首个 path 段合并处理，以统一 `raycast://extensions/…` 与 `com.raycast:/extensions/…` 两种形式。
    static func parse(url: URL) -> ExtensionDeepLink? {
        guard claims(url) else { return nil }
        var segments: [String] = []
        if let host = url.host, !host.isEmpty { segments.append(host) }
        segments += url.pathComponents.filter { $0 != "/" }
        segments = segments.map { $0.removingPercentEncoding ?? $0 }
        guard segments.count >= 3, segments[0].lowercased() == "extensions" else { return nil }
        let body = Array(segments.dropFirst())
        guard body.count >= 2 else { return nil }
        let ownerOrAuthor: String?
        let extensionName: String
        let commandName: String
        switch body.count {
        case 2:
            ownerOrAuthor = nil
            extensionName = body[0]
            commandName = body[1]
        case 3:
            ownerOrAuthor = body[0]
            extensionName = body[1]
            commandName = body[2]
        default:
            ownerOrAuthor = body.dropLast(2).joined(separator: "/")
            extensionName = body[body.count - 2]
            commandName = body[body.count - 1]
        }
        guard !extensionName.isEmpty, !commandName.isEmpty else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var arguments: [String: String] = [:]
        var fallbackText: String?
        var launchType = ExtensionLaunchType.userInitiated
        for item in items {
            switch item.name.lowercased() {
            case "arguments":
                if let raw = item.value { arguments = parseArguments(raw) }
            case "fallbacktext":
                fallbackText = item.value
            case "launchtype", "launch_type":
                launchType = item.value?.lowercased() == "background" ? .background : .userInitiated
            default:
                break
            }
        }
        return ExtensionDeepLink(
            ownerOrAuthor: ownerOrAuthor, extensionName: extensionName, commandName: commandName,
            arguments: arguments, fallbackText: fallbackText, launchType: launchType)
    }

    /// Raycast 发送的是一个 URL 编码的 JSON 对象；其他情况说明无参数，而不是失败。
    nonisolated static func parseArguments(_ raw: String) -> [String: String] {
        guard let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            let dict = json as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in dict {
            if let string = value as? String {
                out[key] = string
            } else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    out[key] = number.boolValue ? "true" : "false"
                } else {
                    let double = number.doubleValue
                    out[key] =
                        double == double.rounded() && double.magnitude < 1e15
                        ? String(number.int64Value) : String(double)
                }
            } else if value is NSNull {
                out[key] = ""
            }
        }
        return out
    }
}
