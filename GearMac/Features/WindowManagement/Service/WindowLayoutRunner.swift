// 文件职责：单次应用一套布局——摆放已存在的窗口、打开尚未运行的窗口并继续摆放。
// 分层：Service；@MainActor 隔离，等待在本次手势自己的 task 内完成，不遗留 timer/observer。
import AppKit
@preconcurrency import ApplicationServices

/// 单次应用一套布局：摆放已存在的，打开尚不存在的，并把它们也摆好。
@MainActor
enum WindowLayoutRunner {
    /// 足够冷启动应用绘制，又足够短，使卡住的应用无法把持整个运行。
    private static let launchDeadline = Duration.seconds(10)
    /// 每个待处理应用每跳一次 AX 往返，因此有意不按帧频率执行。
    private static let pollInterval = Duration.milliseconds(200)

    struct Outcome: Sendable {
        var placed = 0
        var opened = 0
        var skipped: [WindowLayoutPlan.Skipped] = []
        /// 已打开但在截止时间前始终未产生窗口的应用。
        var neverAppeared: [String] = []
        /// 启动失败，已由 `QuicklinkLauncher` 本地化。
        var openFailures: [String] = []
        /// 缺少授权，这是用户必须处理的唯一一种失败。
        var isBlockedOnPermission = false

        var didAnything: Bool { placed > 0 }
    }

    /// 唯一入口。`gap` 是首选间隙；是否采用由布局决定。
    static func run(_ layout: WindowLayout, gap: CGFloat) async -> Outcome {
        // 显式的用户手势，因此在这里请求授权是合适的。
        guard Permissions.ensureAccessibility() else {
            return Outcome(isBlockedOnPermission: true)
        }

        let snapshot = WindowInventory.snapshot()
        let plan = WindowLayoutPlan.make(
            layout: layout, screens: snapshot.screens, windows: snapshot.windows,
            preferredGap: gap)
        var outcome = Outcome(skipped: plan.skipped)
        guard !plan.placements.isEmpty else { return outcome }

        let startingApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var bound: [UUID: WindowInventory.Element] = [:]
        placeExisting(plan, snapshot: snapshot, bound: &bound, outcome: &outcome)

        let pending = plan.opens
        if !pending.isEmpty {
            await open(pending, outcome: &outcome)
            await placeOpened(pending, bound: &bound, outcome: &outcome)
        }
        // 放在最后，使本次运行打开的应用不会覆盖布局指定的应用而激活。
        if !Task.isCancelled, let frontmost = plan.frontmostEntryID.flatMap({ bound[$0] }),
            !userSwitchedApps(since: startingApp, opening: pending)
        {
            AXWindowAccess.focus(frontmost.window, in: frontmost.application, of: frontmost.app)
        }
        return outcome
    }

    /// 启动过程抢占前台是预期的；前台出现其他应用则说明用户已切走。
    private static func userSwitchedApps(
        since startingApp: pid_t?, opening placements: [WindowLayoutPlan.Placement]
    ) -> Bool {
        guard let current = NSWorkspace.shared.frontmostApplication,
            current.processIdentifier != startingApp
        else { return false }
        return !placements.contains { $0.bundleID == current.bundleIdentifier }
    }

    /// 布局可能命名的所有窗口，并把聚焦窗口标记为运行结束时的前台项。
    static func captureCurrentWindows() -> (entries: [WindowLayoutEntry], frontmostEntryID: UUID?) {
        guard Permissions.ensureAccessibility() else { return ([], nil) }
        let snapshot = WindowInventory.snapshot(positionableOnly: true)
        let screens = snapshot.screens
        let focusedHandle = focusedWindowHandle(in: snapshot)
        var frontmostEntryID: UUID?
        let entries = snapshot.windows.compactMap { window -> WindowLayoutEntry? in
            guard
                let host = WindowPlacementEngine.screen(
                    containing: window.frame, in: screens.map(\.screen)),
                let target = screens.first(where: { $0.screen.id == host.id })
            else { return nil }
            let entry = WindowLayoutGeometry.entry(
                bundleID: window.bundleID, display: target.display, frame: window.frame,
                on: target.screen)
            if window.handle == focusedHandle { frontmostEntryID = entry.id }
            return entry
        }
        return (entries, frontmostEntryID)
    }

