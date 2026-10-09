// 文件职责：Notes 功能的可观察状态存储，编排仓库的异步读写、自动保存防抖、搜索与文件夹切换，并向外上报 Issue。
// 分层：Service（@MainActor @Observable）；所有阻塞 IO 都通过 detached 抛到主线程外执行。
import Foundation

/// 笔记编辑器的主状态对象：持有摘要列表、当前笔记草稿与搜索状态，并串行化所有仓库操作。
@MainActor
@Observable
final class NotesStore {
    /// 需要向 UI 上报的失败，按发生阶段区分。
    enum Issue: Sendable {
        case load(NotesRepository.Failure)
        case save(NotesRepository.Failure)
        case operation(NotesRepository.Failure)
    }

    /// 对外只读的状态：摘要列表、当前笔记 id、编辑器内容与搜索状态，只能由本类的内部方法写入。
    private(set) var summaries: [NoteSummary] = []
    private(set) var activeID: NoteID?
    private(set) var source = ""
    private(set) var editorEpoch = 0
    private(set) var isDirty = false
    private(set) var isLoaded = false
    private(set) var searchQuery = ""
    private(set) var searchResults: [NoteSearchResult] = []
    private(set) var isSearching = false
    /// 未命名笔记的标题由实时草稿（而非上次列表）推导，因此会随输入实时变化。
    var activeTitle: String {
        guard let activeID else { return "Notes" }
        let title =
            summaries.first(where: { $0.id == activeID })?.title
            ?? URL(fileURLWithPath: activeID.rawValue).deletingPathExtension().lastPathComponent
        guard NoteTitle.isUnnamed(title) else { return title }
        return NoteTitle.firstLine(of: source) ?? title
    }
    /// 当前笔记的文件路径；无当前笔记时为 nil。
    var activeFileURL: URL? { activeID.map(repository.fileURL(for:)) }
    private(set) var notesDirectory: URL
    var onIssue: ((Issue) -> Void)?

    private var repository: NotesRepository
    private let loadSelection: @Sendable () -> NoteID?
    private let saveSelection: @Sendable (NoteID?) -> Void
    @ObservationIgnored private var saveDebounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    private var saveFailed = false
    /// 待处理的文件夹切换：等旧文件夹写不下的草稿保存完成后再执行。
    @ObservationIgnored private var pendingRelocation: NotesRepository?
    private var searchGeneration = 0
    @ObservationIgnored private var sourceRevision = 0

    /// 创建 store；`loadSelection` / `saveSelection` 用于在启动时恢复上次选中的笔记。
    init(
        repository: NotesRepository,
        loadSelection: @escaping @Sendable () -> NoteID? = { nil },
        saveSelection: @escaping @Sendable (NoteID?) -> Void = { _ in }
    ) {
        self.repository = repository
        self.loadSelection = loadSelection
        self.saveSelection = saveSelection
        notesDirectory = repository.notesDirectory
    }

    isolated deinit {
        saveDebounce?.cancel()
        searchTask?.cancel()
        searchWorker?.cancel()
    }

    /// 启动：等待进行中的保存任务结束，然后重新加载列表与文档。
    func start() async -> Bool {
        if let saveTask { await saveTask.value }
        return await reload()
    }

    /// 先把当前草稿保存到原文件夹，再切换到新仓库并重新列出。
    func relocate(to repository: NotesRepository) async {
        pendingRelocation = nil
        guard repository.notesDirectory != notesDirectory else { return }
        guard await flush() else {
            pendingRelocation = repository
            return
        }
        cancelSearch()
        self.repository = repository
        notesDirectory = repository.notesDirectory
        guard isLoaded else { return }
        // 先清空状态，这样新文件夹加载失败时不会残留旧笔记被写入其中。
        apply(nil, summaries: [])
        _ = await reload(preferredID: nil)
    }

    /// 重新加载列表，优先恢复当前选中的笔记（否则使用外部提供的选择）。
    func reload() async -> Bool {
        await reload(preferredID: activeID ?? loadSelection())
    }

