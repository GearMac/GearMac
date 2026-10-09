// 文件职责：基于 SQLite 持久化用户创建的 Quicklink，提供加载、增删改、置顶、去重校验与批量导入等操作。
// 分层：Model；@MainActor 观察对象，封装 SQLite 细节，数据库不可用时拒绝写入而非静默成功。
import Foundation
import SQLite3

// 按 sqlite3.h 中的 C 宏写法书写，因为该宏未导入到 Swift。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 存放用户创建的 Quicklink 的 SQLite 库，记录从不物理删除。详见 docs/features/quicklinks.md#storage。
@MainActor
@Observable
final class QuicklinkStore {
    /// 展示顺序遵循 `Quicklink.precedes`：先按置顶时间排列置顶项，其余按名称排序。
    private(set) var quicklinks: [Quicklink] = []
    /// 数据库无法打开时为 false；此后所有写操作都会拒绝而非假装成功。
    private(set) var isAvailable = false
    var onChange: (([Quicklink]) -> Void)?

    /// 建表语句。
    private static let schema = """
        CREATE TABLE IF NOT EXISTS quicklinks(
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          link TEXT NOT NULL,
          open_with TEXT,
          icon TEXT,
          in_root_search INTEGER NOT NULL DEFAULT 1,
          pinned_at REAL,
          created_at REAL NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1
        );
        """

    private let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var upsertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var deleteStmt: OpaquePointer?

