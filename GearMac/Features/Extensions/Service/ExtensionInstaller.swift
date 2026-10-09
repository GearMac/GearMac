// 文件职责：从扩展商店（预构建 zip）或 GitHub 源码（本地安装依赖并构建）完成扩展安装，并上报安装进度。
// 分层：Service；所有安装都在临时工作目录中完成，结束后无论成败都会删除。
import Foundation

/// 从商店或 GitHub 源码安装，整个过程在一个无论结果如何都会被删除的工作目录中进行。
struct ExtensionInstaller: Sendable {
    /// 从源码安装可能耗时数分钟，长时间无反馈会被当作卡死。
    enum Progress: Sendable, Equatable {
        case downloading
        case installingDependencies(manager: String)
        case building
        case installing

        var message: String {
            switch self {
            case .downloading: return "Downloading…"
            case .installingDependencies(let manager): return "Installing dependencies with \(manager)…"
            case .building: return "Building…"
            case .installing: return "Installing…"
            }
        }
    }

    /// 足够慢速网络下的首次安装完成，又不至于让卡死的子进程永久挂起。
    private static let commandTimeout: TimeInterval = 300

    let client: ExtensionStoreClient
    let packageManager: ExtensionPackageManager
    /// 来自 `extensionCustomSearchPaths`，在内置搜索路径列表之前检查。
    let additionalSearchPaths: [String]

    init(
        client: ExtensionStoreClient = ExtensionStoreClient(),
        packageManager: ExtensionPackageManager = .automatic, additionalSearchPaths: [String] = []
    ) {
        self.client = client
        self.packageManager = packageManager
        self.additionalSearchPaths = additionalSearchPaths
    }

    /// 安装商店中的预构建扩展（下载 zip 并解压）。
    @discardableResult
    func install(
        _ listing: ExtensionListing, onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> InstalledExtension {
        try await inWorkspace(onProgress: onProgress) { workspace in
            onProgress(.downloading)
            return try await preparePrebuilt(from: listing.downloadURL, in: workspace)
        }
    }

    /// 从 GitHub 源码安装：只把构建产物复制出去；源码及其依赖随工作目录一起删除。
    @discardableResult
    func install(
        _ source: ExtensionGitHubSource, onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> InstalledExtension {
        try await inWorkspace(onProgress: onProgress) { workspace in
            onProgress(.downloading)
            let checkout = workspace.appendingPathComponent("source", isDirectory: true)
            try await client.downloadFolder(source, to: checkout)
            return try await build(
                at: try validated(checkout),
                into: workspace.appendingPathComponent("build", isDirectory: true),
                onProgress: onProgress)
        }
    }

    /// 在工作目录删除前复制到位，因此能返回安装结果。
    private func inWorkspace(
        onProgress: (Progress) -> Void, prepare: (URL) async throws -> URL
    ) async throws -> InstalledExtension {
        let workspace = ExtensionCleanup.workspace(in: FileManager.default.temporaryDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let prepared = try await prepare(workspace)
        onProgress(.installing)
        return try ExtensionCatalog.install(from: prepared)
    }

    // MARK: - Prebuilt

    private func preparePrebuilt(from url: URL, in workspace: URL) async throws -> URL {
        let data = try await client.download(url)
        let archive = workspace.appendingPathComponent("extension.zip")
        try data.write(to: archive, options: .atomic)

        let expanded = workspace.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)
        // `ditto` 随 macOS 提供，能处理商店分发的 zip；Foundation 没有解压能力。
        let result = try await run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, expanded.path], in: workspace)
        guard result.status == 0 else {
            throw ExtensionStoreError.downloadFailed(result.trimmedOutput)
        }
        return try locateManifestRoot(in: expanded)
    }

