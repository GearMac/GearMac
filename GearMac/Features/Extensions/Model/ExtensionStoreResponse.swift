// 文件职责：封装 Raycast 商店接口的 URL 构造、响应解码与商店/下载错误类型。
// 分层：Model；纯 URL 与 JSON 处理，不 import AppKit/SwiftUI。
import Foundation

/// 请求的是他人的端点，因此安装不需要的字段均为可选。
enum ExtensionStoreResponse {
    /// 商店官网搜索所用的端点；因非官方，可能未经预告地变更。
    static func searchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            // 大小写敏感：其他写法只会返回未声明任何平台的扩展。
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    /// 按 manifest 所带的 handle 与名称查询单个扩展。
    static func lookupURL(handle: String, name: String) -> URL? {
        guard !handle.isEmpty, !name.isEmpty else { return nil }
        return URL(string: "https://www.raycast.com/api/v1/extensions")?
            .appending(path: handle)
            .appending(path: name)
    }

    /// 搜索接口的顶层响应封装。
    private struct StorePayload: Decodable {
        let data: [StoreEntry]
    }

    /// 商店返回的单个扩展条目。
    private struct StoreEntry: Decodable {
        let id: String
        let name: String
        let title: String?
        let description: String?
        let author: Author?
        let icons: Icons?
        let commands: [Command]?
        let downloadCount: Int?
        let downloadURL: String?
        let commitSHA: String?
        let status: String?

        /// 扩展作者信息。
        struct Author: Decodable {
            let name: String?
            let handle: String?
        }
        /// 扩展的浅色/深色图标地址。
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        /// 扩展包含的一个命令（只需其名称以计数）。
        struct Command: Decodable {
            let name: String?
        }

        /// JSON 字段与 Swift 名称的映射（服务端使用下划线命名）。
        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, status
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case commitSHA = "commit_sha"
        }
    }

    /// 解析搜索响应，转换为扩展列表条目数组。
    static func parseStore(_ data: Data) throws -> [ExtensionListing] {
        try JSONDecoder().decode(StorePayload.self, from: data).data.compactMap(listing(from:))
    }

    /// 查询接口直接返回该条目本身，而不是一页列表。
    static func parseEntry(_ data: Data) throws -> ExtensionListing? {
        listing(from: try JSONDecoder().decode(StoreEntry.self, from: data))
    }

    /// 无可用于下载地址的条目会被丢弃，而不是作为不可安装项列出。
    private static func listing(from entry: StoreEntry) -> ExtensionListing? {
        // 已下架的扩展仍会被搜索返回；但它已无法再下载。
        guard entry.status == nil || entry.status == "active" else { return nil }
        guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
        return ExtensionListing(
            id: entry.id,
            name: entry.name,
            title: entry.title ?? entry.name,
            summary: entry.description ?? "",
            author: entry.author?.name ?? entry.author?.handle ?? "",
            lightIconURL: entry.icons?.light.flatMap(URL.init(string:)),
            darkIconURL: entry.icons?.dark.flatMap(URL.init(string:)),
            commandCount: entry.commands?.count ?? 0,
            downloadCount: entry.downloadCount,
            downloadURL: url,
            commitSHA: entry.commitSHA)
    }
}

    /// 商店与下载过程中可能出现的错误。
enum ExtensionStoreError: LocalizedError {
    /// 响应格式无法解析。
    case malformedResponse
    /// 服务端拒绝，字符串为拒绝原因。
    case rejected(String)
    /// 下载失败，字符串为原因。
    case downloadFailed(String)
    /// 未找到任何可用的包管理器。
    case noPackageManager
    /// 未找到 Node。
    case noNode
    /// 构建失败，字符串为构建输出。
    case buildFailed(String)
    /// 下载内容不是合法的 Raycast 扩展。
    case notAnExtension

    /// 面向用户的本地化错误描述。
    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "The server answered with something this version doesn't understand."
        case .rejected(let message):
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .noPackageManager:
            return
                "No package manager was found. Install pnpm, npm, Yarn or Bun, or add the folder "
                + "it lives in to Custom search paths."
        case .noNode:
            return
                "Node wasn't found. Install Node.js, add the folder it lives in to Custom search "
                + "paths, or install this extension from the Raycast Store instead."
        case .buildFailed(let output):
            return "The extension didn't build: \(output)"
        case .notAnExtension:
            return "That download didn't contain a Raycast extension."
        }
    }
}
