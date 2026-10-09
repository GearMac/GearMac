// 文件职责：snippet 目录的仓库层——加载快照、创建/保存/删除 Markdown 文件，并在写入前做源文件指纹冲突校验。
// 分层：Model/仓库层；带目录级锁与 NSFileCoordinator，不 import AppKit/SwiftUI。
import Foundation

/// snippet 目录的读写仓库：对外提供加载与增删改操作，内部串行化文件访问。
struct SnippetRepository: Sendable {
    /// 除每次访问都要经过的 `NSLock` 外不持有其他状态。
    private final class DirectoryLock: @unchecked Sendable {
        private let lock = NSLock()

        func withLock<Value>(
            _ operation: () throws(RepositoryError) -> Value
        ) throws(RepositoryError) -> Value {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    /// `locks` 只在 `lock.withLock` 内读写，这正是线程安全的全部保证。
    private final class DirectoryLockTable: @unchecked Sendable {
        private let lock = NSLock()
        private var locks: [String: DirectoryLock] = [:]

        func directoryLock(for directory: URL) -> DirectoryLock {
            let identity = canonicalIdentity(for: directory)
            return lock.withLock {
                if let existing = locks[identity] { return existing }
                let directoryLock = DirectoryLock()
                locks[identity] = directoryLock
                return directoryLock
            }
        }

        private func canonicalIdentity(for directory: URL) -> String {
            let fileManager = FileManager.default
            var existingAncestor = directory.standardizedFileURL
            var missingComponents: [String] = []

            while !fileManager.fileExists(atPath: existingAncestor.path) {
                let parent = existingAncestor.deletingLastPathComponent()
                guard parent.path != existingAncestor.path else { break }
                missingComponents.append(existingAncestor.lastPathComponent)
                existingAncestor = parent
            }

            var resolved = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
            for component in missingComponents.reversed() {
                resolved.appendPathComponent(component, isDirectory: true)
            }
            return resolved.standardizedFileURL.path
        }
    }

    private static let directoryLocks = DirectoryLockTable()

    enum Mutation: Sendable {
        case save
        case delete
    }

    /// 测试钩子：在写入前的再次校验之前调用。
    struct MutationHooks: Sendable {
        var beforeRevalidation: @Sendable (Mutation, URL) -> Void = { _, _ in }
    }

    /// 一次加载的结果：成功解析的记录与解析失败的条目。
    struct Snapshot: Sendable, Equatable {
        let records: [StoredSnippet]
        let issues: [Issue]

        /// 磁盘上仍存在的全部文件：解析失败的文件只是在编辑中，而非被删除。
        var fileIDs: Set<StoredSnippet.ID> { Set(records.map(\.id) + issues.map(\.id)) }
    }

    /// 某个文件解析失败的条目，含文件位置与错误描述。
    struct Issue: Identifiable, Sendable, Equatable {
        let fileURL: URL
        let message: String

        var id: String { fileURL.standardizedFileURL.path }
    }

    /// 仓库操作错误；冲突错误携带期望与实际的文件指纹。
    enum RepositoryError: Error, LocalizedError, Sendable, Equatable {
        case conflict(
            fileURL: URL,
            expected: SnippetSourceRevision,
            actual: SnippetSourceRevision?
        )
        case fileNotFound(URL)
        case invalidFileLocation(URL)
        case io(fileURL: URL, message: String)

        /// 面向用户的错误描述。
        var errorDescription: String? {
            switch self {
            case .conflict(let fileURL, _, _):
                return
                    "The snippet changed on disk. Reload it before saving or deleting. (\(fileURL.lastPathComponent))"
            case .fileNotFound(let fileURL):
                return "The snippet file no longer exists. (\(fileURL.lastPathComponent))"
            case .invalidFileLocation(let fileURL):
                return "The snippet file is outside this GearMac channel. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            }
        }

        /// 按界面语言解析的面向用户错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .conflict(let fileURL, _, _):
                return String(
                    format: L10n.string(SnippetsKey.errorConflict, language: language),
                    fileURL.lastPathComponent)
            case .fileNotFound(let fileURL):
                return String(
                    format: L10n.string(SnippetsKey.errorFileNotFound, language: language),
                    fileURL.lastPathComponent)
            case .invalidFileLocation(let fileURL):
                return String(
                    format: L10n.string(SnippetsKey.errorInvalidLocation, language: language),
                    fileURL.path)
            case .io(let fileURL, let message):
                return String(
                    format: L10n.string(SnippetsKey.errorAccessFailed, language: language),
                    fileURL.path, message)
            }
        }
    }

    let bundleIdentifier: String
    let channelDirectory: URL
    let snippetsDirectory: URL

    private let directoryLock: DirectoryLock
    private let mutationHooks: MutationHooks

