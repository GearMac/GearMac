// 文件职责：端到端验证备份包与归档层——.gearmac 的封装/解包往返，以及格式校验、路径穿越与符号链接等防护。
// 分层：测试 harness；每个用例在临时目录中运行且用 UUID 隔离，以便并行执行。
import AppleArchive
import Foundation
import System

/// 编译随包发布的 bundle 与归档层，确保 `.gearmac` 的形态不会悄悄改变。
/// 备份归档层端到端行为的测试入口。
@main
@MainActor
struct BackupArchiveTest {
    /// 累计失败的断言数。
    static var failures = 0

    /// 记录一次断言：通过则打印 PASS，否则打印 FAIL 并累加失败数。
    static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    /// 带 UUID 后缀的临时目录；按 docs/testing.md 约定，harness 会在真实系统上并行运行。
    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-archive-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 依次运行各用例，打印总结果并按失败数决定退出码。
    static func main() {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        roundTrip(in: root)
        clipboardLines(in: root)
        noAbsolutePathsEscape(in: root)
        formatGuard(in: root)
        rejectsGarbage(in: root)
        refusesTraversal(in: root)
        refusesSymbolicLinks(in: root)
        categoriesAreComplete()
        staging()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Round trip

    /// 验证二进制、含分隔符标题、非 ASCII 文本与零字节文件都能完整封装、解包。
    static func roundTrip(in root: URL) {
        let source = root.appendingPathComponent("seal")
        let bundle = BackupBundle(root: source)
        try? bundle.prepare(BackupCategory.all)

        // 一段二进制数据，这样错误的 keyset 或只走文本的路径会表现为数据损坏。
        let png = Data((0..<200_000).map { UInt8($0 % 251) })
        try? bundle.write(png, to: bundle.clipboardImagesDirectory.appendingPathComponent("a.png"))
        _ = try? bundle.writeDocument(
            title: "Café — notes/with:separators", extension: "md", contents: "héllo\nwörld",
            in: bundle.notesDirectory)
        try? bundle.write(Data(), to: bundle.snippetsDirectory.appendingPathComponent("empty.md"))
        let manifest = BackupManifest(
            appVersion: "1.2.3", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            counts: ["clipboard": 1, "notes": 1])
        try? bundle.writeManifest(manifest)

        let archive = root.appendingPathComponent("out.gearmac")
        let opened = root.appendingPathComponent("open")
        do {
            try BackupArchive.seal(directory: source, into: archive)
            try BackupArchive.open(file: archive, into: opened)
        } catch {
            check("seal and open succeed (\(error))", false)
            return
        }

        let reopened = BackupBundle(root: opened)
        check(
            "a binary blob survives the round trip",
            (try? Data(
                contentsOf: reopened.clipboardImagesDirectory.appendingPathComponent("a.png")))
                == png)
        let notes = reopened.documents(in: reopened.notesDirectory, extension: "md")
        check("a note with separators and non-ASCII survives", notes.first?.contents == "héllo\nwörld")
        check(
            "a title's path separators never become directories",
            notes.first.map { !$0.name.contains("/") } ?? false)
        check(
            "a zero-byte file survives",
            reopened.documents(
                in: reopened.snippetsDirectory, extension: "md"
            ).first?.contents == "")
        let decoded = try? reopened.readManifest()
        check("the manifest round trips", decoded == manifest)
        check("an absent category reads as absent", decoded?.categories == [.clipboard, .notes])
        check("a present category keeps its count", decoded?.count(.clipboard) == 1)
        check("an absent category counts zero", decoded?.count(.snippets) == 0)

        // 归属关系不应随归档传递：解出的文件属于打开它的人。
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: reopened.clipboardImagesDirectory.appendingPathComponent("a.png").path)
        check(
            "the extracted file is owned by the current user",
            (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value == getuid())
    }

    // MARK: - Clipboard

    /// 验证剪贴板条目经 JSONL 往返不变，且每条记录始终占一行。
    static func clipboardLines(in root: URL) {
        let bundle = BackupBundle(root: root.appendingPathComponent("clips"))
        try? bundle.prepare([.clipboard])
        let items = [
            BackupClipboardItem(
                kind: .text, text: "one\ntwo\nthree", imageName: nil,
                createdAt: Date(timeIntervalSince1970: 10), sourceBundleID: "com.apple.Safari",
                pinnedAt: nil),
            BackupClipboardItem(
                kind: .text, text: "carriage\r\nreturn", imageName: nil,
                createdAt: Date(timeIntervalSince1970: 20), sourceBundleID: nil,
                pinnedAt: Date(timeIntervalSince1970: 25)),
            BackupClipboardItem(
                kind: .image, text: nil, imageName: "b.png",
                createdAt: Date(timeIntervalSince1970: 30), sourceBundleID: nil, pinnedAt: nil)
        ]
        if let writer = try? bundle.clipboardWriter() {
            for item in items { try? writer.write(item) }
        }

        check("every clip round trips through JSONL", Array(bundle.clipboardItems()) == items)

        // 按行切分所依赖的不变量：剪贴板内容中的换行会被转义，绝不会是原始换行。
        let raw = (try? Data(contentsOf: bundle.clipboardItemsURL)) ?? Data()
        check(
            "one line per clip, whatever the clip contains",
            raw.split(separator: 0x0A, omittingEmptySubsequences: true).count == items.count)
    }

    /// 与 settings-backup-test 的 `snippetsEnabled` 检查对应：这个文件会离开本机。
    static func noAbsolutePathsEscape(in root: URL) {
        let bundle = BackupBundle(root: root.appendingPathComponent("paths"))
        try? bundle.prepare([.clipboard])
        let item = BackupClipboardItem(
            kind: .image, text: nil, imageName: "c.png", createdAt: Date(), sourceBundleID: nil,
            pinnedAt: nil)
        if let writer = try? bundle.clipboardWriter() { try? writer.write(item) }
        let raw = (try? Data(contentsOf: bundle.clipboardItemsURL)) ?? Data()
        let text = String(bytes: raw, encoding: .utf8) ?? ""
        check("no home directory leaks into the file", !text.contains("/Users"))
        check("no image path leaks into the file", !text.contains("/Library"))
    }

    // MARK: - Guards

    /// 验证版本号不匹配的 manifest 会被同一种错误拒绝。
    static func formatGuard(in root: URL) {
        for offset in [-1, 1] {
            let bundle = BackupBundle(root: root.appendingPathComponent("format\(offset)"))
            try? bundle.prepare([])
            var manifest = BackupManifest(appVersion: "1", createdAt: Date(), counts: [:])
            manifest.format = BackupManifest.currentFormat + offset
            try? bundle.writeManifest(manifest)
            do {
                _ = try bundle.readManifest()
                check("a format of \(manifest.format) is refused", false)
            } catch {
                check(
                    "a format of \(manifest.format) is refused by the same error",
                    error == .unsupportedFormat(found: manifest.format))
                check(
                    "the refusal names the format it found",
                    error.errorDescription?.contains("\(manifest.format)") == true)
            }
        }
    }

    /// 验证非归档文件与缺少 manifest 的包都会被拒绝。
    static func rejectsGarbage(in root: URL) {
        let file = root.appendingPathComponent("garbage.gearmac")
        try? Data("not an archive".utf8).write(to: file)
        let into = root.appendingPathComponent("garbage-out")
        do {
            try BackupArchive.open(file: file, into: into)
            check("a non-archive is refused", false)
        } catch {
            check("a non-archive is refused", true)
        }

        let empty = BackupBundle(root: root.appendingPathComponent("empty"))
        try? empty.prepare([])
        do {
            _ = try empty.readManifest()
            check("a bundle with no manifest is refused", false)
        } catch {
            check("a bundle with no manifest is refused", error == .unreadable)
        }
    }

    /// 恶意归档不得写到调用方指定目录之外。
    static func refusesTraversal(in root: URL) {
        // 逐个头手工构造：`writeDirectoryContents` 会拒绝输出这里需要的 `..` 路径。
        let archive = root.appendingPathComponent("evil.gearmac")
        let payload = Data("escaped".utf8)
        guard
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else {
            check("the traversal fixture can be built", false)
            return
        }
        do {
            try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
                let header = ArchiveHeader()
                header.append(
                    .uint(
                        key: ArchiveHeader.FieldKey("TYP"),
                        value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
                header.append(
                    .string(key: ArchiveHeader.FieldKey("PAT"), value: "../escape.txt"))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o644))
                header.append(
                    .blob(key: ArchiveHeader.FieldKey("DAT"), size: UInt64(payload.count)))
                try encoder.writeHeader(header)
                try payload.withUnsafeBytes { buffer in
                    try encoder.writeBlob(key: ArchiveHeader.FieldKey("DAT"), from: buffer)
                }
            }
            try compressor.close()
            try destination.close()
        } catch {
            check("the traversal fixture can be built (\(error))", false)
            return
        }

        let into = root.appendingPathComponent("evil-out", isDirectory: true)
        try? BackupArchive.open(file: archive, into: into)
        let escaped = root.appendingPathComponent("escape.txt")
        check(
            "an entry naming `..` never lands outside the destination",
            !FileManager.default.fileExists(atPath: escaped.path))
    }

