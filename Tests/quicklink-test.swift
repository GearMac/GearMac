// 文件职责：quicklink（快捷链接）的独立测试 harness，覆盖目标识别、路径检测、编码选择、占位符检测、展示顺序、存储增删改查与校验、置顶、持久化、外部数据库读取、存档往返与合并、手写存档以及 Raycast 导入。
// 分层：测试 harness；通过注入 home 目录与临时目录，使断言不依赖具体机器与用户数据。
import Foundation

/// 独立运行的测试入口：依次执行各测试分组，最后打印通过率并以失败数决定退出码。
@main
@MainActor
struct QuicklinkTests {
    static var failures = 0
    static var passes = 0

    /// 在所有解析路径的地方注入该目录，使任何断言都不依赖具体机器。
    static let home = "/Users/gearmac-harness"

    static func main() {
        destinationDetection()
        pathDetection()
        encodingChoice()
        placeholderDetection()
        displayOrder()
        storeCRUD()
        storeValidation()
        pinning()
        persistence()
        readsADatabaseWrittenElsewhere()
        corruptDatabaseIsPreserved()
        archiveRoundTrip()
        archiveMerge()
        archiveAcceptsAHandWrittenFile()
        raycastImport()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Destination detection

    /// 校验目标识别：网页、deeplink、网络路径，以及应当解析为 nil 的输入。
    static func destinationDetection() {
        expect(detect("https://example.com") == .web(url("https://example.com")), "https is a website")
        expect(detect("http://example.com/a") == .web(url("http://example.com/a")), "http is a website")
        expect(
            detect("example.com/search?q=1") == .web(url("https://example.com/search?q=1")),
            "a bare host gains https, keeping its path and query")
        expect(
            detect("sub.example.co.uk") == .web(url("https://sub.example.co.uk")),
            "a multi-label host is still a website")
        expect(
            detect("example.com:8080/x") == .web(url("https://example.com:8080/x")),
            "a port does not stop a bare host being a website")
        expect(
            detect("spotify://track/1") == .deeplink(url("spotify://track/1")),
            "an unknown scheme is a deeplink")
        expect(
            detect("shortcuts://run-shortcut?name=Focus")
                == .deeplink(url("shortcuts://run-shortcut?name=Focus")),
            "a deeplink keeps its query")
        expect(
            detect("mailto:someone@example.com") == .deeplink(url("mailto:someone@example.com")),
            "a schemeless-authority scheme is still a deeplink")
        expect(
            detect("smb://server/share") == .network(url("smb://server/share")),
            "smb is a network path")
        expect(
            detect("afp://server/share") == .network(url("afp://server/share")),
            "afp is a network path")
        expect(
            detect("http://example.com/a b") == .web(url("http://example.com/a%20b")),
            "a literal space is rescued rather than rejected")
        expect(
            detect("https://example.com/a%20b") == .web(url("https://example.com/a%20b")),
            "an already-encoded value is not encoded twice")

        expect(detect("") == nil, "an empty link resolves to nothing")
        expect(detect("   ") == nil, "a whitespace-only link resolves to nothing")
        expect(detect("not a url") == nil, "prose is not a destination")
        expect(detect("{argument}") == nil, "a bare leftover placeholder is not a destination")
        expect(detect("1.5") == nil, "a decimal is not a host")
        expect(detect("C:/Users/x") == nil, "a drive letter is not a scheme")
    }

    /// 校验路径识别：绝对路径、波浪号展开、file URL，以及多余空白与结尾斜杠的处理。
    static func pathDetection() {
        expect(detect("/tmp") == .path("/tmp"), "an absolute path is a path")
        expect(
            detect("~/Downloads") == .path("\(home)/Downloads"),
            "a tilde expands against the injected home")
        expect(detect("~") == .path(home), "a bare tilde is the home directory")
        expect(
            detect("  ~/Projects/GearMac  ") == .path("\(home)/Projects/GearMac"),
            "surrounding whitespace is trimmed before detection")
        expect(
            detect("file:///Users/x/notes.md") == .path("/Users/x/notes.md"),
            "a file URL resolves to the path it names, not to a deeplink")
        expect(
            QuicklinkDestination.detect("~/Downloads", homeDirectory: "/Users/other/")
                == .path("/Users/other/Downloads"),
            "a trailing slash on the home directory does not double up")
    }

    /// 校验编码选择：进入 URL/deeplink 的值用百分号编码，进入路径的值不编码。
    static func encodingChoice() {
        expect(
            QuicklinkDestination.usesURLEncoding("https://x.com/?q={argument}", homeDirectory: home),
            "values going into a URL are encoded")
        expect(
            QuicklinkDestination.usesURLEncoding("spotify://search/{argument}", homeDirectory: home),
            "values going into a deeplink are encoded")
        expect(
            !QuicklinkDestination.usesURLEncoding("~/Notes/{date}.md", homeDirectory: home),
            "values going into a path are not encoded")
        expect(
            !QuicklinkDestination.usesURLEncoding("/tmp/{argument}", homeDirectory: home),
            "an absolute path is not encoded either")
    }

    /// 校验占位符检测：`{argument}` 算占位符，未闭合的花括号不算。
    static func placeholderDetection() {
        expect(
            QuicklinkDestination.containsPlaceholder("https://x.com/?q={argument}"),
            "a token is a placeholder")
        expect(
            !QuicklinkDestination.containsPlaceholder("https://x.com/?q=1"),
            "a plain link has no placeholder")
        expect(
            !QuicklinkDestination.containsPlaceholder("https://x.com/{unterminated"),
            "an unclosed brace is not a placeholder")
    }

    // MARK: - Model

    /// 校验展示顺序：置顶项按置顶时间排在前，其余按名称不区分大小写排序。
    static func displayOrder() {
        let base = Date(timeIntervalSince1970: 1_000)
        let zulu = link("Zulu")
        let alpha = link("alpha")
        var pinnedLate = link("Late Pin")
        pinnedLate.pinnedAt = base.addingTimeInterval(60)
        var pinnedEarly = link("Early Pin")
        pinnedEarly.pinnedAt = base

        let sorted = [zulu, alpha, pinnedLate, pinnedEarly].sorted(by: Quicklink.precedes)
        expect(
            sorted.map(\.name) == ["Early Pin", "Late Pin", "alpha", "Zulu"],
            "pins lead in pin order, then the rest sort case-insensitively by name")
    }

    // MARK: - Store

    /// 校验存储的增删改查：新增、编辑保持同一身份、隐藏于根搜索、启停、复制与删除。
    static func storeCRUD() {
        withStore { store in
            guard let github = try? store.add(link("GitHub", "https://github.com")) else {
                return fail("adding a quicklink succeeds")
            }
            expect(store.quicklinks.map(\.name) == ["GitHub"], "an added quicklink is listed")
            expect(store.quicklink(entryID: github.entryID)?.id == github.id, "entry id round-trips")

            var edited = github
            edited.name = "GitHub Issues"
            edited.link = "https://github.com/issues"
            try? store.update(edited)
            expect(
                store.quicklink(id: github.id)?.name == "GitHub Issues",
                "an edit is stored under the same identity")
            expect(
                store.quicklink(id: github.id)?.link == "https://github.com/issues",
                "the edited link is stored")

            try? store.setShowsInRootSearch(false, id: github.id)
            expect(
                store.quicklink(id: github.id)?.showsInRootSearch == false,
                "hiding from root search is stored")

            expect(github.isEnabled, "a new quicklink is enabled")
            try? store.setEnabled(false, id: github.id)
            expect(store.quicklink(id: github.id)?.isEnabled == false, "disabling is stored")
            expect(
                store.quicklink(id: github.id)?.link == "https://github.com/issues",
                "disabling keeps every other field intact")

            guard let copy = try? store.duplicate(id: github.id) else {
                return fail("duplicating a quicklink succeeds")
            }
            expect(copy.id != github.id, "a duplicate is a new identity")
            expect(copy.name == "GitHub Issues Copy", "a duplicate gets a distinct name")
            expect(copy.link == "https://github.com/issues", "a duplicate keeps the destination")
            expect(!copy.isEnabled, "a duplicate inherits the enabled flag")

            try? store.remove(id: copy.id)
            expect(store.quicklinks.map(\.id) == [github.id], "removing drops only that row")
        }
    }

    /// 校验保存校验规则：名称/链接必填、不可解析链接拒绝、非法字符与重名拒绝、名称保存时去空白。
    static func storeValidation() {
        withStore { store in
            expect(throwsError(store, link("", "https://x.com")) == .emptyName, "a name is required")
            expect(throwsError(store, link("Name", "")) == .emptyLink, "a link is required")
            expect(
                throwsError(store, link("Name", "not a url")) == .unresolvableLink,
                "a link that resolves to nothing is rejected")
            expect(
                throwsError(store, link("Na\0me", "https://x.com")) == .invalidCharacter,
                "a null character is rejected")

            _ = try? store.add(link("Search", "https://x.com/?q={argument}"))
            expect(
                store.quicklinks.count == 1,
                "a templated link is accepted, since its destination is only knowable once expanded")
            expect(
                throwsError(store, link("search", "https://other.com")) == .duplicateName,
                "a duplicate name is rejected case-insensitively")

            var renamed = store.quicklinks[0]
            renamed.name = "  Search  "
            expect(
                (try? store.update(renamed)) != nil,
                "a quicklink does not collide with its own name when edited")
            expect(store.quicklinks[0].name == "Search", "names are trimmed on save")
        }
    }

    /// 校验置顶行为：置顶提升到顶部、后置顶项排在先置顶项之下、编辑保留置顶、取消置顶回到字母块。
    static func pinning() {
        withStore { store in
            _ = try? store.add(link("Alpha"))
            _ = try? store.add(link("Bravo"))
            _ = try? store.add(link("Charlie"))
            expect(names(store) == ["Alpha", "Bravo", "Charlie"], "unpinned rows sort by name")

            let charlie = store.quicklinks[2].id
            let alpha = store.quicklinks[0].id
            try? store.togglePinned(id: charlie)
            expect(names(store) == ["Charlie", "Alpha", "Bravo"], "a pin lifts the row to the top")

            try? store.togglePinned(id: alpha)
            expect(
                names(store) == ["Charlie", "Alpha", "Bravo"],
                "a second pin joins below the first rather than displacing it")

            var pinned = store.quicklink(id: charlie)!
            pinned.name = "Charlie Renamed"
            try? store.update(pinned)
            expect(
                names(store) == ["Charlie Renamed", "Alpha", "Bravo"],
                "editing a pinned row keeps its pin stamp and its place")

            try? store.togglePinned(id: charlie)
            expect(
                names(store) == ["Alpha", "Bravo", "Charlie Renamed"],
                "unpinning drops the row back into the alphabetical block")
        }
    }

    /// 校验关闭并重新打开数据库后，各字段与置顶/启用状态都能恢复。
    static func persistence() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var stored: UUID?
        do {
            let store = QuicklinkStore(directory: dir)
            var draft = link("Downloads", "~/Downloads")
            draft.iconSymbol = "folder"
            draft.openWithBundleID = "com.apple.finder"
            stored = try? store.add(draft).id
            try? store.togglePinned(id: stored!)
            try? store.setEnabled(false, id: stored!)
        }

        let reopened = QuicklinkStore(directory: dir)
        reopened.load()
        expect(reopened.isAvailable, "a reopened database is available")
        guard let restored = reopened.quicklinks.first, reopened.quicklinks.count == 1 else {
            return fail("the quicklink survives a close and reopen")
        }
        expect(restored.id == stored, "identity survives")
        expect(restored.name == "Downloads" && restored.link == "~/Downloads", "fields survive")
        expect(restored.iconSymbol == "folder", "the icon survives")
        expect(restored.openWithBundleID == "com.apple.finder", "the open-with app survives")
        expect(restored.isPinned, "the pin stamp survives")
        expect(!restored.isEnabled, "the enabled flag survives")
    }