    /// 商店的 zip 会把扩展包在一个目录里，本地构建则可能不会。两种都接受。
    private func locateManifestRoot(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("package.json").path) {
            return directory
        }
        let children =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        for child in children
        where fileManager.fileExists(atPath: child.appendingPathComponent("package.json").path) {
            return child
        }
        throw ExtensionStoreError.notAnExtension
    }

    // MARK: - Source

    /// 返回用于安装的目录：`ray` 产出产物时返回 `output`，否则返回 `source`。
    private func build(
        at source: URL, into output: URL, onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let resolved = packageManager.resolve(additionalSearchPaths: additionalSearchPaths) else {
            throw ExtensionStoreError.noPackageManager
        }
        guard let node = ExtensionPackageManager.nodeURL(additionalSearchPaths: additionalSearchPaths)
        else {
            throw ExtensionStoreError.noNode
        }

        onProgress(.installingDependencies(manager: resolved.manager.title))
        let install = try await run(
            resolved.url, arguments: resolved.manager.installArguments, in: source, node: node)
        guard install.status == 0 else {
            throw ExtensionStoreError.buildFailed(install.trimmedOutput)
        }

        onProgress(.building)
        let ray = source.appendingPathComponent("node_modules/.bin/ray")
        guard FileManager.default.isExecutableFile(atPath: ray.path) else {
            // 不是 Raycast 构建：其自带脚本是唯一约定，且产物原地输出。
            let build = try await run(
                resolved.url, arguments: resolved.manager.buildArguments, in: source, node: node)
            guard build.status == 0 else {
                throw ExtensionStoreError.buildFailed(build.trimmedOutput)
            }
            return try validated(source)
        }

        // 直接调用 `ray`，`-o` 绝不指向源码目录：开发模式安装会清空它。
        let build = try await run(
            ray,
            arguments: [
                "build", "-e", environment(for: source), "-o", output.path, "--non-interactive"
            ],
            in: source, node: node)
        guard build.status == 0 else {
            throw ExtensionStoreError.buildFailed(build.trimmedOutput)
        }
        return try validated(output)
    }

    /// `dist` 会为 Windows 构建 `rust:` 辅助程序，这在此处是死代码且需要 macOS 上
    /// 无人具备的工具链；`dev` 环境的 Rust 插件则会把它替换为空实现。
    private func environment(for source: URL) -> String {
        let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == "node_modules" { enumerator?.skipDescendants() }
            if candidate.lastPathComponent == "Cargo.toml" { return "dev" }
        }
        return "dist"
    }

    private func validated(_ directory: URL) throws -> URL {
        guard
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("package.json").path)
        else { throw ExtensionStoreError.notAnExtension }
        return directory
    }

    // MARK: - Running a child process

    /// 子进程的运行结果。
    private struct CommandResult {
        let status: Int32
        let output: String

        /// 取输出末尾，包管理器通常在那里给出真正的错误。
        var trimmedOutput: String {
            let lines = output.split(separator: "\n").suffix(6)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "no output" : text
        }
    }

    /// 以适配 GUI 应用的 PATH 运行工具，GUI 应用不继承登录 shell 的任何环境。
    private func run(
        _ executable: URL, arguments: [String], in directory: URL, node: URL? = nil
    ) async throws -> CommandResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory

        var environment = ProcessInfo.processInfo.environment
        var searchPath = additionalSearchPaths + ExtensionPackageManager.searchPaths
        // Node 放最前：包管理器会按 PATH 启动 `ray`，而版本管理器会把 Node 藏起来。
        if let node { searchPath.insert(node.deletingLastPathComponent().path, at: 0) }
        environment["PATH"] = searchPath.joined(separator: ":")
        // 防止 npm 把进度条写进我们在失败时展示的输出。
        environment["CI"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 关闭安装会终止子进程，因此被取消的构建不会比其工作目录存活更久。
        var timeout: Task<Void, Never>?
        defer { timeout?.cancel() }
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // 只 resume 一次，取「进程结束」与「超时」中先到者。
                let state = ResumeGuard()
                process.terminationHandler = { finished in
                    let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                    guard state.claim() else { return }
                    continuation.resume(
                        returning: CommandResult(
                            status: finished.terminationStatus,
                            output: String(decoding: data, as: UTF8.self)))
                }
                do {
                    try process.run()
                } catch {
                    guard state.claim() else { return }
                    continuation.resume(throwing: error)
                    return
                }
                // 在启动之前到达的取消请求当时没有可终止的进程，这里补上。
                if Task.isCancelled { Self.stop(process) }
                timeout = Task {
                    try? await Task.sleep(for: .seconds(Self.commandTimeout))
                    guard !Task.isCancelled, process.isRunning else { return }
                    Self.stop(process)
                    guard state.claim() else { return }
                    continuation.resume(
                        returning: CommandResult(status: -1, output: "timed out after 5 minutes"))
                }
            }
        } onCancel: {
            Self.stop(process)
        }
        try Task.checkCancellation()
        return result
    }

    /// `Process` 会让子进程成为进程组组长，因此这个信号能覆盖包管理器派生的所有进程。
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        kill(-process.processIdentifier, SIGTERM)
    }
}

/// 保证两条竞态路径中只有一条能 resume continuation。
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// 尝试认领这一次 resume；已被认领时返回 false。
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
