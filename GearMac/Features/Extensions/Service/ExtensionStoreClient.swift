// 文件职责：与扩展商店（Extension Store）交互：搜索/查询扩展，并从商店或 GitHub 下载安装包字节。
// 分层：Service；无缓存会话，只做网络 IO，不持有 UI 状态。
import Foundation

/// 商店的搜索接口，以及安装包字节的两处来源。
struct ExtensionStoreClient: Sendable {
    /// 不使用缓存、也绝不用 `URLSession.shared`，使搜索或下载不会在磁盘上留下第二份副本。
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let session: URLSession

    /// 允许注入自定义会话以便测试。
    init(session: URLSession = ExtensionStoreClient.defaultSession) {
        self.session = session
    }

    /// 按关键词搜索商店，返回扩展列表。
    func search(_ query: String) async throws -> [ExtensionListing] {
        guard let url = ExtensionStoreResponse.searchURL(query: query, page: 1) else {
            throw ExtensionStoreError.malformedResponse
        }
        return try ExtensionStoreResponse.parseStore(try await get(url))
    }

    /// 商店有该扩展但无法提供时（例如已下架）返回 nil。
    func lookup(handle: String, name: String) async throws -> ExtensionListing? {
        guard let url = ExtensionStoreResponse.lookupURL(handle: handle, name: name) else {
            throw ExtensionStoreError.malformedResponse
        }
        return try ExtensionStoreResponse.parseEntry(try await get(url))
    }

    /// 下载商店提供的安装包数据。
    func download(_ url: URL) async throws -> Data {
        try await get(url)
    }

    // MARK: - GitHub

    /// 构建时永远用不到，且是某些扩展目录中最占体积的部分。
    private static let skippedDirectories: Set<String> = ["node_modules", "metadata"]

    /// 先取一次递归 tree，再拉取 raw blob：`contents` 每目录消耗一次 API 调用，
    /// 而匿名额度只有每小时 60 次——一个带 17 个目录的扩展曾占掉其中三分之一。
    func downloadFolder(_ source: ExtensionGitHubSource, to destination: URL) async throws {
        guard let url = source.treeURL(sha: try await treeSHA(of: source), recursive: true) else {
            throw ExtensionStoreError.malformedResponse
        }
        let tree = try ExtensionGitHubSource.parseTree(try await get(url))
        guard tree.truncated != true else {
            throw ExtensionStoreError.downloadFailed("\(source.summary) is too large to download.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in tree.tree where entry.isFile {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.contains(where: Self.skippedDirectories.contains),
                let raw = source.rawURL(for: entry.path)
            else { continue }
            let target = components.reduce(destination) { $0.appendingPathComponent($1) }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await get(raw).write(to: target, options: .atomic)
            if entry.isExecutable {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
        }
    }

    /// 沿路径逐段走到目标 tree：trees API 要求 sha，只有根目录才能传 ref。
    private func treeSHA(of source: ExtensionGitHubSource) async throws -> String {
        var sha = source.ref
        for segment in source.path.split(separator: "/").map(String.init) {
            guard let url = source.treeURL(sha: sha) else {
                throw ExtensionStoreError.malformedResponse
            }
            guard
                let next = try ExtensionGitHubSource.parseTree(try await get(url))
                    .directorySHA(named: segment)
            else {
                throw ExtensionStoreError.rejected(
                    "\(source.owner)/\(source.repository) has no \(source.path) folder at \(source.ref).")
            }
            sha = next
        }
        return sha
    }

    // MARK: - Fetching

    /// 带必要请求头发起 GET；GitHub API 错误时尽量提取响应体中的 message 作为错误描述。
    private func get(_ url: URL) async throws -> Data {
        let isGitHubAPI = url.host == "api.github.com"
        var request = URLRequest(url: url)
        // GitHub 在不带该头时返回旧媒体类型，并会拒绝没有 user agent 的请求。
        request.setValue("GearMac", forHTTPHeaderField: "User-Agent")
        if isGitHubAPI {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            // 因为是匿名请求，私有仓库的表现与仓库不存在完全一致。
            if isGitHubAPI, http.statusCode == 404 {
                throw ExtensionStoreError.rejected(
                    "That repository or branch wasn't found. A private repository can't be read.")
            }
            // GitHub 会在响应体中说明限流原因；直接透出比只报一个 403 更有用。
            struct Message: Decodable { let message: String }
            if let error = try? JSONDecoder().decode(Message.self, from: data) {
                throw ExtensionStoreError.rejected(error.message)
            }
            throw ExtensionStoreError.downloadFailed("HTTP \(http.statusCode)")
        }
        return data
    }
}
