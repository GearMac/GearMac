// 文件职责：基于 SQLite 的剪贴板历史存储，负责条目模型、保留策略、FTS 搜索与图片 blob 管理。
// 分层：Model（存储层）；@MainActor 串行化内存窗口，磁盘 I/O 与 FTS 查询保持在非主线程。
import Foundation
import SQLite3

// 与 sqlite3.h 中的 C 宏写法一致，该宏没有被导入到 Swift。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 一条剪贴板历史条目：文本、图片或文件引用。
struct ClipboardItem: Identifiable, Hashable, Sendable {
    /// 条目的存储种类。
    enum Kind: String, Sendable { case text, image, file }

    let id: UUID
    let kind: Kind
    /// 复制的文本；对 `.file` 条目则是绝对路径——FTS 索引的正是它。
    let text: String?
    /// 磁盘上的绝对路径；只有 `imagesDir` 下的文件才归我们负责删除。
    let imagePath: String?
    let createdAt: Date
    /// 捕获这次复制时前台 App 的 Bundle ID（参见 `ClipboardManager.poll`）。
    let sourceBundleID: String?
    /// 条目被固定的时间；固定项排在列表最前，且不参与清理。
    let pinnedAt: Date?
    /// 用户为条目打的标签；由右键「打标签」写入，随备份携带。
    let tag: String?

    var isPinned: Bool { pinnedAt != nil }

    /// 被引用的路径；有了它，调用方无需再从 `text` 反推文件条目的含义。
    var filePath: String? { kind == .file ? text : nil }

    /// 「粘贴为纯文本」写入的内容：文本本身，或以文件路径代替文件。
    var plainText: String? { kind == .image ? nil : text }

    /// 「复制文本」(⇧⌘T) 是否适用：截获的图片，或在 Finder 中复制的图片文件。
    var offersTextExtraction: Bool {
        switch kind {
        case .image: return imagePath != nil
        case .file: return filePath.map { ClipboardFileKind.of(path: $0) == .image } ?? false
        case .text: return false
        }
    }

    /// 构造一条文本条目，id 与创建时间由内部生成。
    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    /// 构造一条图片条目，指向已写入磁盘的图片。
    init(imagePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID)
    }

    /// 就她引用：`imagePath` 保持 nil，避免 `deleteBlob` 删掉不属于我们的文件。
    init(filePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .file, text: filePath, imagePath: nil, createdAt: createdAt,
            sourceBundleID: sourceBundleID)
    }

    /// 全字段初始化器，供存储层回读与导入使用。
    init(
        id: UUID, kind: Kind, text: String?, imagePath: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date? = nil, tag: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
        self.tag = tag
    }

    /// 复制并替换存储层会改写的两个字段；pin 始终显式给出。
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt, tag: tag)
    }

    /// 打标签的专用副本：标签为 nil 即清除，因此不能与旧值合并。
    func with(tag: String?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID, pinnedAt: pinnedAt, tag: tag)
    }

    /// 大小写不敏感的子串匹配：存储层在没有 FTS 时的筛选方式。
    func matches(_ query: String) -> Bool {
        text?.localizedCaseInsensitiveContains(query) ?? false
    }
}

/// 保留天数；`forever` 为 -1，因此未设置的键（0）会落到默认值。
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    /// 按界面语言给出的保留时长标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .day: .retentionDay
            case .week: .retentionWeek
            case .month: .retentionMonth
            case .threeMonths: .retentionThreeMonths
            case .sixMonths: .retentionSixMonths
            case .year: .retentionYear
            case .forever: .retentionForever
            }
        return L10n.string(key, language: language)
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// ↵ 在剪贴板条目上执行的动作；Paste 会占用所选动作空出的快捷键。
enum ClipboardDefaultAction: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copy
    case pastePlainText

    var id: String { rawValue }

    /// 按界面语言给出的动作名。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .paste: .defaultActionPaste
            case .copy: .defaultActionCopy
            case .pastePlainText: .defaultActionPastePlainText
            }
        return L10n.string(key, language: language)
    }

    /// 在以此项为默认动作时，`chord` 对 `item` 实际执行的动作；无可粘贴文本时返回 nil。
    func action(for chord: ClipboardChord, on item: ClipboardItem) -> Self? {
        let hasPlainText = item.plainText != nil
        // 图片没有文本，因此以纯文本为默认时会按原样粘贴它。
        let resolved: Self = self == .pastePlainText && !hasPlainText ? .paste : self
        let action: Self =
            switch chord {
            case .return: resolved
            case resolved.ownChord: .paste
            case .command: .copy
            case .controlCommand: .pastePlainText
            }
        return action == .pastePlainText && !hasPlainText ? nil : action
    }

    /// 在 Paste 为默认动作时，各动作所对应的 ↵ 快捷键。
    private var ownChord: ClipboardChord {
        switch self {
        case .paste: .return
        case .copy: .command
        case .pastePlainText: .controlCommand
        }
    }
}