    /// 绑定的列顺序必须与读取顺序一致，且旧表需要补上 `is_enabled` 列。
    static func readsADatabaseWrittenElsewhere() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        sqlite(
            dir.appendingPathComponent("quicklinks.sqlite3"),
            """
            CREATE TABLE quicklinks(
              id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, link TEXT NOT NULL,
              open_with TEXT, icon TEXT, in_root_search INTEGER NOT NULL DEFAULT 1,
              pinned_at REAL, created_at REAL NOT NULL
            );
            INSERT INTO quicklinks(id, name, link, open_with, icon, in_root_search, created_at)
              VALUES('\(id.uuidString)', 'Jira', 'https://jira.example.com', NULL, 'ticket', 0, 1000);
            """)

        let store = QuicklinkStore(directory: dir)
        store.load()
        guard let row = store.quicklinks.first else {
            return fail("an externally written row loads")
        }
        expect(row.id == id, "the external id is read")
        expect(row.name == "Jira" && row.link == "https://jira.example.com", "the text columns line up")
        expect(row.iconSymbol == "ticket", "the icon column lines up")
        expect(row.openWithBundleID == nil, "a null open-with reads as none")
        expect(!row.showsInRootSearch, "the root-search flag lines up")
        expect(!row.isPinned, "a null pin stamp reads as unpinned")
        expect(row.isEnabled, "a table written before is_enabled loads its rows as enabled")