    /// 接收编辑器的输入，标脏并安排一次防抖保存。
    func updateSource(_ updated: String) {
        guard activeID != nil, updated != source else { return }
        source = updated
        sourceRevision &+= 1
        isDirty = true
        saveFailed = false
        scheduleSave()
    }

    /// 失败后重试保存，返回是否已保存成功。
    @discardableResult
    func retrySave() async -> Bool {
        saveFailed = false
        return await flush()
    }

    /// 唯一的写入起点，确保防抖保存与 flush 不会在同一文件上重叠。
    @discardableResult
    func flush() async -> Bool {
        saveDebounce?.cancel()
        saveDebounce = nil
        // 两轮：一轮处理已在途的写入，一轮处理其在途期间落地的新编辑。
        for _ in 0..<2 {
            if let saveTask {
                await saveTask.value
                continue
            }
            guard isDirty, !saveFailed else { break }
            let task = Task { [weak self] in
                await self?.write()
                self?.saveTask = nil
            }
            saveTask = task
            await task.value
        }
        return !isDirty
    }

    /// 新建一篇空白笔记并切换到它，返回是否成功。
    @discardableResult
    func create() async -> Bool {
        guard await flush() else { return false }
        cancelSearch()
        let repository = repository
        let result = await detached {
            let document = try repository.create()
            return (document, try repository.list())
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            apply(payload.0, summaries: payload.1)
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    /// 把导入的笔记写成新文件并重新列出，当前打开的草稿保持不动。
    func importNotes(_ notes: [NotesRepository.Incoming]) async -> Int {
        guard !notes.isEmpty else { return 0 }
        let repository = repository
        let result = await detached {
            (try repository.importNotes(notes), try repository.list())
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return 0
        }
    }

    /// 切换到指定笔记；`permitsApply` 在异步读取返回后再次判断结果是否仍可应用。
    @discardableResult
    func select(
        _ id: NoteID,
        permitsApply: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard id != activeID else { return true }
        guard await flush() else { return false }
        guard permitsApply() else { return false }
        cancelSearch()
        let repository = repository
        let result = await detached {
            try repository.load(id)
        } recover: {
            repository.fileURL(for: id)
        }
        guard permitsApply(), !Task.isCancelled else { return false }
        switch result {
        case .success(let document):
            apply(document, summaries: summaries)
            return true
        case .failure(let failure):
            publish(.load(failure))
            return false
        }
    }

    /// 重命名笔记；若重命名的是当前笔记，则同步更新选中状态。
    @discardableResult
    func rename(_ id: NoteID, to title: String) async -> NoteID? {
        guard await flush() else { return nil }
        cancelSearch()
        let repository = repository
        let result = await detached {
            let renamed = try repository.rename(id: id, title: title)
            return (renamed, try repository.list())
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            if id == activeID {
                activeID = payload.0
                saveSelection(payload.0)
            }
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return nil
        }
    }

    /// 把指定笔记移入废纸篓；若它是当前笔记，则自动切到列表中的下一篇。
    @discardableResult
    func trash(_ id: NoteID) async -> Bool {
        guard await flush() else { return false }
        let repository = repository
        let replacesActive = id == activeID
        let result = await detached {
            try repository.trash(id: id)
            let summaries = try repository.list()
            let successor = replacesActive ? summaries.first : nil
            return (try successor.map { try repository.load($0.id) }, summaries)
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            cancelSearch()
            // 空集合是合法的静止状态；只有新建才会重新产生笔记。
            if replacesActive {
                apply(payload.0, summaries: payload.1)
            } else {
                summaries = payload.1
            }
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    /// 接收搜索输入，经短暂防抖后在后台线程执行搜索；空查询直接清空结果。
    func updateSearchQuery(_ updated: String) {
        searchQuery = updated
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = NoteSearch.Query(updated)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            searchTask = nil
            searchWorker = nil
            return
        }
        isSearching = true
        // 上一查询的结果不得滞留在新的查询文本下。
        searchResults = []
        let repository = repository
        let summaries = summaries
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                Signposts.interval("Notes.search") {
                    repository.search(query, summaries: summaries)
                }
            }
            self.searchWorker = worker
            let results = await worker.value
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.searchResults = results
            self.isSearching = false
            self.searchWorker = nil
            self.searchTask = nil
        }
    }

    /// 取消进行中的搜索任务并清空搜索状态。
    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchWorker?.cancel()
        searchWorker = nil
        searchGeneration &+= 1
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    /// 停止 store：取消防抖保存与搜索，但不会取消进行中的写入；所有调用方都会先 flush。
    func stop() {
        saveDebounce?.cancel()
        saveDebounce = nil
        cancelSearch()
    }

    /// 重新加载列表（必要时含文档），并通过多个快照字段确保结果不会被期间发生的编辑或切换覆盖。
    private func reload(preferredID: NoteID?) async -> Bool {
        let repository = repository
        let selectedID = activeID
        let epoch = editorEpoch
        let revision = sourceRevision
        let reloadSource = !isDirty
        let result = await detached {
            if reloadSource { return try repository.load(preferredID: preferredID) }
            return (try repository.list(), nil)
        } recover: {
            repository.notesDirectory
        }
        guard !Task.isCancelled else { return false }
        guard repository.notesDirectory == notesDirectory, selectedID == activeID,
            epoch == editorEpoch, revision == sourceRevision
        else { return true }
        switch result {
        case .success(let (summaries, document)):
            if reloadSource, !isDirty, saveTask == nil,
                !isLoaded || document?.id != activeID || (document?.source ?? "") != source
            {
                apply(document, summaries: summaries)
            } else {
                self.summaries = summaries
            }
            return true
        case .failure(let failure):
            publish(.load(failure))
            // 只有首次加载失败才让窗口保持关闭；已加载过的 store 仍可展示其草稿。
            return isLoaded
        }
    }

    /// 安排一次延迟保存：每次调用重置计时器，静默 300ms 后执行 flush。
    private func scheduleSave() {
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil, let self else { return }
            saveDebounce = nil
            await flush()
        }
    }

