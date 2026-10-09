// 文件职责：监视 settings.json（包括编辑器的「另存为」式重命名写入），在写入稳定后回调 onChange。
// 分层：Service；@MainActor，只处理文件系统事件与去抖，不解析内容。
import Darwin
import Foundation

/// 报告 settings.json 的编辑，包括编辑器的「另存为」式重命名写入，并在写入稳定后触发。
@MainActor
final class SettingsFileMonitor {
    /// 文件稳定变化后的回调。
    var onChange: (() -> Void)?

    private let fileURL: URL
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var settleTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private static let settleDelay = Duration.milliseconds(150)
    private static let retryDelay = Duration.seconds(1)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    isolated deinit {
        settleTask?.cancel()
        retryTask?.cancel()
        folderSource?.cancel()
        fileSource?.cancel()
    }

    /// 开始监视。
    func start() {
        arm()
    }

    /// 每次都重新打开文件：重命名式保存会让旧的文件描述符指向已失效的 inode。
    private func arm() {
        let folder = fileURL.deletingLastPathComponent()
        if folderSource == nil {
            folderSource = source(watching: folder, events: [.write, .delete, .rename, .revoke])
        }
        fileSource?.cancel()
        fileSource = source(watching: fileURL, events: [.write, .extend, .delete, .rename, .revoke])
        if folderSource == nil { scheduleRetry() }
    }

    /// 为给定 URL 建立文件系统事件源，打开失败时返回 nil。
    private func source(
        watching url: URL, events: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.sourceDidFire() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }

    /// 事件触发后重建事件源并安排去抖。
    private func sourceDidFire() {
        if !FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) {
            folderSource?.cancel()
            folderSource = nil
        }
        arm()
        settle()
    }

    /// 重新安排去抖：延迟后若没有新事件再回调 onChange。
    private func settle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.settleDelay)
            } catch {
                return
            }
            self?.onChange?()
        }
    }

    /// 仅在文件夹缺失期间轮询；下一次保存或用户操作会把它恢复。
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            retryTask = nil
            arm()
            if folderSource != nil { settle() }
        }
    }
}
