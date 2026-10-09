// 文件职责：验证 ExtensionCommandMetadataStore 的读写往返、失败计数与回退、错误清除、按扩展删除，以及损坏文件的兜底。
// 分层：测试 harness；每个用例使用独立临时 JSON 文件，绝不触碰机器上的真实扩展数据。

import Foundation

@main
@MainActor
struct ExtensionCommandMetadataTests {
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

    /// 每个用例专属的临时状态文件，绝不使用机器上的真实扩展文件。
    static func makeFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-metadata-test-\(UUID().uuidString).json")
    }

    // MARK: - Cases

    /// 写入通过同一文件上的第二个 store 读回，验证往返一致性。
    static func writesRoundTrip() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let first = ExtensionCommandMetadataStore(fileURL: file)
        first.setSubtitle("Tick 1", extension: "ticklab", command: "tick")
        first.setBackgroundEnabled(true, extension: "ticklab", command: "tick")
        first.flush()

        let second = ExtensionCommandMetadataStore(fileURL: file)
        let metadata = second.metadata(extension: "ticklab", command: "tick")
        expect(metadata.subtitle == "Tick 1", "the subtitle round-trips")
        expect(metadata.backgroundEnabled, "the flag round-trips")
        expect(
            second.metadata(extension: "ticklab", command: "other") == ExtensionCommandMetadata(),
            "an unwritten command reads as defaults")
    }

    /// 失败会累加计数以便策略退避；一次成功则连同计数一起清除错误。
    static func resultsTrackTheFailureRun() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        let now = Date()
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: now)
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: now)
        var metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.consecutiveFailures == 2, "consecutive failures accumulate")
        expect(metadata.lastError == "Boom.", "the last error is kept")

        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: true, error: nil, now: now)
        metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.consecutiveFailures == 0, "a success resets the count")
        expect(metadata.lastError == nil, "a success clears the error")
        expect(metadata.lastRun == now, "the run is stamped")
    }

    /// 禁用会一并清除告警，使其不会比引发它的调度存活更久。
    static func clearingTheErrorRetiresTheBackoff() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        store.recordBackgroundResult(
            extension: "ticklab", command: "tick", success: false, error: "Boom.", now: Date())
        store.clearBackgroundError(extension: "ticklab", command: "tick")
        let metadata = store.metadata(extension: "ticklab", command: "tick")
        expect(metadata.lastError == nil, "the error is gone")
        expect(metadata.consecutiveFailures == 0, "the backoff is gone with it")
    }

    /// 卸载会带走该扩展的记录，且仅限它自己的记录。
    static func removeAllDropsOneExtension() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExtensionCommandMetadataStore(fileURL: file)
        store.activateBackgroundRefresh(extension: "ticklab", command: "tick", now: Date())
        store.activateBackgroundRefresh(extension: "coffee", command: "status", now: Date())
        store.removeAll(extension: "ticklab")
        store.flush()

        let reloaded = ExtensionCommandMetadataStore(fileURL: file)
        expect(
            !reloaded.metadata(extension: "ticklab", command: "tick").backgroundEnabled,
            "the uninstalled extension's record is gone")
        expect(
            reloaded.metadata(extension: "coffee", command: "status").backgroundEnabled,
            "the other extension keeps its own")
    }

    /// 垃圾内容应退化为空 store 而不是崩溃；下一次 flush 会修复文件。
    static func garbageStaysSafe() {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try? "not json at all".write(to: file, atomically: true, encoding: .utf8)

        let store = ExtensionCommandMetadataStore(fileURL: file)
        expect(
            store.metadata(extension: "broken", command: "x") == ExtensionCommandMetadata(),
            "a corrupt file reads as defaults")
    }

    /// 依次运行全部用例，最后按失败数决定退出码。
    static func main() {
        writesRoundTrip()
        resultsTrackTheFailureRun()
        clearingTheErrorRetiresTheBackoff()
        removeAllDropsOneExtension()
        garbageStaysSafe()

        print(failures == 0 ? "Extension command metadata tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
