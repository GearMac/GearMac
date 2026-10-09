// 文件职责：把设置中配置的搜索范围解析为搜索策略，区分 Spotlight 可直接使用的根目录与需要展开的家目录分支，并合并出忽略规则。
// 分层：Model；纯值类型，不引入副作用。
import Foundation

/// 解释一份已配置的范围列表：哪些根目录 Spotlight 可直接使用，以及需要舍弃哪些。
struct FileSearchPolicy: Sendable, Equatable {
    let homeDirectory: URL
    /// 家目录被单独区分：因为 `~/Library` 永远不会作为搜索范围，需要单独处理。
    let directRoots: [URL]
    let includesHome: Bool
    let ignore: FileSearchIgnoreList

    /// 根据范围、忽略模式与家目录构造策略。
    init(scopes: [String], ignorePatterns: [String], homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        let home = homeDirectory.standardizedFileURL.path
        let roots = FileSearchScope.roots(for: scopes, homeDirectory: homeDirectory)
        directRoots = roots.filter { $0.path != home }
        includesHome = roots.count != directRoots.count
        ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + ignorePatterns)
    }
}
