// 文件职责：通过 AX 读取屏幕上的窗口清单，并经单次 `AXGeometry` 快照完成坐标转换。
// 分层：Service；@MainActor 隔离，Element 持有 AX 句柄且不标 Sendable，绝不离开主 actor。
import AppKit
@preconcurrency import ApplicationServices

/// 通过 AX 读取屏幕上的内容，只读一次，并经单次 `AXGeometry` 快照完成转换。
@MainActor
enum WindowInventory {
    /// 一次快照会遍历每个应用，因此一个挂起进程不能消耗完整的 mover 超时。
    private static let sweepTimeout: Float = 0.2

    /// 单个窗口的存活 AX 句柄。不标 `Sendable`：它们不离开主 actor。
    struct Element {
        let bundleID: String
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
    }

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        /// 计划所依据的纯描述；`handle` 用于索引 `elements`。
        var windows: [WindowLayoutWindow]
        var elements: [Int: Element]
    }

    /// `positionableOnly` 是采集路径：一个我们永远无法移动的窗口不会成为条目。
    static func snapshot(positionableOnly: Bool = false) -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        var windows: [WindowLayoutWindow] = []
        var elements: [Int: Element] = [:]

        for app in candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                guard let frame = eligibleFrame(window, positionableOnly: positionableOnly)
                else { continue }
                let handle = windows.count
                windows.append(
                    WindowLayoutWindow(
                        handle: handle, bundleID: bundleID, frame: frame,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? ""))
                elements[handle] = Element(
                    bundleID: bundleID, app: app, application: application, window: window)
            }
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    /// 某个应用的、本次运行尚未写入过的窗口。
    static func unclaimedWindows(
        of application: AXUIElement, excluding claimed: some Collection<AXUIElement>
    ) -> [AXUIElement] {
        AXWindowAccess.windows(in: application).filter { window in
            AXUIElementSetMessagingTimeout(window, sweepTimeout)
            guard eligibleFrame(window, positionableOnly: true) != nil else { return false }
            return !claimed.contains { CFEqual($0, window) }
        }
    }

    /// 所有拥有面向用户窗口的应用，不含我们自己。按 pid 排除，因为“关于”会把我们变成 `.regular`。
    static func candidates() -> [NSRunningApplication] {
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.processIdentifier != ownPID
        }
    }

    /// 按 bundleID 解析出应用的 AX 句柄与运行实例。
    static func application(for bundleID: String) -> (AXUIElement, NSRunningApplication)? {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        else { return nil }
        return (AXWindowAccess.application(for: app.processIdentifier), app)
    }

    /// 布局可命名的窗口：真实、标准、在屏幕上，且能上报几何信息。
    private static func eligibleFrame(
        _ window: AXUIElement, positionableOnly: Bool
    ) -> CGRect? {
        // 比 mover 的规则更严格：保存用的 sheet 绝不能被采集为条目。
        guard
            AXWindowAccess.string(window, kAXSubroleAttribute)
                == (kAXStandardWindowSubrole as String)
        else { return nil }
        guard AXWindowAccess.bool(window, kAXMinimizedAttribute) != true,
            !AXWindowAccess.isFullScreen(window), let frame = AXWindowAccess.frame(of: window),
            frame.width > 0, frame.height > 0
        else { return nil }
        guard !positionableOnly || AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
        else { return nil }
        return frame
    }
}
