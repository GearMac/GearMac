// 文件职责：一次性读取房间可容纳的所有窗口（含最小化窗口与隐藏应用的窗口），产出快照。
// 分层：Service；@MainActor 隔离，单次扫描使用较短的 AX 超时，避免一个挂起进程拖慢整轮。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// 一次性读取房间可容纳的每个窗口，包括最小化窗口与隐藏应用的窗口。
@MainActor
enum RoomWindowSweep {
    /// 一次扫描会遍历每个应用，因此一个挂起进程不能消耗完整消息超时。
    private static let sweepTimeout: Float = 0.2
    /// 比这更小的都是面板或窄条，绝非房间的窗口。
    private static let smallest = CGSize(width: 100, height: 60)
    /// 层级 0 是普通窗口层；其上是菜单栏、Dock 与各种浮层。
    private static let normalLayer = 0

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        /// `handle` 是该数组的下标，也是 `elements` 的键。
        var windows: [RoomLiveWindow]
        var elements: [Int: WindowInventory.Element]

        func window(_ handle: Int) -> RoomLiveWindow? {
            windows.indices.contains(handle) ? windows[handle] : nil
        }

        /// 房间落地的显示器；该显示器消失时用第一个。
        func screen(uuid: String?) -> WindowLayoutScreen? {
            let uuid = uuid?.lowercased()
            return screens.first { $0.display.uuid == uuid } ?? screens.first
        }
    }

    /// 采集当前所有可归属房间的窗口快照。
    static func snapshot() -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        let ranks = frontRanks()
        var windows: [RoomLiveWindow] = []
        var elements: [Int: WindowInventory.Element] = [:]
        for app in WindowInventory.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in reportedWindows(of: application, app: app) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                let minimized = AXWindowAccess.bool(window, kAXMinimizedAttribute) == true
                guard isRoomWindow(window, of: app, minimized: minimized),
                    let frame = AXWindowAccess.frame(of: window),
                    frame.width >= smallest.width, frame.height >= smallest.height
                else { continue }
                let handle = windows.count
                let windowID = AXWindowAccess.windowID(of: window)
                windows.append(
                    RoomLiveWindow(
                        handle: handle, bundleID: bundleID, appName: app.localizedName ?? bundleID,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                        windowID: windowID, frame: frame, isMinimized: minimized,
                        isAppHidden: app.isHidden, frontRank: windowID.flatMap { ranks[$0] } ?? .max,
                        appURL: app.bundleURL))
                elements[handle] = WindowInventory.Element(
                    bundleID: bundleID, app: app, application: application, window: window)
            }
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    /// 基于 Web 的应用在被通过辅助功能询问前不会列出窗口；询问后再停。
    private static func reportedWindows(
        of application: AXUIElement, app: NSRunningApplication
    ) -> [AXUIElement] {
        let windows = AXWindowAccess.windows(in: application)
        guard windows.isEmpty, !app.isHidden else { return windows }
        AXWindowAccess.setManualAccessibility(true, application: application)
        defer { AXWindowAccess.setManualAccessibility(false, application: application) }
        return AXWindowAccess.windows(in: application)
    }

    /// 隐藏或最小化的应用的窗口在一段时间内会被识别为对话框；真正的窗口能够最小化。
    private static func isRoomWindow(
        _ window: AXUIElement, of app: NSRunningApplication, minimized: Bool
    ) -> Bool {
        guard !AXWindowAccess.isFullScreen(window) else { return false }
        let subrole = AXWindowAccess.string(window, kAXSubroleAttribute)
        if subrole == (kAXStandardWindowSubrole as String) { return true }
        guard subrole == (kAXDialogSubrole as String) else { return false }
        return app.isHidden || minimized
            || AXWindowAccess.element(window, kAXMinimizeButtonAttribute) != nil
    }

    /// 按窗口编号从前到后。从不读取标题，因此无需屏幕录制权限。
    private static func frontRanks() -> [UInt32: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [UInt32: Int] = [:]
        for window in listing where window[kCGWindowLayer as String] as? Int == normalLayer {
            guard let number = window[kCGWindowNumber as String] as? UInt32 else { continue }
            ranks[number] = ranks.count
        }
        return ranks
    }
}
