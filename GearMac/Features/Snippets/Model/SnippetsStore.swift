// 文件职责：Snippets 功能的主状态存储——加载/创建/保存/删除 snippet，监视文件系统变化并发布快照。
// 分层：Model（@MainActor @Observable）；文件 IO 交由 SnippetRepository 在后台执行，UI 只读取其状态。
import Darwin
import Foundation

@MainActor
@Observable
final class SnippetsStore {
    /// store 的加载状态。
    enum State: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var snippets: [StoredSnippet] = []
    private(set) var state: State = .idle
    private(set) var issues: [SnippetRepository.Issue] = []
    private(set) var operationError: String?

    private(set) var snippetsDirectory: URL
    var onSnapshot: ((SnippetRepository.Snapshot) -> Void)?

    private var repository: SnippetRepository
    @ObservationIgnored private var directoryWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var watcherRetryTask: Task<Void, Never>?
    private var generation = 0
    private var watcherGeneration = 0
    private var isStarted = false

    init(repository: SnippetRepository = SnippetRepository()) {
        self.repository = repository
        snippetsDirectory = repository.snippetsDirectory
    }

    isolated deinit {
        reloadTask?.cancel()
        watcherRetryTask?.cancel()
        directoryWatcher?.cancel()
        for source in fileWatchers.values { source.cancel() }
    }

