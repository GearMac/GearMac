// 文件职责：听写期间把系统输出音量平滑压低，结束后恢复，并在中断后自恢复原音量。
// 分层：Service/@MainActor；通过 CoreAudio 读写音量，状态落盘到 Application Support。
import CoreAudio
import Foundation
import OSLog

/// 输出音量「闪避器」：以 16 步渐变压低/恢复默认输出设备音量。
@MainActor
final class DictationAudioDucker {
    /// 某个输出设备的音量读写句柄。
    struct Output {
        let deviceUID: String
        let read: () throws -> Float
        let write: (Float) throws -> Void
    }

    /// 当前正在压低的设备及其音量快照。
    private struct Snapshot {
        let output: Output
        var volume: DictationVolumeSnapshot
    }

    private static let logger = Logger(subsystem: "com.gearmac", category: "DictationVolume")
    private let fileURL: URL
    private let defaultOutput: () throws -> Output?
    private let resolveOutput: (String) throws -> Output?
    private var snapshot: Snapshot?
    private var transition: Task<Void, Never>?

    /// 允许注入文件路径与设备解析方式，便于测试。
    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-volume.json"),
        defaultOutput: @escaping () throws -> Output? = {
            try AudioHardwareSystem.shared.defaultOutputDevice.flatMap {
                try DictationAudioDucker.output(for: $0)
            }
        },
        resolveOutput: @escaping (String) throws -> Output? = { uid in
            try AudioHardwareSystem.shared.device(forUID: uid).flatMap {
                try DictationAudioDucker.output(for: $0)
            }
        }
    ) {
        self.fileURL = fileURL
        self.defaultOutput = defaultOutput
        self.resolveOutput = resolveOutput
    }

    /// 析构时取消未完成的渐变任务。
    isolated deinit { transition?.cancel() }

    /// 启动时恢复上次异常退出遗留的音量。
    func recover() {
        schedule { _ = try await $0.recoverSavedVolume() }
    }

    /// 开始听写：确保已恢复旧状态后把音量降到原始的 10%。
    func begin() {
        schedule { ducker in
            if ducker.snapshot == nil {
                guard try await ducker.recoverSavedVolume(),
                    let output = try ducker.defaultOutput()
                else { return }
                let original = try output.read()
                let volume = DictationVolumeSnapshot(
                    deviceUID: output.deviceUID, original: original, lastSet: original)
                guard volume.isValid, original > 0 else { return }
                ducker.snapshot = Snapshot(output: output, volume: volume)
            }
            guard let snapshot = ducker.snapshot else { return }
            try await ducker.fade(to: snapshot.volume.original * 0.1, release: false)
        }
    }

    /// 结束听写：把音量渐变回原始值并清除持久化状态。
    func end() {
        guard snapshot != nil || transition != nil else { return }
        schedule { ducker in
            guard let snapshot = ducker.snapshot else { return }
            try await ducker.fade(to: snapshot.volume.original, release: true)
        }
    }

    /// 立即恢复音量并取消渐变，随后重新尝试清理遗留状态（退出路径使用）。
    func restoreImmediately() {
        transition?.cancel()
        if let snapshot, let current = try? snapshot.output.read(), snapshot.volume.matches(current) {
            do { try snapshot.output.write(snapshot.volume.original) } catch {
                Self.logger.error("Couldn't restore dictation volume: \(error.localizedDescription)")
            }
        }
        snapshot = nil
        recover()
    }

    /// 等待当前渐变任务结束，供测试或关停流程同步。
    func waitForTransition() async {
        while let transition { await transition.value }
    }

    /// 取消上一个操作后串行执行新操作，失败时记录日志并尝试恢复。
    private func schedule(_ operation: @escaping @MainActor (DictationAudioDucker) async throws -> Void) {
        let previous = transition
        previous?.cancel()
        transition = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            do { try await operation(self) } catch is CancellationError {
            } catch {
                Self.logger.error("Couldn't update dictation volume: \(error.localizedDescription)")
                if snapshot != nil { restoreImmediately() }
            }
            if !Task.isCancelled { transition = nil }
        }
    }

    /// 分 16 步把音量线性过渡到目标值，每步先持久化再写入硬件。
    private func fade(to target: Float, release: Bool) async throws {
        guard let snapshot else { return }
        let start = try snapshot.output.read()
        guard snapshot.volume.matches(start) else {
            try await clear()
            return
        }
        for step in 1...16 {
            try Task.checkCancellation()
            guard let snapshot = self.snapshot else { return }
            let volume = start + (target - start) * Float(step) / 16
            var saved = snapshot.volume
            saved.previous = saved.lastSet
            saved.lastSet = volume
            // 持久化与硬件写入之间若崩溃，两个音量值任一都必须能恢复。
            try await persist(saved)
            try Task.checkCancellation()
            guard snapshot.volume.matches(try snapshot.output.read()) else {
                try await clear()
                return
            }
            try snapshot.output.write(volume)
            self.snapshot?.volume.lastSet = try snapshot.output.read()
            self.snapshot?.volume.previous = nil
            if step < 16 { try await Task.sleep(for: .milliseconds(30)) }
        }
        if release { try await clear() }
    }

    /// 读取并修正上次遗留的音量快照，返回是否可继续使用当前设备。
    private func recoverSavedVolume() async throws -> Bool {
        let fileURL = fileURL
        let volume = try await Task.detached(priority: .utility) { () -> DictationVolumeSnapshot? in
            do {
                return try JSONDecoder().decode(DictationVolumeSnapshot.self, from: Data(contentsOf: fileURL))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return nil
            }
        }.value
        try Task.checkCancellation()
        guard let volume else { return true }
        guard volume.isValid else { try await persist(nil); return true }
        guard let output = try resolveOutput(volume.deviceUID) else { return false }
        let current = try output.read()
        if volume.matches(current), current != volume.original { try output.write(volume.original) }
        try await persist(nil)
        return true
    }

    /// 清除内存中的快照并删除持久化文件。
    private func clear() async throws {
        snapshot = nil
        try await persist(nil)
    }

    /// 原子写入或删除音量快照文件（在后台线程执行）。
    private func persist(_ volume: DictationVolumeSnapshot?) async throws {
        let fileURL = fileURL
        try await Task.detached(priority: .utility) {
            if let volume {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try JSONEncoder().encode(volume).write(to: fileURL, options: .atomic)
            } else {
                do { try FileManager.default.removeItem(at: fileURL) } catch let error as CocoaError
                    where error.code == .fileNoSuchFile
                {}
            }
        }.value
    }

    /// 找到设备的主输出音量控件并包装成读写句柄。
    private static func output(for device: AudioHardwareDevice) throws -> Output? {
        guard let control = try device.controls.first(where: isMainOutputVolume) else { return nil }
        return Output(
            deviceUID: try device.uid,
            read: { try control.volumeScalarValue }, write: { try control.setVolumeScalarValue($0) })
    }

    /// 判断控件是否为全局主输出音量控件。
    private static func isMainOutputVolume(_ control: AudioHardwareControl) -> Bool {
        guard (try? control.classID) == kAudioVolumeControlClassID else { return false }
        func value(for selector: AudioObjectPropertySelector) -> UInt32? {
            let address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard let data = try? control.propertyData(address: address, qualifier: nil),
                data.count == MemoryLayout<UInt32>.size
            else { return nil }
            return data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
        return value(for: kAudioControlPropertyScope) == kAudioObjectPropertyScopeOutput
            && value(for: kAudioControlPropertyElement) == kAudioObjectPropertyElementMain
    }
}
