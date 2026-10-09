// 文件职责：通过 AX 一次性扫描所有可切换窗口，返回纯数据条目与实时 AX 句柄快照。
// 分层：Service（@MainActor）；遍历较浅以保持同步，不读取窗口名（无需屏幕录制权限），且仅限主 actor。
import AppKit
@preconcurrency import ApplicationServices

/// 通过 AX 一次性读取所有可切换窗口。遍历足够浅，因此可保持同步：不同于菜单遍历，
/// 它只访问 App 及其窗口，不深入树结构。
@MainActor
enum WindowSwitchSweep {
    /// 一次扫描会遍历每个 App，因此单个卡死进程不应耗尽完整的消息超时时间。
    private static let sweepTimeout: Float = 0.2

    /// 单个窗口的实时 AX 句柄。永不 `Sendable`：它们不会离开主 actor。
    struct Element {
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
    }

    /// 一次扫描的结果：条目列表与句柄到元素的映射。
    struct Snapshot {
        var entries: [WindowSwitchEntry]
        var elements: [Int: Element]
    }

    /// 扫描所有候选 App 的窗口，生成快照；`ranks` 提供 App 的层级排名。
    static func snapshot(ranks: [pid_t: Int]) -> Snapshot {
        var entries: [WindowSwitchEntry] = []
        var elements: [Int: Element] = [:]

        for app in WindowInventory.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
            let iconURL = app.bundleURL
            let iconStamp = iconURL.map(FileIconStamp.value(for:)) ?? 0
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                guard isSwitchable(window) else { continue }
                let handle = entries.count
                entries.append(
                    WindowSwitchEntry(
                        handle: handle, appName: app.localizedName ?? bundleID,
                        bundleID: bundleID, iconURL: iconURL, iconStamp: iconStamp,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                        isMinimized: AXWindowAccess.bool(window, kAXMinimizedAttribute) == true,
                        appRank: ranks[pid] ?? .max))
                elements[handle] = Element(app: app, application: application, window: window)
            }
        }
        return Snapshot(entries: entries, elements: elements)
    }

    /// 比布局清单的规则更宽松：最小化窗口正是切换器的用武之地，
    /// 且位于其他 Space 的窗口在被抬升前不会报告 frame。
    private static func isSwitchable(_ window: AXUIElement) -> Bool {
        AXWindowAccess.string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String)
    }
}
