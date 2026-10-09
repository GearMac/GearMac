// 文件职责：定义已安装扩展的数据模型，并提供扩展的安装、扫描、卸载与目录布局逻辑。
// 分层：Service/Model；磁盘布局沿用 Raycast 自身结构，安装目录以 bundle id 区分渠道。
import Foundation

/// 已安装的扩展：其 manifest 加上它在磁盘上的位置。
struct InstalledExtension: Sendable, Hashable, Identifiable {
    let manifest: ExtensionManifest
    let directory: URL
    /// 由 `scan` 在主 actor 之外读取，因此发布启动器列表项时绝不会触碰磁盘。
    var installedAt: Date?

    var id: String { manifest.name }
    var title: String { manifest.title }

    /// 图标资源通常位于 `assets/`，但少数 manifest 指向扩展根目录。
    var iconPath: String? {
        guard let icon = manifest.icon else { return nil }
        let candidates = [
            directory.appendingPathComponent("assets").appendingPathComponent(icon),
            directory.appendingPathComponent(icon)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    var assetsPath: String { directory.appendingPathComponent("assets").path }

    /// 某个命令的预构建 CommonJS bundle；安装不完整时返回 nil。
    func bundleURL(for command: ExtensionCommand) -> URL? {
        let url = directory.appendingPathComponent("\(command.name).js")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 按名称查找该扩展的某个命令。
    func command(named name: String) -> ExtensionCommand? {
        manifest.commands.first { $0.name == name }
    }
}

/// 某个扩展中的具体命令 —— 启动器实际激活的对象。
struct ExtensionCommandRef: Sendable, Hashable {
    let extensionName: String
    let commandName: String

    /// 扩展命令对外暴露时使用的 `AppEntry.id`。
    var entryID: String { "extension:\(extensionName)/\(commandName)" }

    init(extensionName: String, commandName: String) {
        self.extensionName = extensionName
        self.commandName = commandName
    }

    init?(entryID: String) {
        guard entryID.hasPrefix("extension:") else { return nil }
        let body = entryID.dropFirst("extension:".count)
        guard let slash = body.lastIndex(of: "/") else { return nil }
        extensionName = String(body[body.startIndex..<slash])
        commandName = String(body[body.index(after: slash)...])
    }
}

/// 查找并安装扩展，沿用 Raycast 自身的目录布局，使已构建的扩展可直接导入。
enum ExtensionCatalog {
    /// 以 bundle id 作为键，因此 Debug 构建永远不会与正式发布渠道共用安装目录。
    static func extensionsDirectory() -> URL {
        supportDirectory().appendingPathComponent("extensions", isDirectory: true)
    }

    static func storageDirectory() -> URL {
        supportDirectory().appendingPathComponent("extension-data", isDirectory: true)
    }

    /// 位于 `extension-data` 之外；清理扫描会把该目录下的每个文件都视为某个扩展自身的数据。
    static func commandMetadataFile() -> URL {
        supportDirectory().appendingPathComponent("extension-commands.json", isDirectory: false)
    }

    /// 与 `commandMetadataFile` 一样，位于清理扫描会读取的目录之外。
    static func storeVersionsFile() -> URL {
        supportDirectory().appendingPathComponent("extension-versions.json", isDirectory: false)
    }

    /// 每个扩展的 `environment.supportPath` —— 扩展自己的临时目录。
    static func supportPath(for name: String) -> URL {
        supportRoot().appendingPathComponent(safeName(name), isDirectory: true)
    }

    static func supportRoot() -> URL {
        supportDirectory().appendingPathComponent("extension-support", isDirectory: true)
    }

    /// 把 npm 风格的名称压平为单个路径段；若第二处实现发生偏移，会使每个文件都变成孤儿。
    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "@", with: "")
    }

    private static func supportDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `raycast-x` 是 Beta v2；两个根目录可以同时存在，切换渠道会让另一个变空。
    static func raycastExtensionRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["raycast", "raycast-x"].map {
            home.appendingPathComponent(".config/\($0)/extensions", isDirectory: true)
        }
    }

    /// 返回第一个非空的根目录，因此空的渠道不会被误判为未安装。
    static func raycastExtensionsDirectory() -> URL? {
        raycastExtensionRoots().first { root in
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return !(entries ?? []).isEmpty
        }
    }