/// 会因默认动作而重新排序的 ↵ 快捷键组合；⌥↵ 始终为粘贴，故不在此列。
enum ClipboardChord: CaseIterable, Sendable {
    case `return`
    case command
    case controlCommand

    var label: String {
        switch self {
        case .return: "↵"
        case .command: "⌘↵"
        case .controlCommand: "⌃⌘↵"
        }
    }
}

/// 基于 SQLite 的剪贴板历史。参见 docs/features/clipboard.md#store。
@MainActor
@Observable
final class ClipboardStore {
    /// 最新在前、固定项保持原位，且所有固定项常驻内存。docs/features/clipboard.md
    private(set) var items: [ClipboardItem] = [] {
        didSet {
            if !textSearchMatches.isEmpty {
                let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                textSearchMatches = textSearchMatches.map { current[$0.id] ?? $0 }
            }
            invalidateSearch(preservingMatches: true)
            onItemsChanged?()
        }
    }
    @ObservationIgnored var onItemsChanged: (() -> Void)?
    @ObservationIgnored var onSearchResultsChanged: ((String, [ClipboardItem], [ClipboardItem]) -> Void)?
    /// 用户创建的标签，按名称排序；随历史一起加载。
    private(set) var tags: [ClipTag] = []
    /// 历史被整体替换时轮换，使辅助任务迟到的结果落空。
    @ObservationIgnored private(set) var extractionGeneration = UUID()
    /// 视图判断搜索结果新鲜度的唯一依据；`items` 无法反映 OCR 侧的变化。
    private var searchRevision = 0
    @ObservationIgnored private(set) var textSearchEnabled = false
    @ObservationIgnored private var textSearchActive = true
    @ObservationIgnored private var textSearchTask: Task<Void, Never>?
    @ObservationIgnored private var textSearchNeedsRefresh = false
    @ObservationIgnored private var textSearchQuery: String?
    @ObservationIgnored private var textSearchFilter: ClipboardFilter?
    @ObservationIgnored private var textSearchRequest: UUID?
    @ObservationIgnored private var textSearchMatches: [ClipboardItem] = []

    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// 单条缓存，使重复渲染复用 FTS 结果；`items` 变化时清空。
    @ObservationIgnored private var searchCache:
        (query: String, filter: ClipboardFilter, result: [ClipboardItem])?
    /// 空查询用的同类缓存，使固定项拆分每次变更只执行一次。
    @ObservationIgnored private var orderedCache: [ClipboardItem]?

    nonisolated private static let memoryWindow = 1000
    /// 单次查询最多返回的未固定行数，普通结果与仅 OCR 结果共同受限。
    nonisolated private static let searchLimit = 200

