// 文件职责：集中计算各渠道下 GearMac 的存储路径（缓存、Application Support、settings.json、内容目录）。
// 分层：Service；以 bundle id 区分渠道，保证 Dev 构建不与稳定版共用目录。
import Foundation

/// 按渠道区分的存储根目录。以 bundle id 为键，保证 Dev 构建永远不与稳定版共用目录。
enum AppPaths {
    /// 返回该渠道的缓存目录。
    static func caches(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
    ) -> URL {
        root(.cachesDirectory, bundleID: bundleID)
    }

    /// 返回该渠道的 Application Support 目录。
    static func applicationSupport(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
    ) -> URL {
        root(.applicationSupportDirectory, bundleID: bundleID)
    }

    /// `~/.config/gearmac/settings.json`；其他渠道会给文件夹加后缀，如 `gearmac-dev`。
    static func settingsFile(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
    ) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: configFolderName(bundleID: bundleID), directoryHint: .isDirectory)
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    /// Snippets 或 Notes：用户选定的文件夹，否则退回其在 Application Support 下的默认位置。
    static func contentFolder(
        _ chosen: String?, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
    ) -> URL {
        guard let chosen, isFolderPath(chosen) else {
            return applicationSupport(bundleID: bundleID).appending(path: name, directoryHint: .isDirectory)
        }
        // 在此处一次性解析，使本身为符号链接的文件夹也能像普通文件夹一样被列出。
        return URL(filePath: (chosen as NSString).expandingTildeInPath, directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
    }

    /// 选定文件夹的存储形式：默认情况为 nil，否则尽可能用 `~` 相对路径。
    static func contentFolderSetting(
        for url: URL, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
    ) -> String? {
        let chosen = url.standardizedFileURL.resolvingSymlinksInPath()
        let standard = contentFolder(nil, named: name, bundleID: bundleID).resolvingSymlinksInPath()
        guard chosen.path != standard.path else { return nil }
        return (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    /// 绝对路径或以 `~/` 开头，保证同一路径在每台 Mac 上都指向同一文件夹。
    static func isFolderPath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~/")
    }

    /// 由 bundle id 推导配置文件夹名：稳定版为 `gearmac`，子渠道为 `gearmac-<后缀>`。
    private static func configFolderName(bundleID: String) -> String {
        let stable = "com.gearmac.app"
        if bundleID == stable { return "gearmac" }
        guard bundleID.hasPrefix(stable + ".") else { return bundleID }
        return "gearmac-" + bundleID.dropFirst(stable.count + 1)
    }

    /// 返回系统目录下以 bundle id 命名的子目录，并确保它已创建。
    private static func root(
        _ directory: FileManager.SearchPathDirectory, bundleID: String
    ) -> URL {
        let url = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
