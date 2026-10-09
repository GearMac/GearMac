// 文件职责：settings.json 的契约测试 harness，验证键布局、值转换、文本格式化与解析告警，以及 SettingsFileRepository 的导入/保存/提交/替换/不可读/符号链接处理与路径解析。
// 分层：测试 harness；在临时目录中读写 settings.json，不触碰真实用户配置。

import Foundation
import Observation

/// 独立运行的测试入口：顺序执行各分组，最后以失败数决定退出码。
@main
@MainActor
struct SettingsFileTest {
    static var failures = 0

    static func main() async throws {
        testLayout()
        testValues()
        testFormat()
        testParseIssues()
        try await testRepository()
        try testCommit()
        try testReplace()
        try testUnreadable()
        try testSymlink()
        try testContentFolders()
        testPaths()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Layout

    /// 校验键布局：每个键恰好一个 section 一个 name，分区按设置侧栏顺序且不交错。
    private static func testLayout() {
        let malformed = SettingsFileKey.allCases.filter { key in
            key.rawValue.split(separator: ".", omittingEmptySubsequences: false).count != 2
                || key.section.isEmpty || key.name.isEmpty
        }
        check("every key is one section and one name", malformed.isEmpty)

        var closed: Set<String> = []
        var current: String?
        var reopened: [String] = []
        for key in SettingsFileKey.allCases where key.section != current {
            if let current { closed.insert(current) }
            if closed.contains(key.section) { reopened.append(key.section) }
            current = key.section
        }
        check("each section's keys are declared together", reopened.isEmpty)
        check(
            "sections follow the Settings sidebar",
            SettingsFileKey.sections == [
                "general", "appearance", "hyperKey", "calculator", "search", "applications",
                "systemSettings", "systemActions", "commands", "quicklinks", "appleShortcuts", "ai",
                "quickActions", "dictation", "fileSearch", "notes", "snippets", "navigation",
                "windowManagement", "clipboard", "emoji", "calendar", "extensions"
            ])

        // 若文件能打开其中任何一项，就等于授予了只有应用本身才可以请求的能力。
        let grantPaths = [
            "snippets.enabled", "extensions.enabled", "calendar.enabled",
            "calendar.autoJoinMeetings", "calendar.cameraPreview", "quickActions.enabled",
            "ai.mcpEnabled", "mcp.enabled", "clipboard.textSearchEnabled", "dictation.enabled"
        ]
        check(
            "no capability grant has a settings.json key",
            grantPaths.allSatisfy { SettingsFileKey(rawValue: $0) == nil })
    }

    // MARK: - Values

    /// 测试用的字符串原始值枚举。
    private enum Flavor: String, CaseIterable, SettingsFileRawValue {
        case vanilla, mint
    }

    /// 测试用的 token 枚举：原始值是数字，但写出为单词。
    private enum Keep: Int, CaseIterable, SettingsFileToken {
        case week = 7
        case forever = -1

        var settingsToken: SettingsFileJSON {
            switch self {
            case .week: 7
            case .forever: "forever"
            }
        }
    }

    /// 校验 SettingsFileJSON 与 Swift 类型之间的读写转换。
    private static func testValues() {
        check("a bool reads", Bool(settingsJSON: .bool(false)) == false)
        check("a number is not a bool", Bool(settingsJSON: 1) == nil)
        check("a quoted bool is not a bool", Bool(settingsJSON: "true") == nil)
        check("a whole number reads as an Int", Int(settingsJSON: 30) == 30)
        check("a fraction is not an Int", Int(settingsJSON: .number(1.5)) == nil)
        check("a quoted number is not an Int", Int(settingsJSON: "30") == nil)
        check("a string reads", String(settingsJSON: "é/x") == "é/x")
        check(
            "a list reads whole",
            [String](settingsJSON: .array(["a", "b"])) == ["a", "b"])
        check(
            "one bad element rejects the list rather than shortening it",
            [String](settingsJSON: .array(["a", 1])) == nil)
        check("null reads as an absent optional", String?(settingsJSON: .null) == .some(nil))
        check("a value reads as a present optional", String?(settingsJSON: "x") == .some("x"))
        check("a wrong type is not an optional", String?(settingsJSON: 1) == nil)
        check("an optional writes null", (nil as String?).settingsJSON == .null)
        check("a raw enum reads its raw value", Flavor(settingsJSON: "mint") == .mint)
        check("a raw enum rejects an unknown one", Flavor(settingsJSON: "chocolate") == nil)
        check("a raw enum writes its raw value", Flavor.vanilla.settingsJSON == "vanilla")
        check("a token enum reads a number", Keep(settingsJSON: 7) == .week)
        check("a token enum reads its word", Keep(settingsJSON: "forever") == .forever)
        check("a sentinel's raw number is not its spelling", Keep(settingsJSON: -1) == nil)
        check("a token enum writes its word", Keep.forever.settingsJSON == "forever")
    }

    // MARK: - Text

    /// 校验渲染：按键顺序、两空格缩进、转义以及往返一致。
    private static func testFormat() {
        let values: [SettingsFileKey: SettingsFileJSON] = [
            .windowShortcuts: .object([]),
            .autoSwitchInputSource: .null,
            .searchScopes: .array(["/Applications", "~/Applications"]),
            .showInMenuBar: true,
            .automaticallyCheckForUpdates: false,
            .escapeKeyBehavior: "say \"hi\"\\ / é\n\t\u{01}",
            .fileSearchIgnorePatterns: .array([]),
            .popToRootTimeout: 5,
            .windowGap: .number(-1.5)
        ]
        let golden = """
            {
              "general": {
                "showInMenuBar": true,
                "automaticallyCheckForUpdates": false,
                "popToRootSeconds": 5,
                "escapeKeyBehavior": "say \\"hi\\"\\\\ / é\\n\\t\\u0001",
                "autoSwitchInputSource": null
              },
              "applications": {
                "searchScopes": [
                  "/Applications",
                  "~/Applications"
                ]
              },
              "fileSearch": {
                "ignorePatterns": []
              },
              "windowManagement": {
                "gap": -1.5,
                "shortcuts": {}
              }
            }

            """
        let rendered = String(bytes: SettingsFileFormat.render(values), encoding: .utf8) ?? ""
        check("the file prints in key order with two-space indents", rendered == golden)
        if rendered != golden { print(rendered) }

        let parsed = try? SettingsFileFormat.parse(SettingsFileFormat.render(values))
        check("a printed file reads back to the same values", parsed?.values == values)
        check("a printed file reads back with no issues", parsed?.issues == [])
    }

    /// 校验解析告警：无效 JSON、非对象、未知 section/key 与 HUD 摘要。
    private static func testParseIssues() {
        do {
            _ = try SettingsFileFormat.parse(Data("{\n  \"general\": x\n}".utf8))
            check("invalid JSON throws", false)
        } catch {
            guard case .invalidJSON(let detail) = error else {
                return check("invalid JSON throws", false)
            }
            check("invalid JSON names the line", detail.contains("line 2"))
        }
        do {
            _ = try SettingsFileFormat.parse(Data("[1]".utf8))
            check("a file that is not an object throws", false)
        } catch {
            check("a file that is not an object throws", error == .notAnObject(nil))
        }

        let text = #"{"bogus": {}, "general": {"nope": 1, "showInMenuBar": false}, "notes": 3}"#
        let parsed = try? SettingsFileFormat.parse(Data(text.utf8))
        check("a known key reads", parsed?.values[.showInMenuBar] == false)
        check(
            "unknown sections and keys, and a section that is no object, are each reported",
            parsed?.issues == [
                .unknownSetting("bogus"), .unknownSetting("general.nope"), .notAnObject("notes")
            ])
        check(
            "the HUD line names the first issue and counts the rest",
            SettingsFileIssue.summary([.unknownSetting("a.b"), .unwritable])
                == "settings.json: unknown setting “a.b” (+1 more)")
        check("no issues, no HUD", SettingsFileIssue.summary([]) == nil)
    }

    // MARK: - Repository

    /// 用可观察属性模拟真实设置，供绑定读写。
    @Observable
    final class Fixture {
        var shows = true
        var seconds = 0
        var name: String?
        var scopes = ["/Applications"]
    }

    /// 构造绑定列表，把若干 key 连到 fixture 的属性与可选校验。
    private static func bindings(_ fixture: Fixture) -> [SettingsFileBinding] {
        [
            SettingsFileBinding(.showInMenuBar, fixture, \.shows),
            SettingsFileBinding(.popToRootTimeout, fixture, \.seconds) {
                (0...90).contains($0) ? $0 : nil
            },
            SettingsFileBinding(.autoSwitchInputSource, fixture, \.name),
            SettingsFileBinding(.searchScopes, fixture, \.scopes)
        ]
    }

    /// 校验仓库：缺失文件按当前设置写入、导入、外部编辑应用、保存与 echo 去重。
    private static func testRepository() async throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "gearmac/settings.json")

