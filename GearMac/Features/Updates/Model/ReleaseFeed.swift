// 文件职责：解析 GitHub Releases 响应，挑出本构建可安装的最新发布。
// 分层：Model/解析（纯函数，无 I/O）；网络请求由 UpdateCheckStore 负责。
import Foundation

/// 一条本构建可安装的已发布版本，只保留更新器需要的字段。
struct AvailableRelease: Codable, Hashable, Sendable {
    let version: AppVersion
    let tag: String
    let notes: String
    let assetURL: URL
    let assetSize: Int64
    let publishedAt: Date?
}

/// 全程不抛错：响应不可用时即视为无更新，由轮询任务稍后重试。
enum ReleaseFeed {
    /// 发布来源仓库，也是发布说明中每个 `@handle` 与 `#304` 指向的仓库。
    static let repository = "GearMac/GearMac"

    /// 唯一带 x86_64 切片的产物，因此也是 Intel Mac 唯一能安装的产物。
    private static let universalMarker = "-Universal-"

    /// 该通道可接受的最新发布，忽略草稿与没有可用 zip 的条目。
    static func newest(
        from data: Data, channel: ReleaseChannel, architecture: ReleaseArchitecture
    ) -> AvailableRelease? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        return
            entries
            .compactMap { release(from: $0, channel: channel, architecture: architecture) }
            .max { $0.version < $1.version }
    }

    /// 值得提供的发布：严格新于当前运行版本，且未被跳过。
    static func offer(
        _ release: AvailableRelease?, running: AppVersion, skipped: AppVersion?
    ) -> AvailableRelease? {
        guard let release, release.version > running else { return nil }
        if let skipped, release.version <= skipped { return nil }
        return release
    }

    private static func release(
        from entry: Entry, channel: ReleaseChannel, architecture: ReleaseArchitecture
    ) -> AvailableRelease? {
        guard !entry.draft, channel.accepts(prerelease: entry.prerelease),
            let version = AppVersion(entry.tagName),
            // tag 与 prerelease 标记不一致属于发布出错，不作为更新处理。
            version.isPrerelease == entry.prerelease,
            let asset = asset(from: entry.assets, for: architecture)
        else { return nil }
        return AvailableRelease(
            version: version,
            tag: entry.tagName,
            notes: ReleaseNotes.summary(of: entry.body ?? ""),
            assetURL: asset.browserDownloadURL,
            assetSize: asset.size,
            publishedAt: entry.publishedAt.flatMap { try? Date($0, strategy: .iso8601) })
    }

    /// 绝不选 DMG：更新器解压归档，而不是挂载磁盘映像。
    private static func asset(
        from assets: [Entry.Asset], for architecture: ReleaseArchitecture
    ) -> Entry.Asset? {
        let zips = assets.filter { $0.name.hasSuffix(".zip") }
        let universal = zips.first { $0.name.contains(universalMarker) }
        switch architecture {
        case .intel: return universal
        case .appleSilicon: return zips.first { !$0.name.contains(universalMarker) } ?? universal
        }
    }

    /// GitHub Releases API 单条响应的解码模型。
    private struct Entry: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft, body, assets
            case publishedAt = "published_at"
        }

        /// 单条发布的下载资源。
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, size
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
