// 文件职责：以 SQLite 持久化本地聊天会话，负责建表、读写会话/消息/附件与推理记录。
// 分层：Service；主 actor 上运行，会话摘要常驻内存，完整转录按需加载。
import Foundation
import Observation
import SQLite3

/// SQLite 的 transient 析构标记：告诉 sqlite3 在绑定后自行拷贝数据，而非引用 Swift 内存。
private let chatSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 本地聊天存储：摘要常驻内存，转录仅在请求时按需加载。
@MainActor
@Observable
final class ChatHistoryStore {
    private(set) var conversations: [ChatConversation] = []
    private(set) var isAvailable = true

    /// 建库脚本：会话/消息为骨架，附件、搜索、工具调用、推理与元信息各自一张子表。
    private static let schema = """
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS conversations(
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT NOT NULL,
          preview TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          message_count INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages(
          id TEXT PRIMARY KEY NOT NULL,
          conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          role TEXT NOT NULL,
          text TEXT NOT NULL,
          state TEXT NOT NULL,
          sent_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS message_images(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          mime_type TEXT NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_documents(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          name TEXT NOT NULL,
          mime_type TEXT NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_searches(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          query TEXT,
          text_offset INTEGER NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS message_tools(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          call_id TEXT NOT NULL,
          origin TEXT NOT NULL,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          text_offset INTEGER NOT NULL,
          PRIMARY KEY(message_id, position)
        );
        CREATE TABLE IF NOT EXISTS conversation_details(
          conversation_id TEXT PRIMARY KEY NOT NULL
            REFERENCES conversations(id) ON DELETE CASCADE,
          custom_title TEXT,
          generated_title TEXT,
          pinned INTEGER NOT NULL DEFAULT 0,
          model TEXT
        );
        CREATE TABLE IF NOT EXISTS message_details(
          message_id TEXT PRIMARY KEY NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          tool_scope TEXT,
          input_tokens INTEGER,
          output_tokens INTEGER,
          cached_tokens INTEGER,
          reasoning_tokens INTEGER,
          context_window INTEGER,
          cost_usd REAL
        );
        CREATE TABLE IF NOT EXISTS message_thinking(
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          text TEXT NOT NULL,
          text_offset INTEGER NOT NULL,
          duration REAL,
          PRIMARY KEY(message_id, position)
        );
        CREATE INDEX IF NOT EXISTS messages_by_conversation
          ON messages(conversation_id, position);
        CREATE INDEX IF NOT EXISTS conversations_by_recency
          ON conversations(updated_at DESC);
        """

    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private var database: OpaquePointer?

    init(directory: URL) {
        databaseURL = directory.appendingPathComponent("ai-chats.sqlite3")
    }

    isolated deinit {
        sqlite3_close(database)
    }

    /// 从数据库读取全部会话摘要，按最近更新倒序填充内存缓存。
    func load() {
        guard ensureDatabase(), let database else { return }
        let sql = """
            SELECT c.id, c.title, c.preview, c.created_at, c.updated_at, c.message_count,
              m.custom_title, COALESCE(m.pinned, 0), m.generated_title
            FROM conversations c
            LEFT JOIN conversation_details m ON m.conversation_id = c.id
            ORDER BY c.updated_at DESC;
            """
        guard let statement = prepare(sql, in: database) else { return }
        defer { sqlite3_finalize(statement) }
        var loaded: [ChatConversation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else { continue }
            loaded.append(
                ChatConversation(
                    id: id, title: text(statement, 1), preview: text(statement, 2),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    messageCount: Int(sqlite3_column_int64(statement, 5)),
                    customTitle: optionalText(statement, 6),
                    isPinned: sqlite3_column_int64(statement, 7) != 0,
                    generatedTitle: optionalText(statement, 8)))
        }
        conversations = loaded
    }

    /// 彻底关闭：释放句柄与常驻摘要，但保留磁盘上的数据库文件。
    func close() {
        sqlite3_close(database)
        database = nil
        conversations = []
    }