        // 第二次打开必须发现该列已存在，而不是重复添加。
        let reopened = QuicklinkStore(directory: dir)
        reopened.load()
        expect(reopened.quicklinks.count == 1, "the migrated table reopens cleanly")
    }

    /// quicklink 是用户手工维护的数据，因此无法读取的数据库只会上报错误，绝不会被重建。
    static func corruptDatabaseIsPreserved() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("quicklinks.sqlite3")
        let garbage = Data("this is definitely not a database".utf8)
        try? garbage.write(to: dbURL)

        let store = QuicklinkStore(directory: dir)
        expect(!store.isAvailable, "an unreadable database reports itself unavailable")
        expect(store.quicklinks.isEmpty, "no rows are invented")
        expect(
            (try? Data(contentsOf: dbURL)) == garbage,
            "the unreadable file is left exactly as it was — never deleted or overwritten")
        expect(
            throwsError(store, link("Anything")) == .storageUnavailable,
            "a mutation refuses rather than pretending to save")
    }

    // MARK: - Archive

    /// 校验导出后再导入时所有字段与服务端一致地往返。
    static func archiveRoundTrip() {
        // 使用整秒：存档为 ISO 8601，便于阅读者手工编辑。
        let stamp = Date(timeIntervalSince1970: 500)
        let pinned = Quicklink(
            name: "Pinned", link: "~/Downloads", openWithBundleID: "com.apple.finder",
            iconSymbol: "folder", isEnabled: false, showsInRootSearch: false, pinnedAt: stamp,
            createdAt: stamp)
        let plain = Quicklink(name: "GitHub", link: "https://github.com", createdAt: stamp)
        let source = [plain, pinned]

        guard let data = try? QuicklinkArchive.encode(source),
            let decoded = try? QuicklinkArchive.decode(data)
        else { return fail("an exported archive decodes again") }
        expect(decoded == source, "every field survives an export and import round trip")
    }

    /// 校验导入合并：按名称与目标去重、统计被跳过项、并为导入项分配新身份。
    static func archiveMerge() {
        let existing = [link("GitHub", "https://github.com"), link("Downloads", "~/Downloads")]
        let incoming = [
            link("github", "https://elsewhere.com"),  // 同名
            link("Repos", "https://github.com"),  // 同目标
            link("Jira", "https://jira.example.com"),  // 新项
            link("Jira Two", "https://jira.example.com")  // 与上一条在批内重复
        ]

        let result = QuicklinkArchive.merge(incoming, into: existing)
        expect(result.imported == 1, "only the genuinely new quicklink is imported")
        expect(result.skipped == 3, "the duplicates are counted rather than silently dropped")
        expect(result.additions.first?.name == "Jira", "the imported quicklink is the new one")
        expect(
            result.additions.first?.id != incoming[2].id,
            "an import takes a fresh identity so it cannot inherit another item's hotkey")

        let reimported = QuicklinkArchive.merge(existing, into: existing)
        expect(
            reimported.imported == 0 && reimported.skipped == 2,
            "importing the same file twice adds nothing")
    }

    /// 校验手写存档：省略的字段使用默认值，裸数组也能解析，无关 JSON 与空存档被拒绝。
    static func archiveAcceptsAHandWrittenFile() {
        let handWritten = Data(
            """
            { "version": 1, "quicklinks": [ { "name": "Staging", "link": "https://staging.example.com" } ] }
            """.utf8)
        guard let decoded = try? QuicklinkArchive.decode(handWritten), let first = decoded.first
        else { return fail("a hand-written archive decodes") }
        expect(first.name == "Staging", "the name is read")
        expect(first.isEnabled, "an omitted enabled flag defaults to on")
        expect(first.showsInRootSearch, "an omitted root-search flag defaults to shown")
        expect(first.pinnedAt == nil, "an omitted pin stamp reads as unpinned")

        let bareArray = Data(#"[{ "name": "A", "link": "https://a.example.com" }]"#.utf8)
        expect((try? QuicklinkArchive.decode(bareArray))?.count == 1, "a bare array also decodes")
        expect(
            throwsArchiveError(Data("{}".utf8)) == .unreadable, "an unrelated JSON file is rejected")
        expect(
            throwsArchiveError(Data(#"{"version":1,"quicklinks":[]}"#.utf8)) == .empty,
            "an archive with no quicklinks is reported as empty rather than imported")
    }

    /// 校验 Raycast 快捷链接导入：字段映射、占位符改写、openWith 解析与无效项跳过。
    static func raycastImport() {
        let bundleIDs = ["/Applications/Chrome.app": "com.google.Chrome"]
        let stamped = Date(timeIntervalSince1970: 1_780_497_120)
        let imported = RaycastQuicklinkImport.parse(
            [
                "schemaVersion": 1,
                "openWithPlatforms": [
                    ["id": "plat-1", "macos": "/Applications/Chrome.app"]
                ],
                "quicklinks": [
                    [
                        "name": " Search ",
                        "link": " https://google.com/search?q={Query} ",
                        "createdAt": "2026-06-03T14:32:00Z"
                    ],
                    [
                        "name": "Dash",
                        "link": "https://kapeli.com",
                        "openWith": "/Applications/Chrome.app"
                    ],
                    [
                        "name": "Via platform",
                        "link": "https://via.example",
                        "openWith": "plat-1"
                    ],
                    ["name": "Anna", "link": "https://annas-archive.org/search?q={query}"],
                    [
                        "name": "Named",
                        "link": #"https://x.com?q={argument name="Keyword"}"#
                    ],
                    ["name": "  ", "link": "https://skip.example"],
                    ["name": "No link"],
                    ["name": "Missing Text"]
                ]
            ],
            bundleIDForAppPath: { bundleIDs[$0] })

        expect(
            RaycastQuicklinkImport.parse(["quicklinks": []]).isEmpty,
            "Raycast import ignores an empty container")
        expect(
            RaycastQuicklinkImport.parse(["foo": 1]).isEmpty,
            "Raycast import ignores an unrecognized container")
        expect(
            imported.map(\.name) == ["Search", "Dash", "Via platform", "Anna", "Named"],
            "Raycast import keeps valid entries and source order")
        guard imported.count == 5 else { return }
        expect(
            imported[0].link == "https://google.com/search?q={argument}",
            "Raycast import rewrites {Query} to {argument}")
        expect(
            imported[3].link == "https://annas-archive.org/search?q={argument}",
            "Raycast import rewrites {query} the same way")
        expect(
            imported[4].link == #"https://x.com?q={argument name="Keyword"}"#,
            "Raycast import leaves a real {argument} token alone")
        expect(
            imported[1].openWithBundleID == "com.google.Chrome"
                && imported[2].openWithBundleID == "com.google.Chrome",
            "Raycast import resolves an app path and a platform id through the same lookup")
        expect(
            imported[0].createdAt == stamped,
            "Raycast import keeps the export's createdAt")

        let bare = RaycastQuicklinkImport.parse([
            ["name": "Bare", "link": "https://bare.example"]
        ])
        expect(bare.map(\.name) == ["Bare"], "a bare array still parses, matching snippets")
        expect(
            RaycastQuicklinkImport.rewrittenLink(
                #"https://x.com?q={argument name="query"}"#)
                == #"https://x.com?q={argument name="query"}"#,
            "a parameter named query is not rewritten as the token")
    }

    // MARK: - Helpers

    /// 使用注入的 home 目录做目标识别。
    static func detect(_ value: String) -> QuicklinkDestination? {
        QuicklinkDestination.detect(value, homeDirectory: home)
    }

    /// 构造 URL，构造失败时直接让 harness 失败退出。
    static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            fail("harness could not build \(value)")
            exit(1)
        }
        return url
    }

    /// 快捷构造一个用于测试的 Quicklink，默认目标为 example.com。
    static func link(_ name: String, _ target: String = "https://example.com") -> Quicklink {
        Quicklink(name: name, link: target)
    }

    static func names(_ store: QuicklinkStore) -> [String] {
        store.quicklinks.map(\.name)
    }

    /// 调用 `add` 并把抛出的错误作为返回值返回，便于与期望错误比较。
    static func throwsError(_ store: QuicklinkStore, _ draft: Quicklink) -> QuicklinkError? {
        do {
            _ = try store.add(draft)
            return nil
        } catch {
            return error
        }
    }

    /// 调用存档解码并把抛出的错误作为返回值返回。
    static func throwsArchiveError(_ data: Data) -> QuicklinkArchive.ArchiveError? {
        do {
            _ = try QuicklinkArchive.decode(data)
            return nil
        } catch {
            return error
        }
    }

    /// 在临时目录中创建 store，结束后清理，用于隔离每个存储用例。
    static func withStore(_ body: (QuicklinkStore) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(QuicklinkStore(directory: dir))
    }

    /// 创建一个唯一命名的临时目录供 store 用例使用。
    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gearmac-quicklink-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 写入一个并非 store 自己创建的数据库，这是证明它确实能读取外部数据库的唯一方式。
    @discardableResult
    static func sqlite(_ database: URL, _ sql: String) -> Set<String> {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [database.path, sql]
        task.standardOutput = pipe
        guard (try? task.run()) != nil else {
            fail("could not run sqlite3")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 { fail("sqlite3 failed: \(sql.prefix(60))") }
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    /// 断言：条件为真则计入通过，否则计为失败并打印标签。
    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    /// 记录一次失败并打印其标签。
    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