    /// 打开（必要时创建）quicklinks 数据库并准备语句。
    /// `directory` 按渠道使用默认值；测试会传入一次性目录。
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        dbURL = base.appendingPathComponent("quicklinks.sqlite3")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        isAvailable = openDatabase()
        // 打开失败时不触碰文件：这是用户数据，只上报，绝不删除。
        if !isAvailable { closeDatabase() }
    }

    /// 位于 Application Support 下，与代码片段使用的按渠道根目录相同。
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // 声明为 isolated，使析构可访问 main actor 的指针；释放本身已在主线程。
    isolated deinit {
        closeDatabase()
    }

    /// 从数据库读取全部 Quicklink 并按其展示顺序排序。
    func load() {
        guard let stmt = loadStmt else { return }
        var loaded: [Quicklink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = Self.row(stmt) { loaded.append(row) }
        }
        sqlite3_reset(stmt)
        quicklinks = loaded.sorted(by: Quicklink.precedes)
    }

    /// 被禁用的 Quicklink 不在任何地方提供，因此所有展示面都使用此列表而非 `quicklinks`。
    var enabled: [Quicklink] { quicklinks.filter(\.isEnabled) }

    /// 按 id 查找 Quicklink。
    func quicklink(id: UUID) -> Quicklink? {
        quicklinks.first { $0.id == id }
    }

    /// 按启动器条目 ID 查找 Quicklink。
    func quicklink(entryID: String) -> Quicklink? {
        Quicklink.id(fromEntryID: entryID).flatMap(quicklink)
    }

    // 接收完整草稿，新增字段时无需改动每个调用点。
    /// 校验并写入一条新的 Quicklink。
    @discardableResult
    func add(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        let value = try validated(draft)
        try write(value)
        return value
    }

    /// 校验并更新已存在的 Quicklink，id 不存在时不做任何事。
    func update(_ draft: Quicklink) throws(QuicklinkError) {
        guard quicklinks.contains(where: { $0.id == draft.id }) else { return }
        try write(validated(draft))
    }

    /// 从数据库删除指定 Quicklink 并刷新内存列表。
    func remove(id: UUID) throws(QuicklinkError) {
        guard let stmt = deleteStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }
        commit(quicklinks.filter { $0.id != id })
    }

    /// 切换指定 Quicklink 的置顶状态。
    func togglePinned(id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id) else { return }
        value.pinnedAt = value.isPinned ? nil : Date()
        try write(value)
    }

    /// 设置指定 Quicklink 是否启用。
    func setEnabled(_ enabled: Bool, id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id), value.isEnabled != enabled else { return }
        value.isEnabled = enabled
        try write(value)
    }

    /// 设置指定 Quicklink 是否出现在根搜索结果中。
    func setShowsInRootSearch(_ shows: Bool, id: UUID) throws(QuicklinkError) {
        guard var value = quicklink(id: id), value.showsInRootSearch != shows else { return }
        value.showsInRootSearch = shows
        try write(value)
    }

    /// 「复制」：使用新的标识，使引用仍指向原件，并使用不重复的名称。
    @discardableResult
    func duplicate(id: UUID) throws(QuicklinkError) -> Quicklink {
        guard let source = quicklink(id: id) else { throw .storageUnavailable }
        return try add(
            Quicklink(
                name: Self.uniqueName(basedOn: source.name, taken: quicklinks.map(\.name)),
                link: source.link, openWithBundleID: source.openWithBundleID,
                iconSymbol: source.iconSymbol, isEnabled: source.isEnabled,
                showsInRootSearch: source.showsInRootSearch))
    }

    /// 批量添加，跳过任何无效项——用于导入与备份恢复。返回实际写入的记录。
    @discardableResult
    func append(_ incoming: [Quicklink]) -> [Quicklink] {
        var added: [Quicklink] = []
        for candidate in incoming {
            if let stored = try? add(candidate) { added.append(stored) }
        }
        return added
    }

    /// 备份导入时整体替换，丢弃无效与重复的记录。
    @discardableResult
    func replace(with incoming: [Quicklink]) -> Int {
        guard isAvailable, sqlite3_exec(db, "DELETE FROM quicklinks", nil, nil, nil) == SQLITE_OK
        else { return 0 }
        commit([])
        return append(Self.sanitized(incoming)).count
    }

    /// 以 upsert 写入单条记录并刷新内存列表。
    private func write(_ value: Quicklink) throws(QuicklinkError) {
        guard let stmt = upsertStmt else { throw .storageUnavailable }
        sqlite3_bind_text(stmt, 1, value.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, value.link, -1, SQLITE_TRANSIENT)
        bind(stmt, 4, value.openWithBundleID)
        bind(stmt, 5, value.iconSymbol)
        sqlite3_bind_int(stmt, 6, value.isEnabled ? 1 : 0)
        sqlite3_bind_int(stmt, 7, value.showsInRootSearch ? 1 : 0)
        if let pinnedAt = value.pinnedAt {
            sqlite3_bind_double(stmt, 8, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        sqlite3_bind_double(stmt, 9, value.createdAt.timeIntervalSince1970)
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else { throw .storageUnavailable }

        var updated = quicklinks.filter { $0.id != value.id }
        updated.append(value)
        commit(updated.sorted(by: Quicklink.precedes))
    }

    /// 绑定可选文本参数，nil 时绑定 NULL。
    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// 更新内存列表并触发变更回调，内容无变化时跳过。
    private func commit(_ updated: [Quicklink]) {
        guard updated != quicklinks else { return }
        quicklinks = updated
        onChange?(updated)
    }

    /// 校验并清洗草稿，返回可写入的记录或抛出对应错误。
    private func validated(_ draft: Quicklink) throws(QuicklinkError) -> Quicklink {
        guard isAvailable else { throw .storageUnavailable }
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol =
            draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        value.openWithBundleID =
            draft.openWithBundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.link.isEmpty else { throw .emptyLink }
        guard !value.name.contains("\0"), !value.link.contains("\0") else {
            throw .invalidCharacter
        }
        // 模板化链接只有在填充后才能确定，因此在打开时上报。
        guard
            QuicklinkDestination.containsPlaceholder(value.link)
                || QuicklinkDestination.detect(value.link) != nil
        else { throw .unresolvableLink }
        guard
            !quicklinks.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    /// 基于原名生成不与现有名称冲突的复制名称。
    private static func uniqueName(basedOn name: String, taken: [String]) -> String {
        let folded = Set(taken.map { $0.folding(options: [.caseInsensitive], locale: .current) })
        var candidate = name + " Copy"
        var suffix = 2
        while folded.contains(candidate.folding(options: [.caseInsensitive], locale: .current)) {
            candidate = "\(name) Copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// 去除 id 重复的记录。
    private static func sanitized(_ values: [Quicklink]) -> [Quicklink] {
        var ids = Set<UUID>()
        // 采用复制并清洗而非重建，使新增字段不会在导入时被丢弃。
        return values.filter { ids.insert($0.id).inserted }
    }

    // MARK: - SQLite

    /// 打开数据库、建表建索引并准备增删查语句，任一失败返回 false。
    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // `IF NOT EXISTS` 会保留旧表原样，因此其新增列需手动补上。
        sqlite3_exec(
            db, "ALTER TABLE quicklinks ADD COLUMN is_enabled INTEGER NOT NULL DEFAULT 1", nil, nil,
            nil)
        // 放在建表之后，使后添加的列也能同样建立索引。
        sqlite3_exec(
            db,
            "CREATE INDEX IF NOT EXISTS quicklinks_pinned_at ON quicklinks(pinned_at) WHERE pinned_at IS NOT NULL",
            nil, nil, nil)
        upsertStmt = prepare(
            """
            INSERT INTO quicklinks(id, name, link, open_with, icon, is_enabled, in_root_search, pinned_at, created_at)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name, link = excluded.link, open_with = excluded.open_with,
              icon = excluded.icon, is_enabled = excluded.is_enabled,
              in_root_search = excluded.in_root_search, pinned_at = excluded.pinned_at
            """
        )
        // 两条语句均按结构体顺序列出列名，`is_enabled` 是其后追加的。
        loadStmt = prepare(
            """
            SELECT id, name, link, open_with, icon, is_enabled, in_root_search, pinned_at, created_at
            FROM quicklinks
            """
        )
        deleteStmt = prepare("DELETE FROM quicklinks WHERE id = ?")
        return upsertStmt != nil && loadStmt != nil && deleteStmt != nil
    }

    /// 预处理 SQL 语句，失败时返回 nil。
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    /// 释放所有语句句柄并关闭数据库连接。
    private func closeDatabase() {
        [upsertStmt, loadStmt, deleteStmt].forEach { sqlite3_finalize($0) }
        upsertStmt = nil
        loadStmt = nil
        deleteStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    /// 从当前结果行读取一条 Quicklink，必要字段缺失时返回 nil。
    private static func row(_ stmt: OpaquePointer?) -> Quicklink? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let name = columnString(stmt, 1), let link = columnString(stmt, 2)
        else { return nil }
        return Quicklink(
            id: id, name: name, link: link, openWithBundleID: columnString(stmt, 3),
            iconSymbol: columnString(stmt, 4),
            isEnabled: sqlite3_column_int(stmt, 5) != 0,
            showsInRootSearch: sqlite3_column_int(stmt, 6) != 0,
            pinnedAt: columnDate(stmt, 7),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)))
    }

    /// 读取指定列的日期值，列为 NULL 时返回 nil。
    private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    /// 读取指定列的文本值，列为 NULL 时返回 nil。
    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}

/// 为 String 补充空串转 nil 的辅助属性。
extension String {
    /// 空字符串时返回 nil。
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