    /// 无法读取或写了一半的目录会被跳过，而不是让整个扫描失败。
    nonisolated static func scan() -> [InstalledExtension] {
        let root = extensionsDirectory()
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .addedToDirectoryDateKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            entries
            .compactMap { directory -> InstalledExtension? in
                try? restoreExecutablePermissions(in: directory)
                guard let manifest = try? ExtensionManifest.load(directory: directory),
                    manifest.supportsMacOS
                else { return nil }
                let added = try? directory.resourceValues(forKeys: [.addedToDirectoryDateKey])
                return InstalledExtension(
                    manifest: manifest, directory: directory, installedAt: added?.addedToDirectoryDate)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// GitHub 的原始文件下载会丢失权限位，因此按内容恢复可执行的辅助资源。
    nonisolated static func restoreExecutablePermissions(in directory: URL) throws {
        let fileManager = FileManager.default
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        guard
            let enumerator = fileManager.enumerator(
                at: assets,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        else { return }

        while let file = enumerator.nextObject() as? URL {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                !fileManager.isExecutableFile(atPath: file.path), isExecutablePayload(file)
            else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: file.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            let executeBits = (permissions & 0o444) >> 2
            try fileManager.setAttributes(
                [.posixPermissions: permissions | executeBits], ofItemAtPath: file.path)
        }
    }

    private nonisolated static func isExecutablePayload(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4) else { return false }
        let bytes = Array(data)
        if bytes.starts(with: [0x23, 0x21]) { return true }
        return [
            [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],
            [0xCA, 0xFE, 0xBA, 0xBF], [0xBF, 0xBA, 0xFE, 0xCA],
            [0xCE, 0xFA, 0xED, 0xFE], [0xCF, 0xFA, 0xED, 0xFE],
            [0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF]
        ].contains(bytes)
    }

    // MARK: - Install

    /// 安装失败的原因分类与面向用户的错误描述。
    enum InstallError: LocalizedError {
        case notAnExtension(URL)
        case noBuiltCommands(String)
        case wrongPlatform(String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAnExtension(let url):
                return
                    "\(url.lastPathComponent) doesn't contain a Raycast extension (no package.json with commands)."
            case .noBuiltCommands(let name):
                return
                    "\(name) has no built command bundles. GearMac installs prebuilt extensions — run `ray build` in the extension folder first, or import one from an installed Raycast."
            case .wrongPlatform(let name):
                return "\(name) doesn't support macOS."
            case .copyFailed(let reason):
                return "Couldn't install the extension: \(reason)"
            }
        }
    }

    /// 只复制 manifest、已构建的命令和 `assets/` —— 绝不包含 `node_modules` 或 `.js.map`。
    @discardableResult
    static func install(from source: URL) throws -> InstalledExtension {
        guard let manifest = try? ExtensionManifest.load(directory: source) else {
            throw InstallError.notAnExtension(source)
        }
        guard manifest.supportsMacOS else { throw InstallError.wrongPlatform(manifest.title) }

        let fm = FileManager.default
        let built = manifest.commands.filter {
            fm.fileExists(atPath: source.appendingPathComponent("\($0.name).js").path)
        }
        guard !built.isEmpty else { throw InstallError.noBuiltCommands(manifest.title) }

        let destination = extensionsDirectory().appendingPathComponent(
            manifest.name.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.copyItem(
                at: source.appendingPathComponent("package.json"),
                to: destination.appendingPathComponent("package.json"))
            for command in built {
                let file = "\(command.name).js"
                try fm.copyItem(
                    at: source.appendingPathComponent(file),
                    to: destination.appendingPathComponent(file))
            }
            let assets = source.appendingPathComponent("assets")
            if fm.fileExists(atPath: assets.path) {
                try fm.copyItem(at: assets, to: destination.appendingPathComponent("assets"))
            }
            try restoreExecutablePermissions(in: destination)
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }

        // 从安装位置重新读取，使返回值指向副本而非源目录。
        let installedManifest = try ExtensionManifest.load(directory: destination)
        return InstalledExtension(manifest: installedManifest, directory: destination)
    }

    /// 清理它拥有的两个路径：没有别处会回收该临时目录，而对话框也承诺它会被删除。
    static func uninstall(_ installed: InstalledExtension) throws {
        try? FileManager.default.removeItem(at: supportPath(for: installed.manifest.name))
        try FileManager.default.removeItem(at: installed.directory)
    }

    /// Raycast 以 UUID 索引安装项，因此只有 manifest 能说明一个目录里装的是什么。
    nonisolated static func importableFromRaycast() -> [InstalledExtension] {
        let fm = FileManager.default
        let entries = raycastExtensionRoots().flatMap { root in
            (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return
            entries
            .compactMap { directory -> InstalledExtension? in
                guard let manifest = try? ExtensionManifest.load(directory: directory),
                    manifest.supportsMacOS,
                    // 跳过安装了一半或只有源码的目录。
                    manifest.commands.contains(where: {
                        fm.fileExists(atPath: directory.appendingPathComponent("\($0.name).js").path)
                    })
                else { return nil }
                return InstalledExtension(manifest: manifest, directory: directory)
            }
            // 两个渠道可能都存有同一个扩展；靠前的根目录优先，因此只提供一次。
            .reduce(into: [InstalledExtension]()) { unique, candidate in
                guard !unique.contains(where: { $0.manifest.name == candidate.manifest.name }) else {
                    return
                }
                unique.append(candidate)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
