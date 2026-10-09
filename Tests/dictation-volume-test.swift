// 文件职责：Dictation 音量闪避（DictationAudioDucker）的崩溃恢复测试，覆盖设备音量写入、快照、用户改音量与取消。
// 分层：测试 harness；用假的音量读写与临时快照文件驱动真实的 DictationAudioDucker。

import Foundation

/// 独立可执行测试入口：驱动音量闪避的恢复、用户改动、设备切换与故障路径。
@main
struct DictationVolumeTest {
    /// 测试夹具：模拟一个可读写音量、可注入读写回调与写失败的输出设备。
    @MainActor
    private final class Fixture {
        let uid: String
        var volume: Float
        var writes: [Float] = []
        var saved: [DictationVolumeSnapshot] = []
        var onRead: (() -> Void)?
        var onWrite: (() -> Void)?
        var failsNextWrite = false

        init(uid: String = "speakers", volume: Float = 0.5) {
            self.uid = uid
            self.volume = volume
        }

        /// 构造该设备的输出描述，写入前校验恢复快照已落盘。
        func output(fileURL: URL) -> DictationAudioDucker.Output {
            DictationAudioDucker.Output(
                deviceUID: uid,
                read: { [unowned self] in
                    onRead?()
                    return volume
                },
                write: { [unowned self] value in
                    if failsNextWrite { failsNextWrite = false; throw CocoaError(.fileWriteUnknown) }
                    let record = try JSONDecoder().decode(
                        DictationVolumeSnapshot.self,
                        from: Data(contentsOf: fileURL))
                    expect(
                        record.deviceUID == uid && record.matches(volume),
                        "A recoverable snapshot must exist before changing the device volume")
                    saved.append(record)
                    volume = value
                    writes.append(value)
                    onWrite?()
                })
        }

        /// 用该设备构造音量闪避器。
        func ducker(fileURL: URL) -> DictationAudioDucker {
            DictationAudioDucker(
                fileURL: fileURL,
                defaultOutput: { [unowned self] in output(fileURL: fileURL) },
                resolveOutput: { [unowned self] uid in
                    uid == self.uid ? output(fileURL: fileURL) : nil
                })
        }
    }

    /// 断言条件成立，否则直接中止。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    /// 逐个场景校验：普通启动、闪避/恢复、崩溃恢复、用户改音量、快速连续会话与写失败重试。
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dictation-volume-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appending(path: "volume.json")
        let fixture = Fixture()
        let ducker = fixture.ducker(fileURL: fileURL)
        ducker.recover()
        await ducker.waitForTransition()
        expect(fixture.writes.isEmpty, "An ordinary launch must not change the volume")

        ducker.begin()
        await ducker.waitForTransition()
        expect(abs(fixture.volume - 0.05) < 0.001, "Ducking uses ten percent of the original volume")
        let steps = fixture.saved
        expect(!steps.isEmpty, "Ducking must leave recoverable fade steps")
        ducker.end()
        await ducker.waitForTransition()
        expect(abs(fixture.volume - 0.5) < 0.001, "Finishing restores the original volume")
        expect(!FileManager.default.fileExists(atPath: fileURL.path), "Finishing clears recovery state")

        // 每个淡出步骤前后崩溃，都必须能恢复原始音量。
        for record in steps {
            guard let previous = record.previous else { fatalError("Missing pre-write recovery value") }
            for current in [record.lastSet, previous] {
                try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
                fixture.volume = current
                let restarted = fixture.ducker(fileURL: fileURL)
                restarted.recover()
                await restarted.waitForTransition()
                expect(
                    abs(fixture.volume - record.original) < 0.001,
                    "A crash before or after any fade step must restore the original volume")
                expect(
                    !FileManager.default.fileExists(atPath: fileURL.path),
                    "Successful recovery clears its snapshot")
            }
        }

        ducker.begin()
        await ducker.waitForTransition()
        fixture.volume = 0.8
        ducker.end()
        await ducker.waitForTransition()
        expect(fixture.volume == 0.8, "Finishing respects a user volume change")
        let saved = DictationVolumeSnapshot(deviceUID: fixture.uid, original: 0.5, lastSet: 0.05)
        try JSONEncoder().encode(saved).write(to: fileURL)
        ducker.recover()
        await ducker.waitForTransition()
        expect(fixture.volume == 0.8, "Relaunch respects a user volume change")
        expect(!FileManager.default.fileExists(atPath: fileURL.path), "A changed volume retires recovery")

