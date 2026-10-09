// 文件职责：验证扩展清理（ExtensionCleanup）与目录/可执行权限恢复（ExtensionCatalog）行为：只清扫本应用的工作区，只清理未安装扩展的残留，并恢复可执行文件权限。
// 分层：测试 harness；通过注入 ExtensionCleanup.Roots 使用临时目录，绝不触碰真实的 Bundle.main 安装路径。

import Foundation

@main
@MainActor
struct ExtensionCleanupTests {
    static var failures = 0

    /// 断言：条件为假时累计失败并打印 FAIL，否则打印 PASS。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    // MARK: - Fixtures

    /// `Roots` 由外部注入，因此绝不会读取 `Bundle.main`（真实安装路径）。
    static func makeRoots() -> (ExtensionCleanup.Roots, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        let roots = ExtensionCleanup.Roots(
            temp: base.appendingPathComponent("temp", isDirectory: true),
            support: base.appendingPathComponent("support", isDirectory: true),
            data: base.appendingPathComponent("data", isDirectory: true))
        for url in [roots.temp, roots.support, roots.data] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (roots, base)
    }

    /// 在 parent 下创建 name 目录，并写入 bytes 字节的 payload.bin 占位文件。
    static func makeDirectory(_ parent: URL, _ name: String, bytes: Int = 1024) {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? Data(repeating: 0, count: bytes).write(to: url.appendingPathComponent("payload.bin"))
    }

    /// 在 parent 下创建 name 文件，内容为 bytes 字节的零填充。
    static func makeFile(_ parent: URL, _ name: String, bytes: Int = 512) {
        try? Data(repeating: 0, count: bytes).write(to: parent.appendingPathComponent(name))
    }

    /// 判断 url 下是否已存在名为 name 的条目。
    static func exists(_ url: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    // MARK: - Cases

    /// 工作区按名称归属我们：临时根目录中的其他内容都属于别的进程。
    static func sweepTakesOnlyOurWorkspaces() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.temp, "gearmac-install-ABC123")
        makeDirectory(roots.temp, "gearmac-install-DEF456")
        makeDirectory(roots.temp, "keep-me")
        makeFile(roots.temp, "unrelated.txt")

        ExtensionCleanup.sweepWorkspaces(in: roots.temp)