    /// 链接条目根本不写 `..`，但顺着它读取会离开解包目录。
    static func refusesSymbolicLinks(in root: URL) {
        let archive = root.appendingPathComponent("linked.gearmac")
        guard
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else {
            check("the symlink fixture can be built", false)
            return
        }
        do {
            try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
                let header = ArchiveHeader()
                // 76 即 `L`；Swift overlay 没有为符号链接指定可用于表示它的枚举 case。
                header.append(.uint(key: ArchiveHeader.FieldKey("TYP"), value: 76))
                header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: "notes"))
                header.append(
                    .string(key: ArchiveHeader.FieldKey("LNK"), value: root.path))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o777))
                try encoder.writeHeader(header)
            }
            try compressor.close()
            try destination.close()
        } catch {
            check("the symlink fixture can be built (\(error))", false)
            return
        }

        let into = root.appendingPathComponent("linked-out", isDirectory: true)
        do {
            try BackupArchive.open(file: archive, into: into)
            check("an archive carrying a symlink is refused", false)
        } catch {
            check(
                "an archive carrying a symlink is refused",
                error as? BackupArchive.ArchiveError == .cannotRead)
        }
    }

    // MARK: - Declarations

    /// 用于在新增 case 却忘了补布局或选择器时报错的警戒线。
    static func categoriesAreComplete() {
        var subpaths: Set<String> = []
        for category in BackupCategory.allCases {
            let descriptor = category.descriptor
            check("\(category.rawValue) has a label", !descriptor.label(.english).isEmpty)
            check("\(category.rawValue) has a symbol", !descriptor.symbol.isEmpty)
            if !descriptor.subpath.isEmpty {
                check(
                    "\(category.rawValue)'s subpath is its own",
                    subpaths.insert(descriptor.subpath)
                        .inserted)
            }
        }
        check("every case is offered", BackupCategory.all.count == BackupCategory.allCases.count)
        check(
            "ordering follows declaration order",
            BackupCategory.ordered(BackupCategory.all) == BackupCategory.allCases)
    }

    /// 验证临时暂存目录的创建与丢弃行为。
    static func staging() {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        guard let staging = try? BackupStaging(base: base) else {
            check("staging is created on init", false)
            return
        }
        check(
            "staging is created on init",
            FileManager.default.fileExists(atPath: staging.root.path))
        staging.discard()
        check(
            "discard removes the tree",
            !FileManager.default.fileExists(atPath: staging.root.path))
        staging.discard()
        check("discard is idempotent", true)
    }
}