    /// 当 GearMac 自身位于前台时返回 nil，例如从设置页采集时。
    private static func focusedWindowHandle(in snapshot: WindowInventory.Snapshot) -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let focused = AXWindowAccess.element(
                AXWindowAccess.application(for: app.processIdentifier),
                kAXFocusedWindowAttribute)
        else { return nil }
        return snapshot.elements.first { _, element in
            element.app.processIdentifier == app.processIdentifier
                && CFEqual(element.window, focused)
        }?.key
    }

    // MARK: - Placing

    /// 每个应用只做一次抑制/恢复，而不是每个窗口：该标志是以应用为作用域的。
    private static func placeExisting(
        _ plan: WindowLayoutPlan, snapshot: WindowInventory.Snapshot,
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) {
        let existing = plan.placements.filter { $0.source != .launch }
        for (_, group) in Dictionary(grouping: existing, by: \.bundleID) {
            guard case .existing(let first) = group[0].source,
                let application = snapshot.elements[first]?.application
            else { continue }
            let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
            defer { restore() }
            for placement in group {
                guard case .existing(let handle) = placement.source,
                    let element = snapshot.elements[handle]
                else { continue }
                if place(placement, on: element.window) { outcome.placed += 1 }
                bound[placement.entryID] = element
            }
        }
    }

    private static func place(
        _ placement: WindowLayoutPlan.Placement, on window: AXUIElement
    ) -> Bool {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        // 在写入前检查，因此无法定位的窗口会保持原样。
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return false }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        return AXWindowAccess.write(
            placement.frame, anchor: placement.anchor.placement, to: window, current: current,
            canResize: canResize, canvas: placement.canvas) != nil
    }

    // MARK: - Opening

    private static func open(
        _ placements: [WindowLayoutPlan.Placement], outcome: inout Outcome
    ) async {
        for placement in placements {
            guard
                let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: placement.bundleID)
            else {
                outcome.openFailures.append(placement.bundleID)
                continue
            }
            guard let argument = placement.argument else {
                AppLauncher.launch(url)
                outcome.opened += 1
                continue
            }
            do {
                // 与 quicklink 相同的打开方式，因此路径、主机名与 deeplink 都能正确行为。
                try await QuicklinkLauncher.open(
                    argument, openWithBundleID: placement.bundleID, inNewWindow: false)
                outcome.opened += 1
            } catch {
                outcome.openFailures.append(error.localizedDescription)
            }
        }
    }

    /// 在本次手势自己的 task 内做有界等待：无 timer、无 observer，不遗留任何东西。
    private static func placeOpened(
        _ placements: [WindowLayoutPlan.Placement],
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) async {
        var pending = placements
        // 用 `ContinuousClock`，因此时钟跳变或休眠无法缩短或延长等待。
        let deadline = ContinuousClock.now + launchDeadline
        while !pending.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
            guard !Task.isCancelled else { break }
            pending = pending.filter { placement in
                guard let (application, app) = WindowInventory.application(for: placement.bundleID),
                    let window = WindowInventory.unclaimedWindows(
                        of: application, excluding: bound.values.lazy.map(\.window)
                    ).first
                else { return true }
                let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
                defer { restore() }
                if place(placement, on: window) { outcome.placed += 1 }
                bound[placement.entryID] = WindowInventory.Element(
                    bundleID: placement.bundleID, app: app, application: application,
                    window: window)
                return false
            }
        }
        outcome.neverAppeared = pending.map(\.bundleID)
    }
}