    nonisolated private static let insertSQL = """
        INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at, tag)
        VALUES(?,?,?,?,?,?,?,?)
        """

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned_at REAL,
          tag TEXT
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL;
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF rowid, text ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TABLE IF NOT EXISTS tags(
          name TEXT NOT NULL UNIQUE,
          color TEXT NOT NULL
        );
        """

    private static let extractionSchema = """
        CREATE TABLE IF NOT EXISTS item_text(
          item_id TEXT NOT NULL UNIQUE, text TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS item_text_fts USING fts5(
          text, content='item_text', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS item_text_ai AFTER INSERT ON item_text BEGIN
          INSERT INTO item_text_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS item_text_ad AFTER DELETE ON item_text BEGIN
          INSERT INTO item_text_fts(item_text_fts, rowid, text)
            VALUES('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_extract_ad AFTER DELETE ON items BEGIN
          DELETE FROM item_text WHERE item_id = old.id;
        END;
        CREATE TABLE IF NOT EXISTS item_text_failures(
          item_id TEXT NOT NULL UNIQUE, attempts INTEGER NOT NULL, retry_at REAL NOT NULL
        );
        CREATE TRIGGER IF NOT EXISTS items_extract_failure_ad AFTER DELETE ON items BEGIN
          DELETE FROM item_text_failures WHERE item_id = old.id;
        END;
        CREATE INDEX IF NOT EXISTS items_extract_candidates ON items(kind)
          WHERE kind IN ('image', 'file');
        """

    /// 为 internal 而非 private：备份功能需要引用二者来流式导出表并接管其 blob。
    let imagesDir: URL
    let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var insertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var windowFloorStmt: OpaquePointer?
    @ObservationIgnored private var searchStmt: OpaquePointer?
    @ObservationIgnored private var deleteByIDStmt: OpaquePointer?
    @ObservationIgnored private var pinStmt: OpaquePointer?
    @ObservationIgnored private var tagStmt: OpaquePointer?
    @ObservationIgnored private var staleImagesStmt: OpaquePointer?
    @ObservationIgnored private var deleteStaleStmt: OpaquePointer?

    /// `directory` 默认为分渠道存储目录；测试夹具会传入一个临时目录。
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        open()
    }

    /// 幂等，因此功能重新开启时 Coordinator 可以再次打开该文件。
    func open() {
        guard db == nil else { return }
        if openDatabase() { return }
        // 属于可丢弃的采集数据而非用户创作：损坏或过期的数据库直接丢弃重建。
        closeDatabase()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
        }
        if !openDatabase() { closeDatabase() }
    }

    /// 每个访问入口都做了语句级保护，因此已关闭的存储会表现为空历史。
    func close() {
        setTextSearchEnabled(false)
        extractionGeneration = UUID()
        closeDatabase()
        items = []
    }

    /// 使用 Application Support 而非 Caches：可能被系统回收的历史不算真正的历史。
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // 标记为 isolated，使析构时仍可触及主 actor 指针；释放本身已经发生在主线程。
    isolated deinit {
        textSearchTask?.cancel()
        closeDatabase()
    }

    /// 从数据库重新加载内存窗口内的条目，并执行一次保留期清理。
    func load() {
        invalidateSearch()
        extractionGeneration = UUID()
        loadTags()
        guard let stmt = loadStmt else { return }
        sqlite3_bind_int64(stmt, 1, windowFloor())
        var loaded: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(item) }
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        items = loaded
        // App 未运行期间时间仍在流逝；仅靠插入时清理无法覆盖这种情况。
        enforceLimits()
    }

    /// 在加载时以及保留期设置变化时调用。
    func enforceLimits() {
        prune()
    }

    /// `loadStmt` 读取的 rowid 下界；0 表示无下界，即加载全部。
    private func windowFloor() -> sqlite3_int64 {
        guard let stmt = windowFloorStmt else { return 0 }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    /// 记录一份文本复制；与最新条目完全相同时也忽略。
    func addText(_ text: String, sourceBundleID: String?) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    /// 每个文件一行。批量处理，使多文件复制只清理一次，而不是每个文件一次。
    func addFiles(_ paths: [String], sourceBundleID: String?) {
        // 只有单个文件才可能是 ⌘C 的重复，这也正是 `addText` 所防护的情况。
        if paths.count == 1, items.first?.kind == .file, items.first?.text == paths[0] { return }
        for path in paths {
            let item = ClipboardItem(filePath: path, sourceBundleID: sourceBundleID)
            if let stmt = insertStmt { Self.bindAndInsert(stmt, item) }
            items.insert(item, at: 0)
        }
        trimWindow()
        prune()
    }

    /// 把图片数据写入 images 目录并插入一条图片条目（磁盘写入在后台执行）。
    func addImage(_ data: Data, sourceBundleID: String?) {
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // blob 写入是数 MB 级别的 I/O；只有行插入回到主 actor。
        Task.detached(priority: .utility) { [weak self] in
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            await self?.insert(item)
        }
    }

    /// 从导入批量插入：保留原始时间戳、外部图片路径，并去重。
    @discardableResult
    func importEntries(_ entries: [ClipboardItem]) -> Int {
        // 由旧到新，使最新条目获得最大 rowid（加载按 rowid DESC 排序）。
        let inserted = Self.importStoredItems(
            inDatabaseAt: dbURL, entries.sorted { $0.createdAt < $1.createdAt })
        load()
        return inserted
    }

    /// 把条目移到最前；在面板中粘贴或复制它会使其重新成为最新。
    func promote(_ item: ClipboardItem) {
        // 固定行保持原位，重新置最新只会产生一次无意义的写入。
        guard !item.isPinned, items.first?.id != item.id else { return }
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// 切换条目的固定状态。
    func togglePinned(_ item: ClipboardItem) {
        if item.isPinned { unpin(item) } else { pin(item) }
    }

    /// 打标签：空文本即清除；标签只改写这一列，不动时间与顺序。
    func setTag(_ tag: String?, for item: ClipboardItem) {
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = trimmed?.isEmpty == true ? nil : trimmed
        guard tag != item.tag else { return }
        if let stmt = tagStmt {
            if let tag {
                sqlite3_bind_text(stmt, 1, tag, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item.with(tag: tag)
        }
    }

    /// 新建标签；名称为主键，重名创建只更新颜色。
    func createTag(name: String, colorHex: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let db else { return }
        var stmt: OpaquePointer?
        let sql =
            "INSERT INTO tags(name, color) VALUES(?, ?) ON CONFLICT(name) DO UPDATE SET color = excluded.color"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, colorHex, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        loadTags()
    }

    /// 按名称查找标签；条目上的 `tag` 存的正是名称。
    func tag(named name: String?) -> ClipTag? {
        guard let name else { return nil }
        return tags.first { $0.name == name }
    }

    private func loadTags() {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT name, color FROM tags ORDER BY name", -1, &stmt, nil)
                == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        var loaded: [ClipTag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = Self.columnString(stmt, 0), let color = Self.columnString(stmt, 1) {
                loaded.append(ClipTag(name: name, colorHex: color))
            }
        }
        tags = loaded
    }

    /// 删除单个条目：从数据库与内存中移除，并删除归我们所有的图片文件。
    func remove(_ item: ClipboardItem) {
        textSearchMatches.removeAll { $0.id == item.id }
        if let stmt = deleteByIDStmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    /// 固定是有意的保留，因此能绕过批量清空；要删掉固定项需使用 `remove`。
    func clearAll() {
        invalidateSearch()
        extractionGeneration = UUID()
        // RETURNING 在同一次操作中返回被删除的 blob，因此无需单独的 SELECT。
        if db != nil,
            let stmt = prepare("DELETE FROM items WHERE pinned_at IS NULL RETURNING image_path")
        {
            var orphaned: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let path = Self.columnString(stmt, 0), owns(path) { orphaned.append(path) }
            }
            sqlite3_finalize(stmt)
            if !orphaned.isEmpty {
                Task.detached(priority: .utility) {
                    for path in orphaned { try? FileManager.default.removeItem(atPath: path) }
                }
            }
        }
        // 所有固定行无论多旧都常驻内存，因此无需重载即可保持窗口完整。
        items = items.filter(\.isPinned)
    }

    /// 开启或关闭 OCR 文本搜索；开启时建表并清理失败记录，返回是否成功。
    @discardableResult
    func setTextSearchEnabled(_ enabled: Bool) -> Bool {
        guard enabled != textSearchEnabled else { return true }
        if enabled {
            guard let db, sqlite3_exec(db, Self.extractionSchema, nil, nil, nil) == SQLITE_OK else {
                return false
            }
            sqlite3_exec(db, "DELETE FROM item_text_failures", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM item_text WHERE text = ''", nil, nil, nil)
        }
        textSearchEnabled = enabled
        extractionGeneration = UUID()
        invalidateSearch()
        searchRevision += 1
        return true
    }

    /// 取出下一个待 OCR 提取的图片/文件条目；没有时返回 nil。
    func nextExtractionItem(now: Date = Date()) -> ClipboardItem? {
        guard textSearchEnabled else { return nil }
        guard
            let stmt = prepare(
                """
                SELECT id, kind, text, image_path, created_at, source_app, pinned_at
                FROM items WHERE kind IN ('image', 'file')
                  AND id NOT IN (SELECT item_id FROM item_text)
                  AND id NOT IN (SELECT item_id FROM item_text_failures
                    WHERE attempts >= 3 OR retry_at > ?1)
                ORDER BY rowid DESC LIMIT 1
                """)
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_ROW ? Self.row(stmt) : nil
    }

    /// 最近一次可供重试的失败提取时间；无待重试项时为 nil。
    var nextExtractionRetry: Date? {
        guard textSearchEnabled,
            let stmt = prepare(
                "SELECT MIN(retry_at) FROM item_text_failures WHERE attempts < 3")
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
    }

    /// 记录一次 OCR 提取失败，并安排重试时间。
    func recordExtractionFailure(for item: ClipboardItem, generation: UUID, retryAt: Date) {
        guard textSearchEnabled, generation == extractionGeneration,
            let stmt = prepare(
                """
                INSERT INTO item_text_failures(item_id, attempts, retry_at)
                SELECT id, 1, ?2 FROM items WHERE id = ?1
                ON CONFLICT(item_id) DO UPDATE SET attempts = attempts + 1, retry_at = excluded.retry_at
                """)
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, retryAt.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// 以查询选中该行而非直接指名，使识别过程中被删除的条目保持删除状态。
    @discardableResult
    func setExtractedText(_ text: String, for item: ClipboardItem, generation: UUID) -> Bool {
        guard textSearchEnabled, generation == extractionGeneration,
            let stmt = prepare(
                """
                INSERT OR IGNORE INTO item_text(item_id, text)
                SELECT id, ?2 FROM items WHERE id = ?1 AND kind IN ('image', 'file')
                """)
        else { return false }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
        let stored = sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
        sqlite3_finalize(stmt)
        guard stored else { return false }
        if let stmt = prepare("DELETE FROM item_text_failures WHERE item_id = ?1") {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        invalidateSearch(preservingMatches: true)
        searchRevision += 1
        return true
    }

    /// 图片条目对应的磁盘 URL；非图片条目为 nil。
    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return URL(filePath: path, directoryHint: .inferFromPath)
    }

    /// 文件条目对应的磁盘 URL；非文件条目为 nil。
    func fileURL(for item: ClipboardItem) -> URL? {
        guard let path = item.filePath else { return nil }
        return URL(filePath: path, directoryHint: .inferFromPath)
    }

    /// `query` 在 `filter` 下的展示顺序：固定项在前，每个区块内部最新在前。
    func search(_ query: String, filter: ClipboardFilter) -> [ClipboardItem] {
        // 关键副作用：OCR 查询完成并稳定后答案会变，而此时 `items` 并未变化。
        _ = searchRevision
        let q = query.trimmingCharacters(in: .whitespaces)
        updateTextSearch(q, filter: filter)
        // 筛选器也是缓存键的一部分：`rows` 每次渲染都重建，只用查询做键会让缓存失效。
        if let searchCache, searchCache.query == q, searchCache.filter == filter {
            return searchCache.result
        }
        // 先拆分后筛选，可让命中的固定项仍按固定顺序留在 Pinned 区。
        let result = filter.apply(to: unfiltered(q, filter: filter))
        searchCache = (q, filter, result)
        return result
    }

    /// `item` 在当前列表中的行号，使面板能跟随移动过的行。
    func rowIndex(of item: ClipboardItem, in query: String, filter: ClipboardFilter) -> Int? {
        search(query, filter: filter).firstIndex { $0.id == item.id }
    }

    /// `query` 与 `filter` 下第 N 个可见固定项，0 表示第一个固定行。
    func pinnedItem(at index: Int, in query: String, filter: ClipboardFilter) -> ClipboardItem? {
        guard index >= 0 else { return nil }
        return search(query, filter: filter).prefix(while: \.isPinned).dropFirst(index).first
    }

    /// 重置后光标落点：越过固定项落到最新条目；一旦输入则落在首个匹配项。
    func landingIndex(in query: String, filter: ClipboardFilter) -> Int {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        return search(query, filter: filter).firstIndex { !$0.isPinned } ?? 0
    }

    /// 合并内存窗口内的匹配与 OCR 摘录结果，并保持固定项在前的顺序。
    private func unfiltered(_ q: String, filter: ClipboardFilter) -> [ClipboardItem] {
        guard !q.isEmpty else { return orderedItems }
        // 固定项在内存中匹配：它们全部常驻，否则 LIMIT 可能漏掉一个。
        let ordinary = pinnedItems.filter { $0.matches(q) } + runSearch(q).filter { !$0.isPinned }
        guard !textSearchMatches.isEmpty else { return ordinary }
        let ordinaryIDs = Set(ordinary.map(\.id))
        let additional = textSearchMatches.filter { !ordinaryIDs.contains($0.id) }
        let pins = (ordinary + additional).filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
        let unpinned = ordinary.filter { !$0.isPinned }
        // 仅 OCR 命中的行填补 FTS `LIMIT` 给普通结果之后剩余的额度。
        let remaining = max(0, Self.searchLimit - filter.apply(to: unpinned).count)
        // 显式写出 `Array(…)`：若不写，`prefix` 会解析为 `Sequence` 而使链式调用失败。
        let extra = Array(filter.apply(to: additional.filter { !$0.isPinned }).prefix(remaining))
        return pins + unpinned + extra
    }

    /// 在 FTS 中执行查询；FTS 不可用或查询太短时退回内存筛选。
    private func runSearch(_ q: String) -> [ClipboardItem] {
        // trigram FTS 需要至少 3 个字符；更短的查询改为在内存窗口内筛选。
        guard let stmt = searchStmt, q.count >= 3 else { return fallbackSearch(q) }
        let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        var results: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { results.append(item) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        return status == SQLITE_DONE ? results : fallbackSearch(q)
    }

    /// 清空搜索缓存与在途的 OCR 查询；按需保留已有匹配结果供下一次刷新合并。
    private func invalidateSearch(preservingMatches: Bool = false) {
        searchCache = nil
        orderedCache = nil
        textSearchTask?.cancel()
        textSearchTask = nil
        textSearchRequest = nil
        textSearchNeedsRefresh = preservingMatches && textSearchQuery != nil
        if !preservingMatches {
            textSearchQuery = nil
            textSearchFilter = nil
            textSearchMatches = []
        }
    }

    /// 启用或停用 OCR 搜索参与结果合并。
    func setTextSearchActive(_ active: Bool) {
        guard textSearchActive != active else { return }
        textSearchActive = active
        guard textSearchEnabled else { return }
        invalidateSearch()
        searchRevision += 1
    }

    /// 在查询或筛选变化时，向后台发起一次 OCR 摘录文本搜索并合并结果。
    private func updateTextSearch(_ query: String, filter: ClipboardFilter) {
        guard textSearchEnabled, textSearchActive, !query.isEmpty,
            filter == .all || filter == .image || filter == .file
        else {
            if textSearchQuery != nil { invalidateSearch() }
            return
        }
        guard textSearchQuery != query || textSearchFilter != filter || textSearchNeedsRefresh else { return }
        invalidateSearch(preservingMatches: textSearchQuery == query && textSearchFilter == filter)
        textSearchNeedsRefresh = false
        textSearchQuery = query
        textSearchFilter = filter
        let request = UUID()
        textSearchRequest = request
        let url = dbURL
        let residentIDs = query.count < 3 ? Set(items.map(\.id)) : nil
        textSearchTask = Task(priority: .userInitiated) { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                Self.extractedMatches(in: url, query: query, filter: filter, residentIDs: residentIDs)
            }
            let matches = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.textSearchRequest == request else { return }
            let previous = self.searchCache
            self.textSearchMatches = matches
            self.textSearchTask = nil
            self.searchCache = nil
            self.searchRevision += 1
            if let previous, previous.query == query {
                let current = self.search(query, filter: previous.filter)
                self.onSearchResultsChanged?(query, previous.result, current)
            }
        }
    }

    /// 在后台数据库连接上按 `query` 与 `filter` 匹配 OCR 摘录文本，供主 actor 合并进搜索结果。
    nonisolated private static func extractedMatches(
        in url: URL, query: String, filter: ClipboardFilter, residentIDs: Set<UUID>?
    ) -> [ClipboardItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return []
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_exec(db, "PRAGMA cache_size=-2048", nil, nil, nil)
        sqlite3_progress_handler(db, 1000, { _ in Task.isCancelled ? 1 : 0 }, nil)
        let isShort = query.count < 3
        let kind = filter == .image ? "i.kind = 'image'" : filter == .file ? "i.kind = 'file'" : "1"
        let columns = "i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at"
        let sql =
            isShort
            ? """
            SELECT \(columns), t.text FROM item_text t JOIN items i ON i.id = t.item_id
            WHERE \(kind) AND (i.pinned_at IS NOT NULL OR i.rowid >= COALESCE(
              (SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET \(memoryWindow - 1)), 0))
            ORDER BY i.pinned_at IS NULL, i.pinned_at, i.rowid DESC
            """
            : """
            SELECT * FROM (
              SELECT \(columns), NULL AS recognized, i.rowid AS rid FROM items i
                WHERE i.pinned_at IS NULL AND i.rowid IN (
                SELECT i.rowid FROM item_text_fts f
                  JOIN item_text t ON t.rowid = f.rowid JOIN items i ON i.id = t.item_id
                WHERE item_text_fts MATCH ?1 AND \(kind)
                ORDER BY i.rowid DESC
                LIMIT \(searchLimit) + (SELECT COUNT(*) FROM items WHERE pinned_at IS NOT NULL)
              )
              UNION ALL
              SELECT \(columns), t.text AS recognized, i.rowid AS rid
                FROM items i JOIN item_text t ON t.item_id = i.id
                WHERE i.pinned_at IS NOT NULL AND \(kind)
            ) ORDER BY pinned_at IS NULL, pinned_at, rid DESC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if !isShort {
            let match = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        }
        var matches: [ClipboardItem] = []
        var unpinned = 0
        while !Task.isCancelled, sqlite3_step(stmt) == SQLITE_ROW {
            guard let item = row(stmt) else { continue }
            if let residentIDs, !residentIDs.contains(item.id) { continue }
            if isShort || item.isPinned,
                columnString(stmt, 7)?.localizedCaseInsensitiveContains(query) != true
            {
                continue
            }
            matches.append(item)
            if !item.isPinned { unpinned += 1 }
            if unpinned == searchLimit { break }
        }
        return Task.isCancelled ? [] : matches
    }

    // MARK: - Private

    /// 在内存窗口内做子串匹配的兜底搜索。
    private func fallbackSearch(_ q: String) -> [ClipboardItem] {
        items.filter { $0.matches(q) }
    }

    /// 空查询下的展示顺序：固定项在前，其余保持原有顺序。
    private var orderedItems: [ClipboardItem] {
        if let orderedCache { return orderedCache }
        let pinned = pinnedItems
        // 未固定历史直接按 `items` 原样渲染，因此不会为分区付出代价。
        let result = pinned.isEmpty ? items : pinned + items.filter { !$0.isPinned }
        orderedCache = result
        return result
    }

    /// Pinned 区按固定时间排序，使新增的固定项加入末尾而非开头。
    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
    }

    /// 该行保持原位并获得一个固定时间戳，从而排在 Pinned 区最前。
    private func pin(_ item: ClipboardItem) {
        let stamp = Date()
        let current = items.first { $0.id == item.id } ?? item
        let pinned = current.with(pinnedAt: stamp)
        if let stmt = pinStmt {
            sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // 该行来自内存窗口之外的 FTS 命中，因此按时间顺序插回列表。
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
    }

    /// 取消固定后作为最新条目重新加入。参见 docs/features/clipboard.md#pinned-entries。
    private func unpin(_ item: ClipboardItem) {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// 在同一 id 下改写该行使其置顶；若用删除则会连带删掉其派生的 OCR 文本。
    private func reinsert(_ updated: ClipboardItem) {
        if let stmt = prepare(
            """
            UPDATE items SET rowid = (SELECT COALESCE(MAX(rowid), 0) + 1 FROM items),
              created_at = ?1, pinned_at = ?2 WHERE id = ?3
            """)
        {
            sqlite3_bind_double(stmt, 1, updated.createdAt.timeIntervalSince1970)
            if let stamp = updated.pinnedAt {
                sqlite3_bind_double(stmt, 2, stamp.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, updated.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        // 数组操作同时覆盖了 FTS 从内存窗口之外取出的条目。
        items.removeAll { $0.id == updated.id }
        items.insert(updated, at: 0)
        trimWindow()
    }

    /// 限制内存窗口大小，但绝不丢弃固定行：它们无论多旧都要继续渲染。
    private func trimWindow() {
        guard items.count > Self.memoryWindow, let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    /// 插入一条新条目：写入数据库、加入内存窗口顶部，并执行窗口修剪与保留期清理。
    private func insert(_ item: ClipboardItem) {
        if let stmt = insertStmt { Self.bindAndInsert(stmt, item) }
        items.insert(item, at: 0)
        trimWindow()
        prune()
    }

    /// 把条目按参数顺序绑定到 insert 语句并执行，然后重置语句以便复用。
    nonisolated private static func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) {
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        if let text = item.text {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        if let source = item.sourceBundleID {
            sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        if let tag = item.tag {
            sqlite3_bind_text(stmt, 8, tag, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    /// 路径是否位于我们的 images 目录内；只有这些文件才由我们删除。
    private func owns(_ path: String) -> Bool {
        path.hasPrefix(imagesDir.path + "/")
    }

    /// 按保留期清理过期条目与归我们所有的图片文件。
    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        textSearchMatches.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        if let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            var staleOwnedPaths: [String] = []
            while sqlite3_step(imagesStmt) == SQLITE_ROW {
                // 只删除属于我们的文件；外部引用只是失去对应的行。
                if let path = Self.columnString(imagesStmt, 0), owns(path) {
                    staleOwnedPaths.append(path)
                }
            }
            sqlite3_reset(imagesStmt)
            sqlite3_clear_bindings(imagesStmt)
            sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
            sqlite3_step(deleteStmt)
            if sqlite3_changes(db) > 0 {
                invalidateSearch(preservingMatches: true)
                searchRevision += 1
            }
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            // 一次保留期清理可能遗留数百个文件，因此在主 actor 之外删除它们。
            if !staleOwnedPaths.isEmpty {
                Task.detached(priority: .utility) {
                    for path in staleOwnedPaths {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            }
        }
        // 以最旧的未固定行为准：若把免清理的固定项算进来，该判断会永远为真。
        if items.last(where: { !$0.isPinned }).map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
    }

    /// 删除属于我们所有的图片文件；外部引用不动。
    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath, owns(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 打开数据库、建表并预编译全部语句；任一步失败返回 false。
    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // tag 是后来加的列：旧库补一列，已存在时报重复列错误并被忽略。
        _ = sqlite3_exec(db, "ALTER TABLE items ADD COLUMN tag TEXT", nil, nil, nil)
        insertStmt = prepare(Self.insertSQL)
        // 两个走索引的分支，刻意不用一个 OR。参见 docs/features/clipboard.md#store。
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at, tag FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        windowFloorStmt = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at, i.tag
            FROM (
              SELECT rowid FROM items_fts WHERE items_fts MATCH ?
              ORDER BY rowid DESC LIMIT \(Self.searchLimit)
            ) f JOIN items i ON i.rowid = f.rowid ORDER BY f.rowid DESC
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        // 这里只写入时间戳：取消固定会整行重写，使其重新回到历史最前。
        pinStmt = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        tagStmt = prepare("UPDATE items SET tag = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return insertStmt != nil && loadStmt != nil && windowFloorStmt != nil && searchStmt != nil
            && deleteByIDStmt != nil && pinStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    /// 按 SQL 预编译一条语句（绑定在同一个数据库连接上）；失败时返回 nil。
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    /// 释放全部预编译语句并关闭数据库连接。
    private func closeDatabase() {
        [
            insertStmt, loadStmt, windowFloorStmt, searchStmt, deleteByIDStmt, pinStmt, tagStmt,
            staleImagesStmt, deleteStaleStmt
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        windowFloorStmt = nil
        searchStmt = nil
        deleteByIDStmt = nil
        pinStmt = nil
        tagStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    /// 在非主线程把导入内容流式写入数据库文件；暂存的 blob 会迁入 `imagesDirectory`，
    /// 这正是 `owns` 返回 true、日后可被保留期回收的原因。
    nonisolated static func importStoredItems(
        inDatabaseAt url: URL, adoptingImagesInto imagesDirectory: URL? = nil,
        _ items: some Sequence<ClipboardItem>
    ) -> Int {
        var keys: Set<Int> = []
        forEachStoredItem(inDatabaseAt: url) { keys.insert(importKey($0)) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return 0
        }
        defer { sqlite3_close_v2(db) }
        // 轮询器的采集可能正持有写锁；不设置该超时会导致导入被截断。
        sqlite3_busy_timeout(db, 5_000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        var inserted = 0
        // 整批使用一个事务：约一次 WAL 提交，而不是每行一次。
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for staged in items {
            let item = adoptionTarget(staged, in: imagesDirectory)
            guard keys.insert(importKey(item)).inserted else { continue }
            if item.imagePath != staged.imagePath,
                !moveBlob(from: staged.imagePath, to: item.imagePath)
            {
                continue
            }
            bindAndInsert(stmt, item)
            inserted += 1
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        return inserted
    }

    /// 只散列、不持有：为导入去重不应把整份历史的文本都放进内存。
    nonisolated private static func importKey(_ item: ClipboardItem) -> Int {
        var hasher = Hasher()
        hasher.combine(item.kind)
        // 除图片外都以 `text` 为键，否则所有文件条目会散列成同一个值。
        hasher.combine(item.kind == .image ? item.imagePath : item.text)
        return hasher.finalize()
    }

    /// 保留暂存 blob 的文件名，使同一份备份导入两次会落到同一路径——
    /// 该行据此去重，而不会为每张图片再造一份副本。
    nonisolated private static func adoptionTarget(
        _ item: ClipboardItem, in directory: URL?
    ) -> ClipboardItem {
        guard let directory, item.kind == .image, let path = item.imagePath else { return item }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ClipboardItem(
            id: item.id, kind: .image, text: nil,
            imagePath: directory.appendingPathComponent(name).path, createdAt: item.createdAt,
            sourceBundleID: item.sourceBundleID, pinnedAt: item.pinnedAt)
    }

    /// 返回 false 时会跳过该行，使任何行都不会指向即将被丢弃的暂存目录。
    nonisolated private static func moveBlob(from source: String?, to destination: String?) -> Bool {
        guard let source, let destination else { return false }
        let from = URL(fileURLWithPath: source)
        let to = URL(fileURLWithPath: destination)
        return (try? FileManager.default.moveItem(at: from, to: to)) != nil
            || (try? FileManager.default.copyItem(at: from, to: to)) != nil
    }

    /// 遍历内存窗口之外的内容，在非主线程执行。使用 `READWRITE` 是因为 WAL 读取方仍需写入 `-shm`。
    nonisolated static func forEachStoredItem(
        inDatabaseAt url: URL, _ body: (ClipboardItem) -> Void
    ) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return
        }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at, tag
            FROM items ORDER BY rowid
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = row(stmt) { body(item) }
        }
    }

    /// 把一行查询结果还原为 `ClipboardItem`；字段不合法时返回 nil。
    nonisolated private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6),
            tag: columnString(stmt, 7))
    }

    /// 读取可空的 REAL 列为 Date；列为 NULL 时返回 nil。
    nonisolated private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    /// 读取可空的 TEXT 列为 Swift String；列为 NULL 时返回 nil。
    nonisolated private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