    /// 以应用支持目录下的「bundleIdentifier/Snippets」为默认位置，并绑定该目录的锁。
    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.gearmac.app",
        applicationSupportRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0],
        snippetsDirectory: URL? = nil,
        mutationHooks: MutationHooks = MutationHooks()
    ) {
        self.bundleIdentifier = bundleIdentifier
        let channelDirectory = applicationSupportRoot.appendingPathComponent(
            bundleIdentifier,
            isDirectory: true)
        self.channelDirectory = channelDirectory
        let snippetsDirectory =
            snippetsDirectory ?? channelDirectory.appendingPathComponent("Snippets", isDirectory: true)
        self.snippetsDirectory = snippetsDirectory
        directoryLock = Self.directoryLocks.directoryLock(for: snippetsDirectory)
        self.mutationHooks = mutationHooks
    }

    /// 读取目录下全部 Markdown 文件并返回快照；解析失败的文件归入 issues。
    func load() throws(RepositoryError) -> Snapshot {
        try directoryLock.withLock { () throws(RepositoryError) -> Snapshot in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                let files = try markdownFiles(in: snippetsDirectory)
                var records: [StoredSnippet] = []
                var issues: [Issue] = []

                for fileURL in files {
                    do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        let snippet = try SnippetMarkdownSerializer.parse(
                            content: content,
                            fileURL: fileURL)
                        records.append(
                            StoredSnippet(
                                fileURL: fileURL,
                                snippet: snippet,
                                sourceRevision: SnippetSourceRevision(content: content)))
                    } catch {
                        issues.append(Issue(fileURL: fileURL, message: error.localizedDescription))
                    }
                }

                records.sort(by: recordOrder)
                issues.sort { $0.fileURL.path < $1.fileURL.path }
                return Snapshot(records: records, issues: issues)
            }
        }
    }

    /// 创建单个 snippet；文件名冲突时追加数字后缀。
    func create(_ snippet: Snippet) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                return try createUnlocked(snippet)
            }
        }
    }

    /// 批量创建；任一失败则回滚已创建的文件（全有或全无）。
    func create(_ snippets: [Snippet]) throws(RepositoryError) -> [StoredSnippet] {
        try directoryLock.withLock { () throws(RepositoryError) -> [StoredSnippet] in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                var created: [StoredSnippet] = []
                do {
                    for snippet in snippets {
                        created.append(try createUnlocked(snippet))
                    }
                    return created
                } catch {
                    for record in created.reversed() {
                        try? FileManager.default.removeItem(at: record.fileURL)
                    }
                    throw error
                }
            }
        }
    }

    /// 保存编辑后的 snippet；文件指纹不匹配时抛出冲突错误。
    func save(
        _ snippet: Snippet,
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                let content = SnippetMarkdownSerializer.serialize(snippet)
                return try coordinatedMutation(at: fileURL, options: .forReplacing) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.save, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    try Data(content.utf8).write(to: mutationURL, options: .atomic)
                    return StoredSnippet(
                        fileURL: fileURL,
                        snippet: snippet,
                        sourceRevision: SnippetSourceRevision(content: content))
                }
            }
        }
    }

    /// 删除 snippet 文件；文件指纹不匹配时抛出冲突错误。
    func delete(
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) {
        try directoryLock.withLock { () throws(RepositoryError) in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                try coordinatedMutation(at: fileURL, options: .forDeleting) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.delete, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    try FileManager.default.removeItem(at: mutationURL)
                }
            }
        }
    }

    /// 只需保证目录存在；`withIntermediateDirectories` 也会一并创建 channel 目录。
    private func ensureSnippetsDirectory() throws {
        try FileManager.default.createDirectory(
            at: snippetsDirectory, withIntermediateDirectories: true)
    }

    /// 列出目录内的可加载 Markdown 文件并按文件名排序。
    private func markdownFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .filter(Self.isLoadableFile)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // 排除名为 `*.md` 的目录或设备节点；只有非普通文件才会额外解析符号链接。
    private static func isLoadableFile(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        return
            (try? url.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// 在锁内创建单个文件：循环选取不冲突的文件名并原子写入。
    private func createUnlocked(_ snippet: Snippet) throws -> StoredSnippet {
        let content = SnippetMarkdownSerializer.serialize(snippet)
        var suffix = 1

        while true {
            let fileURL = uniqueFileURL(
                for: snippet.name,
                suffix: suffix,
                in: snippetsDirectory)
            do {
                try writeNewFileAtomically(Data(content.utf8), to: fileURL)
                return StoredSnippet(
                    fileURL: fileURL,
                    snippet: snippet,
                    sourceRevision: SnippetSourceRevision(content: content))
            } catch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    suffix += 1
                    continue
                }
                throw error
            }
        }
    }

    /// 先写临时文件再原子重命名，失败时清理临时文件。
    private func writeNewFileAtomically(_ data: Data, to fileURL: URL) throws {
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// 由名称与后缀构造文件名；suffix 为 1 时不加后缀。
    private func uniqueFileURL(for name: String, suffix: Int, in directory: URL) -> URL {
        let base = SnippetMarkdownSerializer.slug(for: name)
        let filename = suffix == 1 ? "\(base).md" : "\(base)-\(suffix).md"
        return directory.appendingPathComponent(filename)
    }

    /// 校验文件位于 snippet 目录内且为 .md，返回标准化后的路径。
    private func validatedFileURL(_ fileURL: URL) throws -> URL {
        let standardized = fileURL.standardizedFileURL
        let parentPath = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        let snippetsPath = snippetsDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard parentPath == snippetsPath,
            standardized.pathExtension.lowercased() == "md"
        else {
            throw RepositoryError.invalidFileLocation(fileURL)
        }
        return standardized
    }

    /// 读取文件当前内容的指纹；文件不存在时报错。
    private func revision(at fileURL: URL) throws -> SnippetSourceRevision {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.fileNotFound(fileURL)
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return SnippetSourceRevision(content: content)
    }

    /// 记录排序：按名称不区分大小写升序，同名再按 ID。
    private func recordOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        let comparison = lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    /// 通过 NSFileCoordinator 协调写入或删除操作，避免与其他读写者冲突。
    private func coordinatedMutation<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        fileCoordinator.coordinate(
            writingItemAt: fileURL,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try mutation(coordinatedURL) }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw CocoaError(.fileWriteUnknown)
    }

    /// 把非 RepositoryError 的异常包装为 .io 错误。
    private func mappedError<Value>(
        at fileURL: URL,
        _ operation: () throws -> Value
    ) throws(RepositoryError) -> Value {
        do {
            return try operation()
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }

}
