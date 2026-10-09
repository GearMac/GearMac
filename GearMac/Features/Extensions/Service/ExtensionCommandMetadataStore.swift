// 文件职责：集中存取每个扩展命令的行元数据（副标题、菜单栏开关、后台刷新状态等）。
// 分层：Service；写入做防抖合并，单独存放于 `extension-data` 之外以免绘制行时加载整个扩展存储。
import Foundation

/// 所有命令的行元数据集中存放在一个小文件里，刻意不放进 `extension-data`：
/// 绘制启动器的一行时绝不能把扩展的整个 `LocalStorage` 和 `Cache` 全部载入。
@MainActor
@Observable
final class ExtensionCommandMetadataStore {
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private var records: [String: [String: ExtensionCommandMetadata]]

    init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        records =
            (try? Data(contentsOf: fileURL))
            .flatMap {
                try? JSONDecoder().decode(
                    [String: [String: ExtensionCommandMetadata]].self, from: $0)
            } ?? [:]
    }

    func metadata(extension name: String, command: String) -> ExtensionCommandMetadata {
        records[name]?[command] ?? ExtensionCommandMetadata()
    }

    func setSubtitle(_ subtitle: String?, extension name: String, command: String) {
        mutate(name, command) { $0.subtitle = subtitle }
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        mutate(name, command) { $0.backgroundEnabled = enabled }
    }

    /// 返回指定扩展/命令当前展示用的菜单栏命令列表。
    func menuBarCommands() -> [(extension: String, command: String)] {
        records.flatMap { name, commands in
            commands.filter(\.value.menuBarEnabled).keys.map { (extension: name, command: $0) }
        }
    }

    /// 关闭该项时也一并丢弃其渲染快照：否则下次启动会恢复过期快照。
    func setMenuBarEnabled(_ enabled: Bool, extension name: String, command: String) {
        mutate(name, command) {
            $0.menuBarEnabled = enabled
            if !enabled { $0.menuBarSnapshot = nil }
        }
    }

    func setMenuBarSnapshot(
        _ snapshot: ExtensionMenuBarSnapshot?, extension name: String, command: String
    ) {
        mutate(name, command) { $0.menuBarSnapshot = snapshot }
    }

    /// 菜单栏运行本身就是一次刷新，因此下一次计时从本次启动算起。
    func recordMenuBarRun(extension name: String, command: String, now: Date) {
        mutate(name, command) {
            $0.menuBarEnabled = true
            $0.lastRun = now
        }
    }

    /// 停用时随调度一起清除上一次错误；否则过期警告会比其原因存活更久。
    func clearBackgroundError(extension name: String, command: String) {
        mutate(name, command) {
            $0.lastError = nil
            $0.consecutiveFailures = 0
        }
    }

    /// 手动运行也算一次刷新，因此调度器不会紧接着再次触发。
    func activateBackgroundRefresh(extension name: String, command: String, now: Date) {
        mutate(name, command) {
            $0.backgroundEnabled = true
            $0.lastRun = now
        }
    }

    func recordBackgroundResult(
        extension name: String, command: String, success: Bool, error: String?, now: Date
    ) {
        mutate(name, command) {
            $0.lastRun = now
            $0.lastError = success ? nil : error
            $0.consecutiveFailures = success ? 0 : $0.consecutiveFailures + 1
        }
    }

    func removeAll(extension name: String) {
        guard records.removeValue(forKey: name) != nil else { return }
        scheduleFlush()
    }

    /// 立即（取消待执行的防抖任务后）将脏数据写入磁盘。
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard isDirty, let data = try? JSONEncoder().encode(records) else { return }
        isDirty = false
        try? data.write(to: fileURL, options: .atomic)
    }

    private func mutate(
        _ name: String, _ command: String, _ body: (inout ExtensionCommandMetadata) -> Void
    ) {
        var record = records[name]?[command] ?? ExtensionCommandMetadata()
        body(&record)
        // 每次提交菜单都会重绘其行；内容未变化时不应产生写入开销。
        guard records[name]?[command] != record else { return }
        records[name, default: [:]][command] = record
        scheduleFlush()
    }

    /// 由定时器合并写入，与 `ExtensionStorage` 合并自身写入的方式一致。
    private func scheduleFlush() {
        isDirty = true
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }
}
