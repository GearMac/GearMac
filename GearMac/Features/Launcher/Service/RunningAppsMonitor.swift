// 文件职责：通过 NSWorkspace 通知实时跟踪正在运行的应用，为启动器提供运行状态指示。
// 分层：Service；@MainActor 隔离，仅在运行集合实际变化时重新发布。
import AppKit

/// 跟踪正在运行的应用，为启动器提供实时指示（数据来自 NSWorkspace）。
@MainActor
@Observable
final class RunningAppsMonitor {
    private(set) var runningBundleIDs: Set<String> = []
    @ObservationIgnored private var observers: [NotificationToken] = []

    /// 先做一次初始刷新，再订阅应用的启动与退出通知。
    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(NotificationToken(token, center: center))
        }
    }

    /// 条目的 bundle 正在运行时为 true；驱动运行标记点与「退出」操作。
    func isRunning(_ app: AppEntry) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    /// 辅助进程与 agent 也会触发这些通知，因此只在集合真正变化时才重新发布。
    private func refresh() {
        let next = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard next != runningBundleIDs else { return }
        runningBundleIDs = next
    }
}
