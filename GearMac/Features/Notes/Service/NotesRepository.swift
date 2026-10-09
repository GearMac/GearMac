// 文件职责：Notes 功能的文件系统仓库，负责笔记的列出、读取、创建、导入、保存、重命名与移入废纸篓，并把文件系统错误统一映射为 Failure。
// 分层：Service；只依赖 Foundation，不得 import AppKit/SwiftUI，所有文件写入都经 NSFileCoordinator 协调。
import Foundation

/// 笔记仓库：以纯文本 Markdown 文件为存储，所有读写路径都被限制在 `notesDirectory` 之内。
struct NotesRepository: Sendable {
    /// 移入废纸篓操作的注入点，便于测试时替换默认的 FileManager 实现。
    typealias TrashOperation = @Sendable (URL) throws -> Void

    /// 仓库可能抛出的错误，每个分支都带有面向用户的本地化描述。
    enum Failure: Error, LocalizedError, Sendable, Equatable {
        case invalidTitle(String)
        case unreadable(URL)
        case invalidLocation(URL)
        case io(fileURL: URL, message: String)

        /// 各分支对应的用户可见错误描述。
        var errorDescription: String? {
            switch self {
            case .invalidTitle(let title):
                return "“\(title)” can't be used as a note title."
            case .unreadable(let fileURL):
                return "The note isn't valid UTF-8. (\(fileURL.lastPathComponent))"
            case .invalidLocation(let fileURL):
                return "The note file is outside the notes folder. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            }
        }

        /// 按界面语言解析的用户可见错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .invalidTitle(let title):
                return String(format: L10n.string(NotesKey.errorInvalidTitle, language: language), title)
            case .unreadable(let fileURL):
                return String(
                    format: L10n.string(NotesKey.errorNotUTF8, language: language),
                    fileURL.lastPathComponent)
            case .invalidLocation(let fileURL):
                return String(
                    format: L10n.string(NotesKey.errorOutsideFolder, language: language), fileURL.path)
            case .io(let fileURL, let message):
                return String(
                    format: L10n.string(NotesKey.errorAccessFailed, language: language),
                    fileURL.path, message)
            }
        }
    }

    /// 笔记文件所在目录，所有读写都被限制在该目录内。
    let notesDirectory: URL
    private let trashOperation: TrashOperation

    /// 创建仓库；`trashOperation` 默认真实移入废纸篓，注入后可在测试中替换。
    init(
        notesDirectory: URL,
        trashOperation: @escaping TrashOperation = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.notesDirectory = notesDirectory
        self.trashOperation = trashOperation
    }

    /// 列出目录内全部笔记摘要，按修改时间倒序、同一时间按标题排序。
    func list() throws(Failure) -> [NoteSummary] {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let keys: Set<URLResourceKey> = [
                .contentModificationDateKey, .isHiddenKey, .isRegularFileKey,
                .isSymbolicLinkKey
            ]
            return try FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            // 不可读的条目会被跳过：单个坏文件不应让其余笔记消失。
            .compactMap { candidate -> NoteSummary? in
                guard candidate.pathExtension.caseInsensitiveCompare("md") == .orderedSame,
                    let values = try? candidate.resourceValues(forKeys: keys),
                    values.isRegularFile == true, values.isSymbolicLink != true,
                    values.isHidden != true,
                    let url = try? validatedFileURL(candidate)
                else { return nil }
                let title = url.deletingPathExtension().lastPathComponent
                return NoteSummary(
                    id: NoteID(rawValue: url.lastPathComponent),
                    title: title,
                    firstLine: NoteTitle.isUnnamed(title) ? firstLine(of: url) : nil,
                    modifiedAt: values.contentModificationDate ?? .distantPast)
            }
            .sorted(by: summaryPrecedes)
        }
    }

    /// 返回 `nil` 文档表示空集合而非失败：是否新建笔记始终由用户决定。
    func load(preferredID: NoteID?) throws(Failure) -> ([NoteSummary], NoteDocument?) {
        let summaries = try list()
        if let preferredID, summaries.contains(where: { $0.id == preferredID }) {
            return (summaries, try load(preferredID))
        }
        guard let first = summaries.first else { return (summaries, nil) }
        return (summaries, try load(first.id))
    }

    /// 读取指定 id 的笔记文档；文件不是 UTF-8 时抛出 `Failure.unreadable`。
    func load(_ id: NoteID) throws(Failure) -> NoteDocument {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else {
                throw Failure.unreadable(url)
            }
            return NoteDocument(id: NoteID(rawValue: url.lastPathComponent), source: source)
        }
    }

    /// 新建一篇空白笔记，标题冲突时自动追加序号，成功后返回该笔记文档。
    func create(title: String = "Untitled") throws(Failure) -> NoteDocument {
        try mappedError(at: notesDirectory) {
            let url = try claimUniqueURL(base: try validatedTitle(title)) {
                try writeNewFileAtomically(Data(), to: $0)
            }
            return try load(NoteID(rawValue: url.lastPathComponent))
        }
    }

    /// 备份携带的单篇笔记：此时它还没有对应的文件。
    struct Incoming: Sendable, Equatable {
        let title: String
        let source: String
    }

    /// 把导入的笔记写成新文件（只新增、不覆盖已有笔记），返回成功导入的数量；标题不可用时跳过该篇而非整体失败。
    func importNotes(_ notes: [Incoming]) throws(Failure) -> Int {
        try mappedError(at: notesDirectory) {
            var imported = 0
            for note in notes {
                guard let base = try? validatedTitle(note.title) else { continue }
                _ = try claimUniqueURL(base: base) {
                    try writeNewFileAtomically(Data(note.source.utf8), to: $0)
                }
                imported += 1
            }
            return imported
        }
    }

    /// 以原子写入方式把 `source` 保存到指定笔记文件，过程由 NSFileCoordinator 协调。
    func save(id: NoteID, source: String) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = Data(source.utf8)
            try coordinatedWrite(at: url, options: .forReplacing) { coordinatedURL in
                try data.write(to: try validatedFileURL(coordinatedURL), options: .atomic)
            }
        }
    }

    /// 把笔记改名为新标题并返回新的 id；标题未发生变化时直接返回原 id。
    func rename(id: NoteID, title: String) throws(Failure) -> NoteID {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let sourceURL = try validatedFileURL(candidate)
            let base = try validatedTitle(title)
            // 精确比较而非折叠比较：仅改变大小写或重音也是用户明确要求的重命名。
            guard base + ".md" != id.rawValue else { return id }
            let destination = try claimUniqueURL(base: base, renaming: id) { destination in
                try coordinatedWrite(at: sourceURL, options: .forMoving) { coordinatedURL in
                    try FileManager.default.moveItem(
                        at: try validatedFileURL(coordinatedURL), to: destination)
                }
            }
            return NoteID(rawValue: destination.lastPathComponent)
        }
    }

    /// 把指定笔记移入废纸篓。
    func trash(id: NoteID) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            try coordinatedWrite(at: url, options: .forDeleting) { coordinatedURL in
                try trashOperation(try validatedFileURL(coordinatedURL))
            }
        }
    }

    /// 在给定摘要集合中执行搜索，返回最多 `limit` 条按相关度排序的结果。
    func search(
        _ query: NoteSearch.Query,
        summaries: [NoteSummary],
        limit: Int = 200
    ) -> [NoteSearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var results: [NoteSearchResult] = []
        for summary in summaries {
            if Task.isCancelled { break }
            let source = try? load(summary.id).source
            if let result = NoteSearch.match(query: query, summary: summary, source: source) {
                results.append(result)
            }
        }
        return Array(results.sorted(by: NoteSearch.precedes).prefix(limit))
    }

    /// 笔记 id 对应的文件路径。
    func fileURL(for id: NoteID) -> URL {
        notesDirectory.appendingPathComponent(id.rawValue)
    }

    /// 只有未命名笔记才会付出这次读取代价，且只读取文件开头部分。
    private func firstLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: NoteTitle.headByteCount), !head.isEmpty
        else { return nil }
        // 定长读取可能截断在多字节字符中间，因此逐步回退到最后一个完整字符。
        for dropped in 0...3 where head.count > dropped {
            if let text = String(bytes: head.dropLast(dropped), encoding: .utf8) {
                return NoteTitle.firstLine(of: text)
            }
        }
        return nil
    }

    /// 确保笔记目录存在，不存在则递归创建。
    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: notesDirectory, withIntermediateDirectories: true)
    }

    /// 占用第一个空闲的 `<base>.md`、`<base> 2.md`……；并发竞争失败只会让序号继续增长。
    private func claimUniqueURL(
        base: String,
        renaming id: NoteID? = nil,
        _ claim: (URL) throws -> Void
    ) throws -> URL {
        let occupied = Set(try list().lazy.filter { $0.id != id }.map { folded($0.id.rawValue) })
        var suffix = 1
        while true {
            let candidate = uniqueCandidate(base: base, suffix: suffix)
            let name = folded(candidate.lastPathComponent)
            // 仅改大小写的重命名会与自身文件冲突，随后的移动会在原地替换它。
            let isSelf = id.map { name == folded($0.rawValue) } ?? false
            guard !occupied.contains(name),
                isSelf || !FileManager.default.fileExists(atPath: candidate.path)
            else {
                suffix += 1
                continue
            }
            do {
                try claim(candidate)
                return candidate
            } catch {
                guard !isSelf, FileManager.default.fileExists(atPath: candidate.path) else {
                    throw error
                }
                suffix += 1
            }
        }
    }

    /// 校验并标准化文件 URL，确保它位于笔记目录内、扩展名为 md 且不含符号链接绕行。
    private func validatedFileURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let expectedParent = notesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent().path == expectedParent.path,
            standardized.lastPathComponent == candidate.lastPathComponent,
            standardized.pathExtension.caseInsensitiveCompare("md") == .orderedSame
        else { throw Failure.invalidLocation(candidate) }
        return standardized
    }

    /// 校验并规范化用户输入的标题，去掉首尾空白与 `.md` 后缀，并拒绝路径分隔符等非法字符。
    private func validatedTitle(_ raw: String) throws -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasSuffix(".md") { title.removeLast(3) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != ".", title != "..", !title.hasPrefix("."),
            !title.contains("/"), !title.contains("\0")
        else { throw Failure.invalidTitle(raw) }
        return title
    }

    /// 生成带序号的候选文件名；序号为 1 时不追加数字。
    private func uniqueCandidate(base: String, suffix: Int) -> URL {
        let suffixText = suffix == 1 ? "" : " \(suffix)"
        return notesDirectory.appendingPathComponent("\(base)\(suffixText).md")
    }

    /// 摘要排序规则：修改时间新的在前，时间相同则按显示标题不区分大小写升序。
    private func summaryPrecedes(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    /// 按不区分大小写与重音的方式折叠字符串，用于文件名冲突比较。
    private func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 先写入同目录下的临时文件再移动到目标位置，保证新文件写入的原子性；失败时清理临时文件。
    private func writeNewFileAtomically(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// 通过 NSFileCoordinator 协调地执行一次文件变更闭包，并透传协调或变更过程中产生的错误。
    private func coordinatedWrite<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Swift.Error>?
        coordinator.coordinate(
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

    /// 统一错误映射：原样透传 `Failure`，其余错误包装成带文件路径的 `Failure.io`。
    private func mappedError<Value>(
        at fileURL: URL,
        _ operation: () throws -> Value
    ) throws(Failure) -> Value {
        do {
            return try operation()
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }
}
