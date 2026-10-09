// 文件职责：校验 ExtensionVersionStore 依据安装时记录的版本判断谁落后、遗忘单个安装记录，以及版本记录写入文件后的持久化。
// 分层：测试 harness；以临时文件承载状态，不读写本机上真实的扩展文件，仅通过进程退出码报告结果。
import Foundation

/// 更新检查依据安装时记录的版本所能得出的结论。
@main
@MainActor
struct ExtensionVersionStoreTests {
    static var failures = 0
    static var passes = 0

    /// 入口：依次运行比对、遗忘与持久化三组检查，并按失败数设置退出码。
    static func main() {
        reconciling()
        forgetting()
        persisting()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// 校验与商店最新列表比对时谁的 commit 更新才算落后，以及未跟踪与无版本条目的处理。
    static func reconciling() {
        print("\n# reconciling")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionVersionStore(fileURL: file)
        store.record("a1", for: "current")
        store.record("a1", for: "behind")
        store.record(nil, for: "imported")

        let latest = [
            listing("current", commit: "a1"), listing("behind", commit: "b2"),
            listing("imported", commit: "c3"), listing("untracked", commit: "d4"),
            listing("unversioned", commit: nil)
        ]
        let behind = store.reconcile(with: latest).map(\.name)
        check("a newer commit is behind", behind == ["behind"])
        check("an import adopts the store's version", store.reconcile(with: latest).map(\.name) == ["behind"])

        store.record(nil, for: "unversioned")
        check(
            "a listing without a commit never reads as behind",
            store.reconcile(with: [listing("unversioned", commit: nil)]).isEmpty)
        check(
            "an untracked install is never checked",
            !store.tracked.contains("untracked"))
    }

    /// 校验被遗忘的安装不再被跟踪，也不会被报告为落后。
    static func forgetting() {
        print("\n# forgetting")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionVersionStore(fileURL: file)
        store.record("a1", for: "github")
        store.forget("github")
        check("a forgotten install leaves tracking", !store.tracked.contains("github"))
        check(
            "and is never reported behind",
            store.reconcile(with: [listing("github", commit: "b2")]).isEmpty)
    }

    /// 校验版本记录写入文件后能跨实例读出，且文件不存在时从空状态开始。
    static func persisting() {
        print("\n# persisting")
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        ExtensionVersionStore(fileURL: file).record("a1", for: "coffee")
        let reopened = ExtensionVersionStore(fileURL: file)
        check("a recorded version survives a relaunch", reopened.tracked == ["coffee"])
        check(
            "and keeps its commit",
            reopened.reconcile(with: [listing("coffee", commit: "b2")]).map(\.name) == ["coffee"])
        check(
            "a missing file starts empty",
            ExtensionVersionStore(fileURL: makeFile()).tracked.isEmpty)
    }

    // MARK: - 辅助方法

    /// 独立的临时文件路径，不会碰触本机上真实的扩展文件。
    static func makeFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-version-test-\(UUID().uuidString).json")
    }

    /// 构造一条只用于比对的最小 ExtensionListing，其余字段填占位值。
    static func listing(_ name: String, commit: String?) -> ExtensionListing {
        ExtensionListing(
            id: name, name: name, title: name, summary: "", author: "", lightIconURL: nil,
            darkIconURL: nil, commandCount: 1, downloadCount: nil,
            downloadURL: URL(fileURLWithPath: "/dev/null"), commitSHA: commit)
    }

    /// 记录一次断言：通过则累加通过数，失败则累加失败数并打印标签。
    static func check(_ description: String, _ condition: Bool) {
        if condition {
            passes += 1
            print("PASS  \(description)")
        } else {
            failures += 1
            print("FAIL  \(description)")
        }
    }
}