        let first = Fixture()
        first.seconds = 15
        SettingsFileRepository(fileURL: url, bindings: bindings(first)).start(importing: true)
        check(
            "a missing file is written from the current settings, folder and all",
            contents(of: url).contains(#""popToRootSeconds": 15"#))

        let edited = #"{"general": {"showInMenuBar": false, "popToRootSeconds": 30}}"#
        try write(edited, to: url)
        let fixture = Fixture()
        fixture.scopes = ["/Custom"]
        let synced = SettingsFileRepository(fileURL: url, bindings: bindings(fixture))
        var reported: [[SettingsFileIssue]] = []
        synced.onIssues = { reported.append($0) }
        synced.start(importing: true)
        check("an import sets what the file names", !fixture.shows && fixture.seconds == 30)
        check("a key the file leaves out keeps its value", fixture.scopes == ["/Custom"])
        check("an import leaves the file as it was written", contents(of: url) == edited)
        check("a clean import reports nothing", reported.isEmpty)

        try write(#"{"general": {"showInMenuBar": false, "popToRootSeconds": 999}}"#, to: url)
        await settle { !reported.isEmpty }
        check("a rejected value keeps the current one", fixture.seconds == 30)
        check("a rejected value is reported", reported.last == [.invalidValue(.popToRootTimeout)])

        try write(#"{"general": {"popToRootSeconds": 45}}"#, to: url)
        await settle { fixture.seconds == 45 }
        check("an edit made elsewhere applies", fixture.seconds == 45)
        check("a key removed from the file keeps its value", !fixture.shows)

        fixture.seconds = 60
        await settle(within: .seconds(2)) { contents(of: url).contains(#""popToRootSeconds": 60"#) }
        check("a change is saved", contents(of: url).contains(#""popToRootSeconds": 60"#))
        check("with every other key written back", contents(of: url).contains(#""searchScopes""#))
        let issuesBeforeEcho = reported.count
        try await Task.sleep(for: .milliseconds(400))
        check(
            "the monitor's echo of a save is not taken for an edit",
            reported.count == issuesBeforeEcho)
        check("and changes nothing", fixture.seconds == 60 && !fixture.shows)

        fixture.name = "ABC"
        // 时长足以让变更排入保存，又远短于保存自身的延迟。
        try await Task.sleep(for: .milliseconds(50))
        synced.flush()
        check("flush writes a pending change at once", contents(of: url).contains(#""ABC""#))
    }

    /// 校验 commit 回调在所有键应用后运行，其返回的 issue 并入文件 issue。
    private static func testCommit() throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        try write(#"{"general": {"showInMenuBar": false}}"#, to: url)

        let fixture = Fixture()
        var shownAtCommit: Bool?
        let moved = SettingsFileIssue.invalidEntry(.showInMenuBar, "moved")
        let repository = SettingsFileRepository(fileURL: url, bindings: bindings(fixture)) {
            shownAtCommit = fixture.shows
            return [moved]
        }
        var reported: [[SettingsFileIssue]] = []
        repository.onIssues = { reported.append($0) }
        repository.start(importing: true)
        check("commit runs once every key has applied", shownAtCommit == false)
        check("and what it reports joins the file's issues", reported == [[moved]])
    }

    /// 校验 importing=false 时不从文件读取，而是用当前设置覆盖文件。
    private static func testReplace() throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        try write(#"{"general": {"popToRootSeconds": 30}}"#, to: url)
        let fixture = Fixture()
        SettingsFileRepository(fileURL: url, bindings: bindings(fixture)).start(importing: false)
        check("replacing takes nothing from the file", fixture.seconds == 0)
        check(
            "and writes the current settings over it",
            contents(of: url).contains(#""popToRootSeconds": 0"#))
    }

    /// 校验无法读取的文件会上报 unreadable，且永远不会被替换。
    private static func testUnreadable() throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        try write("{}", to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        let repository = SettingsFileRepository(fileURL: url, bindings: bindings(Fixture()))
        var reported: [[SettingsFileIssue]] = []
        repository.onIssues = { reported.append($0) }
        repository.start(importing: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        check("a file that can't be read is reported", reported == [[.unreadable]])
        check("and never replaced", contents(of: url) == "{}")
    }

    /// 校验符号链接保持为链接，且写入落在其目标文件。
    private static func testSymlink() throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "dotfiles/settings.json")
        let link = folder.appending(path: "config/settings.json")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("{}", to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let fixture = Fixture()
        fixture.seconds = 15
        SettingsFileRepository(fileURL: link, bindings: bindings(fixture)).start(importing: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        check(
            "a symlinked file stays a symlink",
            attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        check(
            "and the write lands in its target",
            contents(of: target).contains(#""popToRootSeconds": 15"#))
    }

    // MARK: - Paths

    /// 校验内容目录解析：默认目录、~ 下目录、符号链接目标与设置存储形式。
    private static func testContentFolders() throws {
        let bundleID = "com.gearmac.settings-file-test.\(UUID().uuidString)"
        let standard = AppPaths.applicationSupport(bundleID: bundleID)
        defer { try? FileManager.default.removeItem(at: standard) }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        check(
            "no folder keeps notes in Application Support",
            AppPaths.contentFolder(nil, named: "Notes", bundleID: bundleID).lastPathComponent == "Notes")
        check(
            "a folder under ~ reads from the home folder",
            AppPaths.contentFolder("~/Dotfiles/notes", named: "Notes", bundleID: bundleID).path
                == home + "/Dotfiles/notes")
        check(
            "a relative folder is not a folder",
            !AppPaths.isFolderPath("notes") && !AppPaths.isFolderPath("~notes"))

        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "dotfiles/snippets")
        let link = folder.appending(path: "Snippets")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        check(
            "a symlinked folder resolves to its target",
            AppPaths.contentFolder(link.path, named: "Snippets", bundleID: bundleID).path
                == target.resolvingSymlinksInPath().path)

        let defaultFolder = AppPaths.contentFolder(nil, named: "Snippets", bundleID: bundleID)
        check(
            "choosing the default folder stores nothing",
            AppPaths.contentFolderSetting(for: defaultFolder, named: "Snippets", bundleID: bundleID)
                == nil)
        check(
            "choosing one in the home folder stores it under ~",
            AppPaths.contentFolderSetting(
                for: URL(filePath: home + "/Dotfiles/snippets"), named: "Snippets", bundleID: bundleID)
                == "~/Dotfiles/snippets")
    }

    /// 校验各 bundle ID 对应的 settings.json 路径。
    private static func testPaths() {
        let expected = [
            ("com.gearmac.app", "gearmac"), ("com.gearmac.app.dev", "gearmac-dev"),
            ("com.gearmac.app.beta", "gearmac-beta"), ("org.example.cast", "org.example.cast")
        ]
        for (bundleID, folder) in expected {
            check(
                "\(bundleID) keeps its settings in ~/.config/\(folder)",
                AppPaths.settingsFile(bundleID: bundleID).path.hasSuffix(
                    "/.config/\(folder)/settings.json"))
        }
    }

    // MARK: - Helpers

    /// 生成一个临时目录 URL。
    private static func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "gearmac-settings-file-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// 原子写入文本到指定 URL，必要时创建父目录。
    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// 读取 URL 的 UTF-8 文本，失败时返回空串。
    private static func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 在指定超时内轮询条件，直到成立或超时。
    private static func settle(
        within timeout: Duration = .seconds(1), until condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 断言：条件为真则打印 PASS，否则打印 FAIL 并计数。
    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
