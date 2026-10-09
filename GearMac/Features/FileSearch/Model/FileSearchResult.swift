// 文件职责：表示一条文件搜索结果（路径、名称、所在目录、是否为目录），并把父目录路径缩写为以 ~ 开头。
// 分层：Model；纯值类型，不引入副作用。
import Foundation

/// 一条文件搜索结果。
struct FileSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let parentPath: String
    /// 所在文件夹自身的名称，用于区分两个同名的文件夹。
    let parentName: String
    let isDirectory: Bool

    /// 从文件 URL 派生出名称、缩写后的父目录路径等信息。
    init(url: URL, isDirectory: Bool, homeDirectory: URL) {
        let url = url.standardizedFileURL
        let parent = url.deletingLastPathComponent()
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.parentPath = Self.abbreviate(
            parent.path, homePath: homeDirectory.standardizedFileURL.path)
        self.parentName = parent.lastPathComponent
        self.isDirectory = isDirectory
    }

    private static func abbreviate(_ path: String, homePath: String) -> String {
        if path == homePath { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}