    /// 启动并做一次带加载态的重新读取。
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        await reload(showLoadingState: true)
    }

    /// 停止：递增代号、取消任务并拆除文件监视。
    func stop() {
        isStarted = false
        generation &+= 1
        reloadTask?.cancel()
        reloadTask = nil
        watcherRetryTask?.cancel()
        watcherRetryTask = nil
        stopWatchers()
    }

    /// 切换到另一个目录；运行中的 store 会先停止、替换仓库，再加载新目录。
    func relocate(to repository: SnippetRepository) async {
        guard repository.snippetsDirectory != snippetsDirectory else { return }
        let wasStarted = isStarted
        stop()
        self.repository = repository
        snippetsDirectory = repository.snippetsDirectory
        // 先清空，避免新目录加载失败时仍保留旧 snippet 可被展开。
        if !snippets.isEmpty || !issues.isEmpty {
            snippets = []
            issues = []
            onSnapshot?(SnippetRepository.Snapshot(records: [], issues: []))
        }
        guard wasStarted else { return }
        await start()
    }

    /// 手动重试一次加载。
    func retry() {
        guard isStarted else { return }
        scheduleReload(after: .zero, showLoadingState: true)
    }

    /// 创建 snippet 并乐观更新本地列表，随后触发重新加载。
    @discardableResult
    func create(_ snippet: Snippet) async throws -> StoredSnippet {
        let record = try await performMutation { try $0.create(snippet) }
        guard isStarted else { return record }
        var records = snippets.filter { $0.id != record.id }
        records.append(record)
        publishLocal(records: records)
        scheduleReload(after: .zero)
        return record
    }

    /// 批量导入 snippet，成功后合并进本地列表。
    @discardableResult
    func importSnippets(_ imported: [Snippet]) async throws -> [StoredSnippet] {
        guard !imported.isEmpty else { return [] }
        let created = try await performMutation { try $0.create(imported) }
        guard isStarted else { return created }
        let createdIDs = Set(created.map(\.id))
        publishLocal(records: snippets.filter { !createdIDs.contains($0.id) } + created)
        scheduleReload(after: .zero)
        return created
    }

    /// 保存编辑；成功后替换本地对应记录。
    @discardableResult
    func save(_ record: StoredSnippet) async throws -> StoredSnippet {
        let saved = try await performMutation {
            try $0.save(
                record.snippet,
                fileURL: record.fileURL,
                expectedRevision: record.sourceRevision)
        }
        guard isStarted else { return saved }
        var records = snippets.filter { $0.id != saved.id }
        records.append(saved)
        publishLocal(records: records)
        scheduleReload(after: .zero)
        return saved
    }

    /// 删除指定 snippet 并更新本地列表。
    func delete(id: StoredSnippet.ID) async throws {
        guard let record = record(id: id) else {
            throw SnippetRepository.RepositoryError.fileNotFound(URL(fileURLWithPath: id))
        }
        try await performMutation {
            try $0.delete(
                fileURL: record.fileURL,
                expectedRevision: record.sourceRevision)
        }
        guard isStarted else { return }
        publishLocal(records: snippets.filter { $0.id != id })
        scheduleReload(after: .zero)
    }

    /// 按 ID 查找当前记录。
    func record(id: StoredSnippet.ID) -> StoredSnippet? {
        snippets.first(where: { $0.id == id })
    }

    /// 后台任务返回的操作结果封装。
    private enum RepositoryResult<Value: Sendable>: Sendable {
        case success(Value)
        case failure(SnippetRepository.RepositoryError)
    }

    /// 在后台执行一次仓库变更，成功后清除错误并返回结果。
    private func performMutation<Value: Sendable>(
        _ operation: @escaping @Sendable (SnippetRepository) throws -> Value
    ) async throws -> Value {
        reloadTask?.cancel()
        reloadTask = nil
        generation &+= 1
        let repository = repository

        let result = await Task.detached(priority: .utility) {
            do {
                return RepositoryResult.success(try operation(repository))
            } catch let error as SnippetRepository.RepositoryError {
                return RepositoryResult.failure(error)
            } catch {
                return RepositoryResult.failure(
                    .io(
                        fileURL: repository.snippetsDirectory,
                        message: error.localizedDescription))
            }
        }.value

        switch result {
        case .success(let value):
            operationError = nil
            return value
        case .failure(let error):
            operationError = error.localizedDescription
            throw error
        }
    }

    /// 重新加载快照；过期的世代结果会被丢弃。
    private func reload(showLoadingState: Bool) async {
        guard isStarted else { return }
        generation &+= 1
        let loadGeneration = generation
        if showLoadingState { state = .loading }
        let repository = repository

        let result = await Task.detached(priority: .utility) {
            do {
                return RepositoryResult.success(try repository.load())
            } catch let error as SnippetRepository.RepositoryError {
                return RepositoryResult.failure(error)
            } catch {
                return RepositoryResult.failure(
                    .io(
                        fileURL: repository.snippetsDirectory,
                        message: error.localizedDescription))
            }
        }.value

        guard isStarted, loadGeneration == generation else { return }
        switch result {
        case .success(let snapshot):
            apply(snapshot)
        case .failure(let error):
            state = .failed(error.localizedDescription)
            scheduleWatcherRetry()
        }
    }

    /// 以本地记录直接刷新状态，无需读盘。
    private func publishLocal(records: [StoredSnippet]) {
        apply(
            SnippetRepository.Snapshot(
                records: records.sorted(by: recordOrder),
                issues: issues))
    }

    /// 把快照应用到状态；仅在内容变化时通知 `onSnapshot`。
    private func apply(_ snapshot: SnippetRepository.Snapshot) {
        guard isStarted else { return }
        let isUnchanged =
            state == .ready
            && snippets == snapshot.records
            && issues == snapshot.issues
        if !isUnchanged {
            snippets = snapshot.records
            issues = snapshot.issues
            state = .ready
            onSnapshot?(snapshot)
        }
        if syncWatchers(with: snapshot) {
            scheduleReload(after: .milliseconds(150))
        }
    }

    /// 延迟调度一次重新加载，先取消上一个调度。
    private func scheduleReload(after delay: Duration, showLoadingState: Bool = false) {
        guard isStarted else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if delay != .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard let self, self.isStarted, !Task.isCancelled else { return }
            await self.reload(showLoadingState: showLoadingState)
        }
    }

    /// 按快照同步文件监视器，返回是否有变动。
    private func syncWatchers(with snapshot: SnippetRepository.Snapshot) -> Bool {
        guard isStarted else { return false }
        watcherRetryTask?.cancel()
        watcherRetryTask = nil

        var changed = false
        if directoryWatcher == nil {
            changed = armDirectoryWatcher() || changed
        }

        let desiredPaths = Set(
            snapshot.records.map { $0.fileURL.standardizedFileURL.path }
                + snapshot.issues.map { $0.fileURL.standardizedFileURL.path })
        for path in Array(fileWatchers.keys) where !desiredPaths.contains(path) {
            fileWatchers.removeValue(forKey: path)?.cancel()
            changed = true
        }
        for path in desiredPaths where fileWatchers[path] == nil {
            changed = armFileWatcher(path: path) || changed
        }

        // 只要还有未监视的对象就重试；监视器安装失败与缺失一样会让变更无从感知。
        if directoryWatcher == nil || desiredPaths.contains(where: { fileWatchers[$0] == nil }) {
            scheduleWatcherRetry()
        }
        return changed
    }

    /// 为 snippet 目录安装文件系统事件监视。
    @discardableResult
    private func armDirectoryWatcher() -> Bool {
        let descriptor = Darwin.open(snippetsDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        watcherGeneration &+= 1
        let installedGeneration = watcherGeneration
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleDirectoryEvent(generation: installedGeneration)
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        directoryWatcher = source
        source.resume()
        return true
    }

    /// 为单个文件安装文件系统事件监视。
    @discardableResult
    private func armFileWatcher(path: String) -> Bool {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let installedGeneration = watcherGeneration
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleFileEvent(path: path, generation: installedGeneration)
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        fileWatchers[path] = source
        source.resume()
        return true
    }

    /// 处理目录事件：目录消失时拆除监视，并触发重载。
    private func handleDirectoryEvent(generation installedGeneration: Int) {
        guard isStarted, installedGeneration == watcherGeneration,
            let events = directoryWatcher?.data
        else { return }

        if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
            stopWatchers()
        }
        noteFilesystemChange()
    }

    /// 处理文件事件：文件消失时移除该监视，并触发重载。
    private func handleFileEvent(path: String, generation installedGeneration: Int) {
        guard isStarted, installedGeneration == watcherGeneration,
            let source = fileWatchers[path]
        else { return }

        if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
            fileWatchers.removeValue(forKey: path)?.cancel()
        }
        noteFilesystemChange()
    }

    /// 记录一次文件系统变化并安排延迟重载。
    private func noteFilesystemChange() {
        generation &+= 1
        scheduleReload(after: .milliseconds(150))
    }

    /// 取消并清空全部监视器。
    private func stopWatchers() {
        watcherGeneration &+= 1
        directoryWatcher?.cancel()
        directoryWatcher = nil
        for source in fileWatchers.values { source.cancel() }
        fileWatchers.removeAll()
    }

    /// 1 秒后重试一次加载，用于监视器缺失时恢复。
    private func scheduleWatcherRetry() {
        guard isStarted, watcherRetryTask == nil else { return }
        watcherRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard let self, self.isStarted, !Task.isCancelled else { return }
            self.watcherRetryTask = nil
            await self.reload(showLoadingState: false)
        }
    }

    /// 记录排序：按名称不区分大小写升序，同名再按 ID。
    private func recordOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        let comparison = lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }
}