    /// 在后台执行一次真实写入，并在成功后刷新摘要列表；若期间草稿又有变化则保持脏状态。
    private func write() async {
        guard isDirty, let activeID else { return }
        let savedSource = source
        let repository = repository
        let result = await detached {
            try repository.save(id: activeID, source: savedSource)
            return try repository.list()
        } recover: {
            repository.fileURL(for: activeID)
        }
        switch result {
        case .success(let summaries):
            self.summaries = summaries
            isDirty = savedSource != source
            if !isDirty, let pending = pendingRelocation {
                Task { [weak self] in await self?.relocate(to: pending) }
            }
        case .failure(let failure):
            saveFailed = true
            publish(.save(failure))
        }
    }

    /// 应用一份新文档：刷新摘要、当前 id 与编辑器内容，递增编辑器代次并清除脏标记。
    private func apply(_ document: NoteDocument?, summaries: [NoteSummary]) {
        self.summaries = summaries
        activeID = document?.id
        source = document?.source ?? ""
        editorEpoch &+= 1
        isDirty = false
        saveFailed = false
        isLoaded = true
        saveSelection(document?.id)
    }

    /// 把失败上报给 `onIssue` 回调。
    private func publish(_ issue: Issue) {
        onIssue?(issue)
    }

    /// 每次仓库调用都是阻塞 IO，因此放到主线程外执行，并统一返回一个带类型的失败。
    private func detached<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value,
        recover fileURL: @escaping @Sendable () -> URL
    ) async -> Result<Value, NotesRepository.Failure> {
        await Task.detached(priority: .utility) {
            do {
                return .success(try work())
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(.io(fileURL: fileURL(), message: error.localizedDescription))
            }
        }.value
    }
}
