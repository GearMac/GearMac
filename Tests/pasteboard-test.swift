// 文件职责：独立验证剪贴板的文件捕获与写回：读取各种 file flavour、按上限截断、拒绝易失或缺失文件，以及把文件条目写回剪贴板。
// 分层：测试 harness；直接编译真实源码（ClipboardManager、PasteboardFiles、Paster、ClipboardStore）。
// 每个用例都使用 `NSPasteboard.withUniqueName()`：写入 `.general` 会落进用户正在运行的 GearMac，成为一次真实复制。
import AppKit

/// 验证剪贴板文件捕获与写回的测试入口。
@main
@MainActor
struct PasteboardTests {
    static var failures = 0
    static var passes = 0
    static let cap = ClipboardManager.maxCapturedFiles

    /// 依次运行全部剪贴板用例并汇总结果。
    static func main() {
        finderCopyReadsAsAFileNotItsName()
        everyFileFlavourIsRead()
        multipleFilesReadNewestLast()
        linksAndTextAreNotFiles()
        volatileAndMissingFilesFallThrough()
        theBatchIsCapped()
        rejectedFilesDoNotCountTowardTheCap()
        theBoundedReaderStopsAtItsLimit()
        aModernFileURLSuppressesTheLegacyFallback()
        fileEntriesWriteBackAsFiles()
        aVanishedFileWritesNothing()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - 读取
    /// 同一个读取器覆盖每种 flavour：命名了文件的剪贴板绝不能退化读取它的文件名。
    static func everyFileFlavourIsRead() {
        withScratch { dir in
            let file = dir.appendingPathComponent("GearMac-Settings-2026-08-20.json")
            try? Data("{}".utf8).write(to: file)

            // Finder 的真实形态：同一个 item 同时携带 URL 和显示名。
            let item = NSPasteboardItem()
            item.setData(file.dataRepresentation, forType: .fileURL)
            item.setString(file.lastPathComponent, forType: .string)
            let single = board()
            single.writeObjects([item])
            expect(
                PasteboardFiles.urls(on: single) == [file],
                "a URL and a display name on one item reads as the file")

            // 有些剪贴板把 URL 作为字符串而非 UTF-8 数据携带。
            let asString = NSPasteboardItem()
            asString.setString(file.absoluteString, forType: .fileURL)
            let stringBoard = board()
            stringBoard.writeObjects([asString])
            expect(
                PasteboardFiles.urls(on: stringBoard) == [file],
                "and so does one carrying the URL as a string")

            // UTI 之前的旧 flavour，仍有许多 app 在写。
            let legacy = board()
            legacy.declareTypes([.init("NSFilenamesPboardType")], owner: nil)
            legacy.setPropertyList([file.path], forType: .init("NSFilenamesPboardType"))
            expect(
                PasteboardFiles.urls(on: legacy) == [file],
                "the legacy filenames flavour is read when no file URL is present")

            let text = board()
            text.declareTypes([.string], owner: nil)
            text.setString("GearMac-Settings-2026-08-20.json", forType: .string)
            expect(
                PasteboardFiles.urls(on: text).isEmpty,
                "a bare file name is text, not a file")
        }
    }

    /// 被报告过的缺陷：Finder 会把显示名放到 `public.file-url` 旁边的 `.string` 上。
    static func finderCopyReadsAsAFileNotItsName() {
        withScratch { dir in
            let file = dir.appendingPathComponent("Screen Recording.mov")
            try? Data("movie".utf8).write(to: file)
            let pb = board()
            pb.declareTypes([.fileURL, .string], owner: nil)
            pb.setData(file.dataRepresentation, forType: .fileURL)
            pb.setString("Screen Recording.mov", forType: .string)

            expect(
                ClipboardManager.fileURLs(on: pb, volatileRoots: []) == [file.path],
                "a Finder copy reads as its path, never as its name")
        }
    }

    static func multipleFilesReadNewestLast() {
        withScratch { dir in
            let urls = ["a.txt", "b.txt", "c.txt"].map { name -> URL in
                let url = dir.appendingPathComponent(name)
                try? Data(name.utf8).write(to: url)
                return url
            }
            let pb = board()
            pb.writeObjects(urls as [NSURL])
            // 反序返回，这样按顺序插入时最先复制的文件位于历史最前。
            expect(
                ClipboardManager.fileURLs(on: pb, volatileRoots: []) == urls.map(\.path).reversed(),
                "three files read back reversed")
        }
    }

    /// 只有真正的文件 URL 才算数，因此复制的链接仍只是链接。
    static func linksAndTextAreNotFiles() {
        let pb = board()
        pb.declareTypes([.string], owner: nil)
        pb.setString("https://example.com/report.pdf", forType: .string)
        expect(ClipboardManager.fileURLs(on: pb) == nil, "an http URL is not a file")

        let plain = board()
        plain.declareTypes([.string], owner: nil)
        plain.setString("just some prose", forType: .string)
        expect(ClipboardManager.fileURLs(on: plain) == nil, "and neither is prose")

        expect(ClipboardManager.fileURLs(on: board()) == nil, "an empty pasteboard reads as nil")
    }

    /// 若 app 在更好的内联内容旁同时放了一个临时文件，必须保留内联内容。
    static func volatileAndMissingFilesFallThrough() {
        let temp = URL(fileURLWithPath: "/private/tmp/gearmac-volatile-\(UUID().uuidString).png")
        try? Data("x".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let pb = board()
        pb.writeObjects([temp as NSURL])
        expect(
            ClipboardManager.fileURLs(on: pb) == nil,
            "a file under /private/tmp is not durable, against the shipped roots")

        let gone = board()
        gone.writeObjects([URL(fileURLWithPath: "/nowhere/\(UUID().uuidString).txt") as NSURL])
        expect(ClipboardManager.fileURLs(on: gone) == nil, "and neither is one that is not there")
    }

    static func theBatchIsCapped() {
        withScratch { dir in
            let urls = (0..<40).map { index -> URL in
                let url = dir.appendingPathComponent("f\(index).txt")
                try? Data("x".utf8).write(to: url)
                return url
            }
            for legacy in [false, true] {
                for count in [1, cap - 1, cap, cap + 1, 40] {
                    let pb = fileBoard(Array(urls.prefix(count)), legacy: legacy)
                    defer { pb.releaseGlobally() }
                    expect(
                        ClipboardManager.fileURLs(on: pb, volatileRoots: [])
                            == Array(urls.prefix(min(count, cap)).map(\.path).reversed()),
                        "the first durable files stay reversed at the \(count)-file boundary (legacy: \(legacy))"
                    )
                }
            }
        }
    }

    static func rejectedFilesDoNotCountTowardTheCap() {
        withScratch { dir in
            let volatile = dir.appendingPathComponent("volatile", isDirectory: true)
            let staged = volatile.appendingPathComponent("staged.txt")
            let missing = dir.appendingPathComponent("missing.txt")
            let durableLink = dir.appendingPathComponent("durable-link")
            let volatileLink = dir.appendingPathComponent("volatile-link")
            let brokenLink = dir.appendingPathComponent("broken-link")
            let files = (0..<40).map { dir.appendingPathComponent("f\($0).txt") }
            do {
                try FileManager.default.createDirectory(at: volatile, withIntermediateDirectories: true)
                try Data("staged".utf8).write(to: staged)
                for file in files { try Data("file".utf8).write(to: file) }
                try FileManager.default.createSymbolicLink(at: durableLink, withDestinationURL: files[0])
                try FileManager.default.createSymbolicLink(at: volatileLink, withDestinationURL: staged)
                try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: missing)
            } catch {
                fail("cannot create file capture fixtures: \(error)")
                return
            }
            var root = volatile.resolvingSymlinksInPath().path
            if root.hasPrefix("/private/") { root.removeFirst("/private".count) }
            let rejected = [missing, staged, volatileLink, brokenLink]
            let accepted = [durableLink, files[0]] + files
            let mixed = Array(repeating: missing, count: 40) + rejected + accepted
            for legacy in [false, true] {
                let empty = fileBoard(rejected, legacy: legacy)
                defer { empty.releaseGlobally() }
                expect(
                    ClipboardManager.fileURLs(on: empty, volatileRoots: [root + "/"]) == nil,
                    "missing, volatile and broken targets fall through (legacy: \(legacy))")
                let pb = fileBoard(mixed, legacy: legacy)
                defer { pb.releaseGlobally() }
                expect(
                    ClipboardManager.fileURLs(on: pb, volatileRoots: [root + "/"])
                        == Array(accepted.prefix(cap).map(\.standardizedFileURL.path).reversed()),
                    "rejected files do not consume the cap; links and duplicates keep their order (legacy: \(legacy))"
                )
            }
        }
    }

    /// 限制现在位于读取器内部，因此上限和判定函数都必须精确地停下。
    static func theBoundedReaderStopsAtItsLimit() {
        let urls = (0..<100).map { URL(fileURLWithPath: "/fixture/\($0).txt") }
        let pb = fileBoard(urls, legacy: false)
        defer { pb.releaseGlobally() }
        expect(PasteboardFiles.urls(on: pb) == urls, "the attachment reader stays uncapped")
        for limit in [-1, 0, 1, cap - 1, cap, cap + 1, 100, Int.max] {
            var visited: [URL] = []
            let matched = PasteboardFiles.urls(on: pb, limit: limit) { url in
                visited.append(url)
                return true
            }
            let expected = Array(urls.prefix(max(0, limit)))
            expect(matched == expected, "a limit of \(limit) bounds the result in board order")
            expect(visited == expected, "and nothing is decoded past a limit of \(limit)")
        }
        var visited: [URL] = []
        let afterRejections = PasteboardFiles.urls(on: pb, limit: cap) { url in
            visited.append(url)
            return visited.count > 40
        }
        expect(
            afterRejections == Array(urls[40..<(40 + cap)]),
            "rejected URLs do not consume the limit")
        expect(
            visited == Array(urls.prefix(40 + cap)),
            "and every URL is tested once, with testing stopping at the limit")
    }

    /// 以现代 flavour 命名文件的剪贴板绝不能回退到旧 flavour，即使我们拒绝了它。
    static func aModernFileURLSuppressesTheLegacyFallback() {
        withScratch { dir in
            let legacy = dir.appendingPathComponent("legacy.txt")
            let modern = dir.appendingPathComponent("modern.txt")
            let missing = dir.appendingPathComponent("missing.txt")
            try? Data("legacy".utf8).write(to: legacy)
            try? Data("modern".utf8).write(to: modern)
            for url in [modern, missing, URL(string: "https://example.com/file")!] {
                let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
                let pb = board()
                defer { pb.releaseGlobally() }
                pb.declareTypes([type, .fileURL], owner: nil)
                pb.setPropertyList([legacy.path], forType: type)
                pb.setData(url.dataRepresentation, forType: .fileURL)

                let named = url.isFileURL ? [url] : [legacy]
                expect(
                    PasteboardFiles.urls(on: pb) == named,
                    "a modern file URL outranks the legacy paths beside it")
                var visited: [URL] = []
                let rejected = PasteboardFiles.urls(on: pb, limit: cap) { candidate in
                    visited.append(candidate)
                    return false
                }
                expect(rejected.isEmpty, "rejecting every candidate names no file")
                expect(visited == named, "and a rejected modern URL still suppresses the fallback")
                expect(
                    ClipboardManager.fileURLs(on: pb, volatileRoots: [])
                        == (url == missing ? nil : named.map(\.path)),
                    "so a missing modern file never captures the legacy path instead")
            }
        }
    }

    static func fileBoard(_ urls: [URL], legacy: Bool) -> NSPasteboard {
        let pb = board()
        if legacy {
            let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            pb.declareTypes([type], owner: nil)
            expect(pb.setPropertyList(urls.map(\.path), forType: type), "legacy fixture is written")
        } else {
            expect(pb.writeObjects(urls as [NSURL]), "file URL fixture is written")
        }
        return pb
    }

    // MARK: - 写入

    /// 往返验证：Finder 交给我们的内容以文件形式写回，并附带文本形式的路径。
    static func fileEntriesWriteBackAsFiles() {
        withScratch { dir in
            let file = dir.appendingPathComponent("report.pdf")
            try? Data("pdf".utf8).write(to: file)
            let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
            store.addFiles([file.path], sourceBundleID: nil)
            let pb = board()

            expect(Paster.write(store.items[0], store: store, to: pb), "a present file writes")
            let read = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
            expect(read?.first?.path == file.path, "and reads back as the same file URL")
            expect(pb.string(forType: .string) == file.path, "with the path as text, not the name")
            expect(
                pb.types?.contains(ClipboardManager.internalType) == true,
                "marked, so the poller skips our own write")
        }
    }

    static func aVanishedFileWritesNothing() {
        withScratch { dir in
            let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
            store.addFiles(["/nowhere/\(UUID().uuidString).txt"], sourceBundleID: nil)
            let pb = board()
            pb.declareTypes([.string], owner: nil)
            pb.setString("untouched", forType: .string)

            expect(!Paster.write(store.items[0], store: store, to: pb), "a vanished file refuses")
            expect(pb.string(forType: .string) == "untouched", "and leaves the pasteboard alone")
        }
    }

    // MARK: - 测试脚手架

    /// 为每个用例创建一个具名、隔离的剪贴板。
    static func board() -> NSPasteboard { NSPasteboard.withUniqueName() }

    /// 在临时目录中执行用例，结束后清理。
    static func withScratch(_ body: (URL) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gearmac-pasteboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        body(dir)
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            fail(message)
        }
    }

    static func fail(_ message: String) {
        failures += 1
        print("FAIL: \(message)")
    }
}

// MARK: - 为已发布源码触达但本 harness 未覆盖的依赖所提供的桩实现

/// 测试桩：仅提供已发布源码在本 harness 中触达的设置项。
@MainActor
final class AppSettings {
    var clipboardDisabledApps: Set<String> = []
}

/// 测试桩：辅助功能权限探测固定返回 false。
enum Permissions {
    static func ensureAccessibility() -> Bool { false }
}

/// 测试桩：通知令牌，忽略其观察者与通知中心参数。
final class NotificationToken {
    init(_ observer: Any, center: NotificationCenter) {}
}
