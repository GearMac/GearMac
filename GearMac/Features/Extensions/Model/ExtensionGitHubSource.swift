// 文件职责：表示并解析扩展的 GitHub 来源（仓库根目录或其中一个子目录 + ref），并构造 tree/raw 下载 URL 与 Git tree 模型。
// 分层：Model；仅做字符串解析、URL 构造与 JSON 解码，不 import AppKit/SwiftUI。
import Foundation

/// 扩展在 GitHub 上的来源：仓库根目录，或它的某个子目录，对应某个 ref。
struct ExtensionGitHubSource: Hashable, Sendable {
    /// 跟随默认分支，无论仓库如何命名它。
    static let defaultRef = "HEAD"

    let owner: String
    let repository: String
    /// 扩展所在目录，不含首尾斜杠；仓库根目录时为空字符串。
    let path: String
    /// 分支、标签或 commit。
    let ref: String

    /// owner 允许的字符集：字母数字加连字符。
    private static let ownerCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    /// 仓库名允许的字符集：在 owner 字符集基础上再加下划线与点。
    private static let repositoryCharacters = ownerCharacters.union(CharacterSet(charactersIn: "_."))

    /// 接受 `owner/repo`、clone URL，或浏览器复制的 `/tree/<ref>/<path>` 链接。
    init?(_ text: String) {
        var rest = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0 != "?" && $0 != "#" })
        for prefix in ["https://", "http://", "git@github.com:", "www.github.com/", "github.com/"]
        where rest.hasPrefix(prefix) {
            rest.removeFirst(prefix.count)
        }
        if rest.hasSuffix(".git") { rest.removeLast(4) }

        let parts = rest.split(separator: "/").map(String.init)
        // 遵循 GitHub 自身的命名规则，从而使其他主机的 URL 被拒绝而不是被误读。
        guard parts.count >= 2,
            parts[0].unicodeScalars.allSatisfy(Self.ownerCharacters.contains),
            parts[1].unicodeScalars.allSatisfy(Self.repositoryCharacters.contains)
        else { return nil }

        if parts.count == 2 {
            ref = Self.defaultRef
            path = ""
        } else if parts.count >= 4, parts[2] == "tree" {
            ref = parts[3]
            path = parts.dropFirst(4).joined(separator: "/")
        } else {
            return nil
        }
        owner = parts[0]
        repository = parts[1]
    }

    /// 供 UI 展示的简短描述，如 "owner/repo at main" 或默认分支形式。
    var summary: String {
        let location = [owner, repository, path].filter { !$0.isEmpty }.joined(separator: "/")
        return ref == Self.defaultRef ? "\(location) on its default branch" : "\(location) at \(ref)"
    }

    /// 用 trees 而非 contents：contents 接口将单个目录上限设为 1000，且每层额外消耗一次请求。
    func treeURL(sha: String, recursive: Bool = false) -> URL? {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/git/trees/\(sha)")
        if recursive { components?.queryItems = [URLQueryItem(name: "recursive", value: "1")] }
        return components?.url
    }

    /// 文件正文由此获取，不计入 GitHub 匿名 API 的配额。
    func rawURL(for file: String) -> URL? {
        let location = [owner, repository, ref, path, file].filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let escaped = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(escaped)")
    }

    // MARK: - Trees

    /// 一棵 Git tree：目录包含的内容，按 sha 而非路径组织。
    struct Tree: Decodable, Sendable {
        let tree: [Entry]
        /// 当 GitHub 放弃列完时会被设置：返回的只是前缀，而非整个目录。
        let truncated: Bool?

        /// Git tree 中的一个条目。
        struct Entry: Decodable, Sendable {
            let path: String
            let type: String
            let sha: String
            let mode: String?

            var isDirectory: Bool { type == "tree" }
            var isFile: Bool { type == "blob" }
            var isExecutable: Bool { isFile && mode == "100755" }
        }

        /// 按名称查找子目录并返回其 sha；找不到时返回 nil。
        func directorySHA(named name: String) -> String? {
            tree.first { $0.path == name && $0.isDirectory }?.sha
        }
    }

    /// 解析 tree 列表；若 GitHub 返回的是错误信息则抛出对应错误。
    static func parseTree(_ data: Data) throws -> Tree {
        if let tree = try? JSONDecoder().decode(Tree.self, from: data) { return tree }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.rejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }
}