        expect(!exists(roots.temp, "gearmac-install-ABC123"), "a stale workspace is swept")
        expect(!exists(roots.temp, "gearmac-install-DEF456"), "every stale workspace is swept")
        expect(exists(roots.temp, "keep-me"), "another app's directory survives")
        expect(exists(roots.temp, "unrelated.txt"), "an unrelated file survives")
    }

    /// 已安装集合是唯一权威：它列出的都保留，其余一律视为残留。
    static func cleanTakesOnlyOrphans() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, "kill-process")
        makeDirectory(roots.support, "speedtest")
        makeFile(roots.data, "kill-process.json")
        makeFile(roots.data, "speedtest.json")
        makeDirectory(roots.temp, "gearmac-install-STRAY")

        let report = ExtensionCleanup.clean(installed: ["kill-process"], in: roots)

        expect(exists(roots.support, "kill-process"), "an installed extension keeps its scratch dir")
        expect(exists(roots.data, "kill-process.json"), "an installed extension keeps its data")
        expect(!exists(roots.support, "speedtest"), "an orphaned scratch dir goes")
        expect(!exists(roots.data, "speedtest.json"), "an orphaned data file goes")
        expect(!exists(roots.temp, "gearmac-install-STRAY"), "a stray workspace goes")
        expect(report.items == 3, "the report counts every removal: \(report.items)")
        expect(report.bytes > 0, "the report measures what it freed: \(report.bytes)")
    }

    /// npm scope 名称在各处必须展平成同一形式，否则它的文件会变成孤儿。
    static func scopedNamesMatchTheirDirectories() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, ExtensionCatalog.safeName("@scope/thing"))
        makeFile(roots.data, "\(ExtensionCatalog.safeName("@scope/thing")).json")

        let report = ExtensionCleanup.clean(installed: ["@scope/thing"], in: roots)

        expect(report.isEmpty, "a scoped name matches its own directory: \(report.items) removed")
        expect(exists(roots.support, "scope-thing"), "the scoped scratch dir survives")
    }

    /// 按钮承诺的回收量必须与按下后实际清理的结果一致。
    static func reclaimableMatchesClean() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        makeDirectory(roots.support, "gone-one")
        makeDirectory(roots.support, "gone-two")
        makeFile(roots.data, "gone-one.json")

        let predicted = ExtensionCleanup.reclaimable(installed: [], in: roots)
        let actual = ExtensionCleanup.clean(installed: [], in: roots)

        expect(predicted.items == 3, "reclaimable counts every stray: \(predicted.items)")
        expect(predicted == actual, "reclaimable predicts clean exactly")
    }

    /// 无事可做不算失败，从未创建的根目录同样不算失败。
    static func emptyAndMissingRootsAreSafe() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        expect(ExtensionCleanup.clean(installed: [], in: roots).isEmpty, "empty roots report nothing")

        let missing = ExtensionCleanup.Roots(
            temp: base.appendingPathComponent("nope-temp"),
            support: base.appendingPathComponent("nope-support"),
            data: base.appendingPathComponent("nope-data"))
        expect(ExtensionCleanup.clean(installed: [], in: missing).isEmpty, "missing roots report nothing")
        ExtensionCleanup.sweepWorkspaces(in: missing.temp)
    }

    /// 安装器与清扫必须对同一名称达成一致，这正是名称由同一个类型统一提供的原因。
    static func workspaceIsSweptByItsOwnPrefix() {
        let (roots, base) = makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        let workspace = ExtensionCleanup.workspace(in: roots.temp)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        ExtensionCleanup.sweepWorkspaces(in: roots.temp)

        expect(
            !FileManager.default.fileExists(atPath: workspace.path),
            "a workspace the installer would make is one the sweep finds")
    }

    /// 校验恢复可执行权限的流程：Mach-O 二进制与脚本会被修复，普通资源保持数据文件权限。
    static func executableAssetsAreRestored() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-mode-test-\(UUID().uuidString)", isDirectory: true)
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let binary = assets.appendingPathComponent("helper")
        let script = assets.appendingPathComponent("script")
        let text = assets.appendingPathComponent("readme")
        try? Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: binary)
        try? Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        try? Data("ordinary asset".utf8).write(to: text)
        for file in [binary, script, text] {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: file.path)
        }

        try? ExtensionCatalog.restoreExecutablePermissions(in: base)

        expect(FileManager.default.isExecutableFile(atPath: binary.path), "a Mach-O helper is repaired")
        expect(FileManager.default.isExecutableFile(atPath: script.path), "a script helper is repaired")
        expect(!FileManager.default.isExecutableFile(atPath: text.path), "an ordinary asset stays data")
    }

    /// Raycast Beta 把扩展放在 `raycast-x` 下；只检查 `raycast` 会漏掉它。
    static func bothRaycastChannelsAreSearched() {
        let roots = ExtensionCatalog.raycastExtensionRoots().map(\.path)
        expect(roots.count == 2, "both channels are searched: \(roots.count)")
        expect(
            roots.contains { $0.hasSuffix("/.config/raycast/extensions") },
            "the stable channel is searched")
        expect(
            roots.contains { $0.hasSuffix("/.config/raycast-x/extensions") },
            "the beta channel is searched")
    }

    /// 依次运行全部用例，最后按失败数决定退出码。
    static func main() {
        bothRaycastChannelsAreSearched()
        sweepTakesOnlyOurWorkspaces()
        cleanTakesOnlyOrphans()
        scopedNamesMatchTheirDirectories()
        reclaimableMatchesClean()
        emptyAndMissingRootsAreSafe()
        workspaceIsSweptByItsOwnPrefix()
        executableAssetsAreRestored()

        print(failures == 0 ? "Extension cleanup tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
