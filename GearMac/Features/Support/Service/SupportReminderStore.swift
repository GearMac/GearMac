// 文件职责：支持提醒的时钟：决定何时触发询问，并持久化首次运行与最近询问时间，自身不展示任何界面。
// 分层：Service；文件读写与定时循环等副作用集中在此，通过 onDue 回调向外通知。
import Foundation

/// 支持提醒的时钟：决定何时询问，自身从不展示任何内容。
@MainActor
final class SupportReminderStore {
    /// 让首次评估及其可能弹出的窗口避开登录高峰。
    private static let startupDelay = Duration.seconds(60)
    /// 已到期但被推迟的询问按此频率重试，而不是再等一个完整间隔。
    private static let retryInterval: TimeInterval = 600
    /// 开关关闭时只剩开关本身值得等待，因此循环进入空转。
    private static let idleInterval: TimeInterval = 3600

    var onDue: (@MainActor () -> Void)?

    private let settings: AppSettings
    private let fileURL: URL
    private var state: State
    private var pump: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        fileURL = AppPaths.applicationSupport().appendingPathComponent("support-reminder.json")
        if let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(State.self, from: data)
        {
            state = stored
        } else {
            state = State(firstSeenAt: Date())
            persist()
        }
    }

    deinit { pump?.cancel() }

    func start() {
        // 直接替换而非提前返回：已退出的循环会留下非 nil 的 task，阻塞下次启动。
        pump?.cancel()
        pump = Task { [weak self] in
            try? await Task.sleep(for: Self.startupDelay)
            while !Task.isCancelled {
                // 使用可选链：睡眠不能持有 store，否则对象无法释放。
                guard let wait = self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// 每次展示都会调用，无论走哪条路径：刚看过说明的人不会很快再次被询问。
    func markAsked(at now: Date = Date()) {
        state.lastAskedAt = now
        persist()
    }

    // MARK: - Private

    /// 上次询问时间；从未询问过时取首次运行时间。
    private var anchor: Date { state.lastAskedAt ?? state.firstSeenAt }

    /// 循环的一轮：到期就触发询问，并返回下次等待时长。
    private func advance() -> TimeInterval {
        let wait = SupportReminderSchedule.wait(since: anchor, now: Date())
        guard settings.supportRemindersEnabled else { return max(wait, Self.idleInterval) }
        guard wait <= 0 else { return wait }
        onDue?()
        // 设下限：被推迟的询问不会移动基准时间，这里不能因此空转。
        return max(SupportReminderSchedule.wait(since: anchor, now: Date()), Self.retryInterval)
    }

    /// 把状态原子写入磁盘，失败时静默忽略。
    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct State: Codable {
        var firstSeenAt: Date
        var lastAskedAt: Date?
    }
}