    /// 在内存中的会话摘要里按标题与预览做不区分大小写的搜索；空查询返回全部。
    func search(_ query: String) -> [ChatConversation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    /// 按 id 取内存中的会话摘要。
    func conversation(id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    /// 空白名称会把标题交还给首个问题，而不是存一个空字符串。
    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.titleLimit))
        guard var conversation = conversation(id: id),
            write(.customTitle(custom), of: id)
        else { return }
        conversation.customTitle = custom
        replace(conversation)
    }

    /// 测试框架给会话起的名字；单独存储，以免后续保存时被重新推导掉。
    func setGeneratedTitle(_ title: String, id: UUID) {
        guard var conversation = conversation(id: id), write(.generatedTitle(title), of: id)
        else { return }
        conversation.generatedTitle = title
        replace(conversation)
    }

    /// 设置会话的置顶状态；无变化时直接返回。
    func setPinned(_ pinned: Bool, id: UUID) {
        guard var conversation = conversation(id: id), conversation.isPinned != pinned,
            write(.pinned(pinned), of: id)
        else { return }
        conversation.isPinned = pinned
        replace(conversation)
    }

    private static let titleLimit = 120

    /// 读取一个会话的完整转录（含附件、搜索、工具调用与推理）。
    func session(id: UUID) -> ChatSession? {
        guard ensureDatabase(), let database else { return nil }
        let conversationSQL = """
            SELECT created_at, updated_at FROM conversations WHERE id = ? LIMIT 1;
            """
        guard let conversation = prepare(conversationSQL, in: database) else { return nil }
        defer { sqlite3_finalize(conversation) }
        bind(id.uuidString, to: conversation, at: 1)
        guard sqlite3_step(conversation) == SQLITE_ROW else { return nil }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(conversation, 0))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(conversation, 1))

        let messageSQL = """
            SELECT id, role, text, state, sent_at FROM messages
            WHERE conversation_id = ? ORDER BY position;
            """
        guard let messagesStatement = prepare(messageSQL, in: database) else { return nil }
        defer { sqlite3_finalize(messagesStatement) }
        bind(id.uuidString, to: messagesStatement, at: 1)
        let images = images(forConversation: id, in: database)
        let documents = documents(forConversation: id, in: database)
        let searches = searches(forConversation: id, in: database)
        let toolUses = toolUses(forConversation: id, in: database)
        let reasoning = reasoning(forConversation: id, in: database)
        let meta = messageMeta(forConversation: id, in: database)
        var messages: [ChatMessage] = []
        while sqlite3_step(messagesStatement) == SQLITE_ROW {
            guard
                let messageID = UUID(uuidString: text(messagesStatement, 0)),
                let role = ChatMessage.Role(rawValue: text(messagesStatement, 1)),
                let storedState = ChatMessage.State(rawValue: text(messagesStatement, 3))
            else { continue }
            var body = text(messagesStatement, 2)
            let state: ChatMessage.State
            if storedState == .streaming {
                state = .failed
                if body.isEmpty { body = "Response interrupted." }
            } else {
                state = storedState
            }
            messages.append(
                ChatMessage(
                    id: messageID, role: role, text: body, state: state,
                    sentAt: Date(
                        timeIntervalSince1970: sqlite3_column_double(messagesStatement, 4)),
                    images: images[messageID] ?? [], documents: documents[messageID] ?? [],
                    searches: searches[messageID] ?? [],
                    toolUses: toolUses[messageID] ?? [],
                    reasoning: reasoning[messageID] ?? [],
                    usage: meta[messageID]?.usage, toolScope: meta[messageID]?.toolScope))
        }
        return ChatSession(
            id: id, createdAt: createdAt, updatedAt: updatedAt, messages: messages,
            model: model(forConversation: id, in: database))
    }

    /// 在单个事务里写入会话：先写会话行与消息尾部，再写模型选择，全部成功才 COMMIT。
    func save(_ session: ChatSession) {
        guard !session.messages.isEmpty, ensureDatabase(), let database else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return }
        guard saveConversation(session, in: database), rewriteTail(of: session, database: database),
            saveModel(of: session)
        else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return
        }
        guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            return
        }
        var summary = session.summary
        // 摘要会被重新推导；重命名与置顶是用户的，因此要携带过来。
        if let existing = conversation(id: session.id) {
            summary.customTitle = existing.customTitle
            summary.isPinned = existing.isPinned
            summary.generatedTitle = existing.generatedTitle
        }
        replace(summary)
    }

    /// 用给定摘要替换内存中的同 id 会话，并保持按更新时间倒序。
    private func replace(_ conversation: ChatConversation) {
        var updated = conversations.filter { $0.id != conversation.id }
        updated.append(conversation)
        conversations = updated.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 会话元信息行里的一项事实；写入其中一项不会影响其他项。
    private enum Meta {
        case customTitle(String?)
        case generatedTitle(String)
        case pinned(Bool)
        case model(AIModelSelection)

        var column: String {
            switch self {
            case .customTitle: "custom_title"
            case .generatedTitle: "generated_title"
            case .pinned: "pinned"
            case .model: "model"
            }
        }
    }

    /// 用 UPSERT 写入元信息行的单列，兼容行尚不存在的情况。
    private func write(_ meta: Meta, of id: UUID) -> Bool {
        guard ensureDatabase(), let database else { return false }
        let column = meta.column
        let sql = """
            INSERT INTO conversation_details(conversation_id, \(column)) VALUES(?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET \(column) = excluded.\(column);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        switch meta {
        case .customTitle(let title): if let title { bind(title, to: statement, at: 2) }
        case .generatedTitle(let title): bind(title, to: statement, at: 2)
        case .pinned(let pinned): sqlite3_bind_int64(statement, 2, pinned ? 1 : 0)
        case .model(let model):
            guard let json = try? JSONEncoder().encode(model),
                let encoded = String(bytes: json, encoding: .utf8)
            else { return false }
            bind(encoded, to: statement, at: 2)
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// 删除指定会话（子表随外键级联删除），并同步移除内存缓存。
    func remove(id: UUID) {
        guard ensureDatabase(), let database,
            let statement = prepare("DELETE FROM conversations WHERE id = ?;", in: database)
        else { return }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        conversations.removeAll { $0.id == id }
    }

    /// 置顶会话是用户明确要求保留的，因此清空其余会话时跳过它们。
    func clearAll() {
        guard ensureDatabase(), let database,
            sqlite3_exec(
                database, "DELETE FROM conversations WHERE id NOT IN (\(Self.pinnedIDs))", nil,
                nil, nil) == SQLITE_OK
        else { return }
        conversations.removeAll { !$0.isPinned }
    }

    private static let pinnedIDs =
        "SELECT conversation_id FROM conversation_details WHERE pinned = 1"

    /// 因内联 BLOB，这是唯一一个删除能释放页但不会收缩文件的存储。
    @discardableResult
    func prune(before cutoff: Date) -> Int {
        guard ensureDatabase(), let database,
            let statement = prepare(
                "DELETE FROM conversations WHERE updated_at < ? AND id NOT IN (\(Self.pinnedIDs));",
                in: database)
        else { return 0 }
        var removed = 0
        defer {
            sqlite3_finalize(statement)
            if removed > 0 { sqlite3_exec(database, "VACUUM", nil, nil, nil) }
        }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { return 0 }
        removed = Int(sqlite3_changes(database))
        guard removed > 0 else { return 0 }
        conversations.removeAll { $0.updatedAt < cutoff && !$0.isPinned }
        return removed
    }

    /// 按需开库：创建目录、以 WAL 模式打开并确保表结构存在，失败时置 `isAvailable = false`。
    private func ensureDatabase() -> Bool {
        if database != nil { return true }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            isAvailable = false
            return false
        }
        guard
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(database, Self.schema, nil, nil, nil) == SQLITE_OK
        else {
            sqlite3_close(database)
            database = nil
            isAvailable = false
            return false
        }
        isAvailable = true
        return true
    }

    /// 写入或更新会话主行（标题、预览、时间与消息数）。
    private func saveConversation(_ session: ChatSession, in database: OpaquePointer) -> Bool {
        let sql = """
            INSERT INTO conversations(id, title, preview, created_at, updated_at, message_count)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title = excluded.title,
              preview = excluded.preview,
              updated_at = excluded.updated_at,
              message_count = excluded.message_count;
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        let summary = session.summary
        bind(summary.id.uuidString, to: statement, at: 1)
        bind(summary.title, to: statement, at: 2)
        bind(summary.preview, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, summary.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, summary.updatedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 6, Int64(summary.messageCount))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// 会话只会追加或替换最后一条，因此保存时只重写已存储的尾部。
    private func rewriteTail(of session: ChatSession, database: OpaquePointer) -> Bool {
        let stored = storedMessageCount(of: session.id, in: database)
        // 存储行数多于内存中的会话，说明是外部状态；整段重写，绝不拼接。
        let rewriteFrom = stored > session.messages.count ? 0 : max(stored - 1, 0)
        guard
            let deletion = prepare(
                "DELETE FROM messages WHERE conversation_id = ? AND position >= ?;", in: database)
        else { return false }
        bind(session.id.uuidString, to: deletion, at: 1)
        sqlite3_bind_int64(deletion, 2, Int64(rewriteFrom))
        let deleted = sqlite3_step(deletion) == SQLITE_DONE
        sqlite3_finalize(deletion)
        guard deleted else { return false }

        let sql = """
            INSERT INTO messages(id, conversation_id, position, role, text, state, sent_at)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, message) in session.messages.enumerated().dropFirst(rewriteFrom) {
            bind(message.id.uuidString, to: statement, at: 1)
            bind(session.id.uuidString, to: statement, at: 2)
            sqlite3_bind_int64(statement, 3, Int64(position))
            bind(message.role.rawValue, to: statement, at: 4)
            bind(message.text, to: statement, at: 5)
            bind(message.state.rawValue, to: statement, at: 6)
            sqlite3_bind_double(statement, 7, message.sentAt.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return session.messages[rewriteFrom...].allSatisfy {
            saveImages(of: $0, in: database) && saveDocuments(of: $0, in: database)
                && saveSearches(of: $0, in: database)
                && saveToolUses(of: $0, in: database)
                && saveReasoning(of: $0, in: database)
                && saveMeta(of: $0, in: database)
        }
    }

    /// 查询数据库中该会话已存储的消息条数。
    private func storedMessageCount(of id: UUID, in database: OpaquePointer) -> Int {
        guard
            let statement = prepare(
                "SELECT COUNT(*) FROM messages WHERE conversation_id = ?;", in: database)
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// 写入一条消息的搜索记录（列表为空时直接成功）。
    private func saveSearches(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.searches.isEmpty else { return true }
        let sql = """
            INSERT INTO message_searches(message_id, position, query, text_offset)
            VALUES(?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for search in message.searches {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(search.sequence))
            if let query = search.query { bind(query, to: statement, at: 3) }
            sqlite3_bind_int64(statement, 4, Int64(search.textOffset))
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// 已存储的搜索必定已完成：只有正在进行的回复才可能有未完成的搜索。
    private func searches(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatSearch]] {
        let sql = """
            SELECT s.message_id, s.query, s.text_offset, s.position FROM message_searches s
            JOIN messages m ON m.id = s.message_id
            WHERE m.conversation_id = ? ORDER BY s.message_id, s.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var searches: [UUID: [ChatSearch]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let query = optionalText(statement, 1)
            searches[messageID, default: []].append(
                ChatSearch(
                    query: query, isComplete: true,
                    textOffset: Int(sqlite3_column_int64(statement, 2)),
                    sequence: Int(sqlite3_column_int64(statement, 3))))
        }
        return searches
    }

    /// 写入一条消息的工具调用记录（列表为空时直接成功）。
    private func saveToolUses(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.toolUses.isEmpty else { return true }
        let sql = """
            INSERT INTO message_tools(
              message_id, position, call_id, origin, title, state, text_offset)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for use in message.toolUses {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(use.sequence))
            bind(use.callID, to: statement, at: 3)
            bind(use.origin, to: statement, at: 4)
            bind(use.title, to: statement, at: 5)
            bind(use.state.rawValue, to: statement, at: 6)
            sqlite3_bind_int64(statement, 7, Int64(use.textOffset))
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// 仍在运行的工具调用属于一个已消失的进程，因此它从未回报结果。
    private func toolUses(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatToolUse]] {
        let sql = """
            SELECT t.message_id, t.call_id, t.origin, t.title, t.state, t.text_offset, t.position
            FROM message_tools t
            JOIN messages m ON m.id = t.message_id
            WHERE m.conversation_id = ? ORDER BY t.message_id, t.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var uses: [UUID: [ChatToolUse]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let stored = ChatToolUse.State(rawValue: text(statement, 4)) ?? .failed
            uses[messageID, default: []].append(
                ChatToolUse(
                    callID: text(statement, 1), origin: text(statement, 2),
                    title: text(statement, 3), state: stored == .running ? .failed : stored,
                    textOffset: Int(sqlite3_column_int64(statement, 5)),
                    sequence: Int(sqlite3_column_int64(statement, 6))))
        }
        return uses
    }

    /// 写在会话行之后，因为元信息行引用它；未选择过模型的会话则不会有这行。
    private func saveModel(of session: ChatSession) -> Bool {
        guard let model = session.model else { return true }
        return write(.model(model), of: session.id)
    }

    /// 已被移除的路由应由 Coordinator 修复；无法解码的选中项则视为不存在。
    private func model(forConversation id: UUID, in database: OpaquePointer) -> AIModelSelection? {
        guard
            let statement = prepare(
                "SELECT model FROM conversation_details WHERE conversation_id = ? AND model IS NOT NULL;",
                in: database)
        else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try? JSONDecoder().decode(
            AIModelSelection.self, from: Data(text(statement, 0).utf8))
    }

    /// 已保存过的会话在轮次之间切换模型；尚未保存过的会话则在首次保存时带上它。
    func setModel(_ model: AIModelSelection, id: UUID) {
        guard conversation(id: id) != nil else { return }
        _ = write(.model(model), of: id)
    }

    /// 写入一条消息的推理/思考块（列表为空时直接成功）。
    private func saveReasoning(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.reasoning.isEmpty else { return true }
        let sql = """
            INSERT INTO message_thinking(message_id, position, text, text_offset, duration)
            VALUES(?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, block) in message.reasoning.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(block.text, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, Int64(block.textOffset))
            if let duration = block.duration { sqlite3_bind_double(statement, 5, duration) }
            guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// 读取一个会话下所有消息的推理/思考块，按消息与位置排序。
    private func reasoning(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [ChatReasoning]] {
        let sql = """
            SELECT r.message_id, r.text, r.text_offset, r.duration FROM message_thinking r
            JOIN messages m ON m.id = r.message_id
            WHERE m.conversation_id = ? ORDER BY r.message_id, r.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var reasoning: [UUID: [ChatReasoning]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let duration =
                sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 3)
            reasoning[messageID, default: []].append(
                ChatReasoning(
                    text: text(statement, 1), textOffset: Int(sqlite3_column_int64(statement, 2)),
                    duration: duration))
        }
        return reasoning
    }

    /// 只有带工具范围或用量报告的消息才写元信息行。
    private func saveMeta(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard message.toolScope != nil || message.usage != nil else { return true }
        let sql = """
            INSERT INTO message_details(message_id, tool_scope, input_tokens, output_tokens,
              cached_tokens, reasoning_tokens, context_window, cost_usd)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(message.id.uuidString, to: statement, at: 1)
        if let scope = message.toolScope { bind(scope, to: statement, at: 2) }
        if let usage = message.usage {
            let counts = [
                usage.inputTokens, usage.outputTokens, usage.cachedInputTokens,
                usage.reasoningTokens, usage.contextWindow
            ]
            for (offset, count) in counts.enumerated() {
                if let count { sqlite3_bind_int64(statement, Int32(offset + 3), Int64(count)) }
            }
            if let cost = usage.costUSD { sqlite3_bind_double(statement, 8, cost) }
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// 未设置任何用量列的元信息行只带了工具范围：说明该回复未回报任何信息。
    private func messageMeta(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: (toolScope: String?, usage: AIUsage?)] {
        let sql = """
            SELECT x.message_id, x.tool_scope, x.input_tokens, x.output_tokens, x.cached_tokens,
              x.reasoning_tokens, x.context_window, x.cost_usd
            FROM message_details x JOIN messages m ON m.id = x.message_id
            WHERE m.conversation_id = ?;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        func count(_ column: Int32) -> Int? {
            sqlite3_column_type(statement, column) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, column))
        }
        var meta: [UUID: (toolScope: String?, usage: AIUsage?)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)) else { continue }
            let usage = AIUsage(
                inputTokens: count(2), outputTokens: count(3), cachedInputTokens: count(4),
                reasoningTokens: count(5), contextWindow: count(6),
                costUSD: sqlite3_column_type(statement, 7) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 7))
            meta[messageID] = (optionalText(statement, 1), usage == AIUsage() ? nil : usage)
        }
        return meta
    }

    /// 写入一条消息的图片（列表为空时直接成功）。
    private func saveImages(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.images.isEmpty else { return true }
        let sql = """
            INSERT INTO message_images(message_id, position, mime_type, data) VALUES(?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, image) in message.images.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(image.mimeType, to: statement, at: 3)
            let bound = image.data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement, 4, bytes.baseAddress, Int32(bytes.count), chatSQLiteTransient)
            }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// 写入一条消息的文档附件（列表为空时直接成功）。
    private func saveDocuments(of message: ChatMessage, in database: OpaquePointer) -> Bool {
        guard !message.documents.isEmpty else { return true }
        let sql = """
            INSERT INTO message_documents(message_id, position, name, mime_type, data)
            VALUES(?, ?, ?, ?, ?);
            """
        guard let statement = prepare(sql, in: database) else { return false }
        defer { sqlite3_finalize(statement) }
        for (position, document) in message.documents.enumerated() {
            bind(message.id.uuidString, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, Int64(position))
            bind(document.name, to: statement, at: 3)
            bind(document.mimeType, to: statement, at: 4)
            let bound = document.data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement, 5, bytes.baseAddress, Int32(bytes.count), chatSQLiteTransient)
            }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { return false }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return true
    }

    /// 读取一个会话下所有消息的文档附件，按消息与位置排序。
    private func documents(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [AIDocument]] {
        let sql = """
            SELECT d.message_id, d.name, d.mime_type, d.data FROM message_documents d
            JOIN messages m ON m.id = d.message_id
            WHERE m.conversation_id = ? ORDER BY d.message_id, d.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var documents: [UUID: [AIDocument]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)),
                let bytes = sqlite3_column_blob(statement, 3)
            else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
            documents[messageID, default: []].append(
                AIDocument(data: data, mimeType: text(statement, 2), name: text(statement, 1)))
        }
        return documents
    }

    /// 读取一个会话下所有消息的图片，按消息与位置排序。
    private func images(
        forConversation id: UUID, in database: OpaquePointer
    ) -> [UUID: [AIImage]] {
        let sql = """
            SELECT i.message_id, i.mime_type, i.data FROM message_images i
            JOIN messages m ON m.id = i.message_id
            WHERE m.conversation_id = ? ORDER BY i.message_id, i.position;
            """
        guard let statement = prepare(sql, in: database) else { return [:] }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        var images: [UUID: [AIImage]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let messageID = UUID(uuidString: text(statement, 0)),
                let bytes = sqlite3_column_blob(statement, 2)
            else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            images[messageID, default: []].append(AIImage(data: data, mimeType: text(statement, 1)))
        }
        return images
    }

    /// 编译 SQL 语句；失败时返回 `nil`。
    private func prepare(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    /// 将字符串以 transient 方式绑定到指定参数位，由 SQLite 自行拷贝。
    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, chatSQLiteTransient)
    }

    /// 读取可空文本列：列为 NULL 时返回 `nil`。
    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    /// 读取文本列；列为 NULL 时返回空字符串。
    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}