        fixture.volume = 0.5
        fixture.onRead = { [weak fixture] in
            if FileManager.default.fileExists(atPath: fileURL.path) { fixture?.volume = 0.8 }
        }
        ducker.begin()
        await ducker.waitForTransition()
        fixture.onRead = nil
        expect(fixture.volume == 0.8, "A user change while saving must not be overwritten")

        fixture.volume = 0.5
        let changes = AsyncStream<Void>.makeStream()
        fixture.onWrite = { changes.continuation.yield(()) }
        ducker.begin()
        var iterator = changes.stream.makeAsyncIterator()
        _ = await iterator.next()
        ducker.restoreImmediately()
        await ducker.waitForTransition()
        fixture.onWrite = nil
        changes.continuation.finish()
        expect(abs(fixture.volume - 0.5) < 0.001, "Quitting during a fade restores immediately")
        expect(
            !FileManager.default.fileExists(atPath: fileURL.path),
            "A cancelled background write must not recreate a cleared snapshot")

        ducker.begin()
        ducker.end()
        ducker.begin()
        await ducker.waitForTransition()
        expect(abs(fixture.volume - 0.05) < 0.001, "Rapid sessions retain the true original volume")
        ducker.restoreImmediately()
        await ducker.waitForTransition()

        fixture.failsNextWrite = true
        ducker.begin()
        await ducker.waitForTransition()
        expect(abs(fixture.volume - 0.5) < 0.001, "A failed fade leaves the original volume intact")
        expect(!FileManager.default.fileExists(atPath: fileURL.path), "A failed fade clears recovery")
        fixture.volume = 0.05
        fixture.failsNextWrite = true
        try JSONEncoder().encode(saved).write(to: fileURL)
        ducker.recover()
        await ducker.waitForTransition()
        expect(
            fixture.volume == 0.05 && FileManager.default.fileExists(atPath: fileURL.path),
            "A failed recovery keeps the snapshot for another attempt")
        ducker.recover()
        await ducker.waitForTransition()
        expect(abs(fixture.volume - 0.5) < 0.001, "Recovery can retry a failed device write")

        // 设备不可用时保留快照，不得去闪避其它输出设备。
        let other = Fixture(uid: "headphones", volume: 0.7)
        var connected = false
        let switched = DictationAudioDucker(
            fileURL: fileURL,
            defaultOutput: { other.output(fileURL: fileURL) },
            resolveOutput: { uid in
                connected && uid == fixture.uid ? fixture.output(fileURL: fileURL) : nil
            })
        fixture.volume = 0.05
        try JSONEncoder().encode(saved).write(to: fileURL)
        switched.recover()
        switched.begin()
        await switched.waitForTransition()
        expect(
            other.writes.isEmpty && FileManager.default.fileExists(atPath: fileURL.path),
            "An unavailable device keeps its snapshot without ducking a different output")
        connected = true
        switched.recover()
        await switched.waitForTransition()
        expect(
            abs(fixture.volume - 0.5) < 0.001 && other.volume == 0.7,
            "Recovery resolves the original device even after the default output changes")

        // 非法快照不得改变音量，且应被丢弃。
        let invalid = DictationVolumeSnapshot(deviceUID: fixture.uid, original: 2, lastSet: 0.5)
        try JSONEncoder().encode(invalid).write(to: fileURL)
        let count = fixture.writes.count
        ducker.recover()
        await ducker.waitForTransition()
        expect(fixture.writes.count == count, "Invalid recovery data cannot change the volume")
        expect(!FileManager.default.fileExists(atPath: fileURL.path), "Invalid recovery data is discarded")

        let blocker = root.appending(path: "not-a-directory")
        try Data().write(to: blocker)
        let unavailable = fixture.ducker(fileURL: blocker.appending(path: "volume.json"))
        unavailable.begin()
        await unavailable.waitForTransition()
        expect(fixture.writes.count == count, "Unavailable recovery storage prevents unprotected ducking")
        print("Dictation volume crash recovery, user changes, devices and cancellation passed")
    }
}
