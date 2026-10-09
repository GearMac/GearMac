// 文件职责：把绑定到它的各个 store 镜像写入 settings.json，并把文件的编辑应用回这些 store。
// 分层：Service；@MainActor，写入为原子操作并跟随符号链接，是设置文件读写的唯一入口。
import Foundation
import Observation

/// 将绑定到它的各个 store 镜像进 settings.json，并把文件的编辑应用回这些 store。
@MainActor
final class SettingsFileRepository {
    /// 解析或写入产生问题时回调。
    var onIssues: (([SettingsFileIssue]) -> Void)?

    private let fileURL: URL
    private let bindings: [SettingsFileBinding]
    /// 在所有绑定都写入之后执行一次，用于跨键的变更。
    private let commit: () -> [SettingsFileIssue]
    private let monitor: SettingsFileMonitor
    /// 最近读取或写入的字节，避免把监视器对本次保存的回声误当作编辑。
    private var lastSeen: Data?
    /// store 与文件最后一次达成一致的渲染结果；只有超出它才会真正写盘。
    private var baseline: Data?
    private var saveTask: Task<Void, Never>?

    private static let saveDelay = Duration.milliseconds(300)

    init(
        fileURL: URL, bindings: [SettingsFileBinding],
        commit: @escaping () -> [SettingsFileIssue] = { [] }
    ) {
        self.fileURL = fileURL
        self.bindings = bindings
        self.commit = commit
        monitor = SettingsFileMonitor(fileURL: fileURL)
    }

    isolated deinit {
        saveTask?.cancel()
    }

    /// 从此双向跟随；`importing` 为真时先应用文件内容，否则用当前状态替换文件。
    func start(importing: Bool) {
        if importing, FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try? Data(contentsOf: fileURL)
            lastSeen = data
            let issues = data.map { apply($0) } ?? [.unreadable]
            baseline = renderObserved()
            report(issues)
        } else {
            save()
        }
        monitor.onChange = { [weak self] in self?.reload() }
        monitor.start()
    }

    /// 立即执行待处理的保存，用于无法等待延迟的退出或停止场景。
    func flush() {
        guard let saveTask else { return }
        saveTask.cancel()
        save()
    }

    // MARK: - Reading

    /// 文件变化后重新读取并应用；内容与上次相同时直接返回。
    private func reload() {
        // 保存过程中文件短暂缺失是正常的：完成保存的重命名本身会触发事件。
        guard let data = try? Data(contentsOf: fileURL), data != lastSeen else { return }
        lastSeen = data
        let issues = apply(data)
        baseline = render()
        report(issues)
    }

    /// 解析数据并应用其中的值，返回合并后的问题列表。
    private func apply(_ data: Data) -> [SettingsFileIssue] {
        do {
            let parsed = try SettingsFileFormat.parse(data)
            return parsed.issues + apply(parsed.values)
        } catch {
            return [error]
        }
    }

    /// 文件中缺失或拼写错误的键保持其当前值不变。
    private func apply(_ values: [SettingsFileKey: SettingsFileJSON]) -> [SettingsFileIssue] {
        bindings.flatMap { binding in
            values[binding.key].map(binding.write) ?? []
        } + commit()
    }

    // MARK: - Writing

    /// 把当前各个绑定的值渲染为 settings.json 数据。
    private func render() -> Data {
        SettingsFileFormat.render(
            Dictionary(uniqueKeysWithValues: bindings.map { ($0.key, $0.read()) }))
    }

    /// 渲染并跟踪每个绑定的值，使任意位置的下一次变化都会安排一次保存。
    private func renderObserved() -> Data {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSave() }
        }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.saveDelay)
            } catch {
                return
            }
            self?.save()
        }
    }

    /// 渲染当前状态，并在与基线不同时写盘。
    private func save() {
        saveTask = nil
        let data = renderObserved()
        guard data != baseline else { return }
        if !write(data) { report([.unwritable]) }
    }

    /// 原子写入，并写入符号链接的目标，因此指向 dotfiles 仓库的链接仍是链接。
    private func write(_ data: Data) -> Bool {
        let target = fileURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            return false
        }
        lastSeen = data
        baseline = data
        return true
    }

    private func report(_ issues: [SettingsFileIssue]) {
        guard !issues.isEmpty else { return }
        onIssues?(issues)
    }
}
