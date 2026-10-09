// 文件职责：执行“房间（Room）”的进入与恢复——把房间内窗口摆到同一显示器、其余应用退到后台并记录停泊窗口。
// 分层：Service；@MainActor 隔离，所有 AX 写入在单个可见步骤内完成，超时/轮询用 ContinuousClock 度量。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// 进入房间：房间内窗口落到同一显示器，其余窗口退到一旁。参见 window-rooms.md。
@MainActor
enum RoomRunner {
    /// 足够冷启动的应用绘制，又足够短，使卡住的应用无法把持整个房间。
    private static let launchDeadline = Duration.seconds(10)
    /// 刚取消隐藏的应用会忽略移动请求、也不上报窗口，直到它真正回来。
    private static let unhideDeadline = Duration.milliseconds(600)
    /// 取消隐藏只是轮询一个廉价的标志；等待启动则要扫描每个应用，因此轮询得更慢。
    private static let unhidePoll = Duration.milliseconds(20)
    private static let launchPoll = Duration.milliseconds(200)
    /// 会做缩放动画的应用在写入后这么短时间内仍处于动画中途。
    private static let settleDelay = Duration.milliseconds(150)
    /// 足够晚到或被弹回的 frame 显现，再做那一次纠正。
    private static let verifyDelay = Duration.milliseconds(250)
    /// 跨应用置前只有在每个应用都获得一点时间置前后才会按顺序落定。
    private static let raisePacing = Duration.milliseconds(40)
    /// 新的最小尺寸可能在更窄的槽位中暴露另一个；最小尺寸只会增长，因此此过程会终止。
    private static let relayoutPasses = 2
    /// 为应用自身的取整留出余量，例如终端按整格尺寸调整。
    private static let slack: CGFloat = 4
    private static let resizeSlack: CGFloat = 16

    /// 一次进入房间所需的上下文：间隙、目标显示器、已认领窗口、最小尺寸与停泊账本。
    struct Context {
        let gap: CGFloat
        /// 房间落到哪个显示器；该显示器消失时用第一个已连接显示器。
        let displayUUID: String?
        let claimed: Set<UInt32>
        let minimums: RoomMinimumSizeStore
        let ledger: RoomParkingLedger
    }

    /// 一次进入房间的结果统计。
    struct Outcome: Sendable {
        var placed = 0
        var parked = 0
        /// 本次这一轮隐藏的应用，以便只有它们随后被恢复，绝不恢复手动隐藏的应用。
        var hiddenApps = Set<pid_t>()
        var missing: [String] = []
        var isBlockedOnPermission = false
    }

    // MARK: - Entering

    static func enter(_ room: Room, context: Context) async -> Outcome {
        guard Permissions.ensureAccessibility() else { return Outcome(isBlockedOnPermission: true) }
        let apps = appsInOrder(of: room)
        let launched = launchMissing(apps)
        let unhidden = unhide(apps)
        await wait(for: unhideDeadline, every: unhidePoll) { unhidden.allSatisfy { !$0.isHidden } }

        var snapshot = RoomWindowSweep.snapshot()
        guard var plan = makePlan(room, in: snapshot, context: context) else { return Outcome() }
        let late = launched.union(unhidden.compactMap(\.bundleIdentifier))
        if !late.isEmpty {
            await wait(for: launched.isEmpty ? unhideDeadline : launchDeadline, every: launchPoll) {
                guard plan.missing.contains(where: { late.contains(room.windows[$0].bundleID) })
                else { return true }
                snapshot = RoomWindowSweep.snapshot()
                plan = makePlan(room, in: snapshot, context: context) ?? plan
                return false
            }
        }
        let missing = plan.missing.map { room.windows[$0].appName }
        // 如果没有任何窗口可展示，把所有应用都退到一旁只会留下一张空桌面。
        guard !Task.isCancelled, !plan.placements.isEmpty else { return Outcome(missing: missing) }

        place(plan.placements, in: snapshot)
        for _ in 0..<relayoutPasses {
            try? await Task.sleep(for: settleDelay)
            guard await learnMinimums(from: plan, in: snapshot, into: context.minimums) else { break }
            snapshot = RoomWindowSweep.snapshot()
            guard let replanned = makePlan(room, in: snapshot, context: context) else { break }
            plan = replanned
            place(plan.placements, in: snapshot)
        }

        var outcome = Outcome(placed: plan.placements.count, missing: missing)
        outcome.parked = park(plan, in: snapshot, ledger: context.ledger)
        returnWindowsOfHiddenApps(plan, in: snapshot, ledger: context.ledger)
        await raise(plan, in: snapshot)
        outcome.hiddenApps = hideApps(keeping: plan.keeps)

        try? await Task.sleep(for: verifyDelay)
        verify(plan, in: snapshot, minimums: context.minimums)
        forgetPlacedWindows(plan, in: snapshot, ledger: context.ledger)
        return outcome
    }

    /// 房间隐藏过的应用，然后每个已停泊窗口：刚取消隐藏的应用在回来前会忽略移动请求。
    static func restoreEverything(hiddenApps: Set<pid_t>, ledger: RoomParkingLedger) async {
        let hidden = WindowInventory.candidates().filter {
            $0.isHidden && hiddenApps.contains($0.processIdentifier)
        }
        hidden.forEach(show)
        await wait(for: unhideDeadline, every: unhidePoll) { hidden.allSatisfy { !$0.isHidden } }
        returnParkedWindows(ledger: ledger)
    }

    /// 把所有已停泊窗口送回家，返回回来的数量。同步执行，因此退出时可直接跑完。
    @discardableResult
    static func returnParkedWindows(ledger: RoomParkingLedger) -> Int {
        guard Permissions.isAccessibilityTrusted(), !ledger.isEmpty else { return 0 }
        let snapshot = RoomWindowSweep.snapshot()
        let screens = snapshot.screens.map(\.screen.frame)
        let returned = snapshot.windows.compactMap { window -> UInt32? in
            guard let element = snapshot.elements[window.handle] else { return nil }
            return unpark(window, element: element, screens: screens, ledger: ledger)
        }
        ledger.forget(returned)
        // 已退出应用的窗口随之消失；仍在运行但进入缓慢的应用保留它的回家路径。
        ledger.keepOnly(
            bundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        return returned.count
    }

    // MARK: - Planning

    private static func makePlan(
        _ room: Room, in snapshot: RoomWindowSweep.Snapshot, context: Context
    ) -> RoomPlan? {
        guard let screen = snapshot.screen(uuid: context.displayUUID) else { return nil }
        return RoomPlan.make(
            room, windows: snapshot.windows, on: screen, gap: context.gap,
            minimums: context.minimums.sizes, claimed: context.claimed)
    }

    private static func appsInOrder(of room: Room) -> [String] {
        var seen = Set<String>()
        return room.windows.map(\.bundleID).filter { seen.insert($0).inserted }
    }

    private static func launchMissing(_ bundleIDs: [String]) -> Set<String> {
        var launched = Set<String>()
        for bundleID in bundleIDs
        where NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { continue }
            AppLauncher.launch(url)
            launched.insert(bundleID)
        }
        return launched
    }

    private static func unhide(_ bundleIDs: [String]) -> [NSRunningApplication] {
        let wanted = Set(bundleIDs)
        let hidden = WindowInventory.candidates().filter {
            $0.isHidden && wanted.contains($0.bundleIdentifier ?? "")
        }
        hidden.forEach(show)
        return hidden
    }

    /// 在本次手势自己的 task 内轮询；用 `ContinuousClock`，因此时钟跳变无法缩短它。
    private static func wait(
        for duration: Duration, every interval: Duration, until isDone: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + duration
        while !isDone(), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: interval, tolerance: interval)
        }
    }

    // MARK: - Placing

    /// 各窗口之间没有 `await`，因此整个房间在一个可见步骤内落定。
    private static func place(
        _ placements: [RoomPlan.Placement], in snapshot: RoomWindowSweep.Snapshot
    ) {
        let targets = placements.compactMap { placement in
            snapshot.elements[placement.handle].map { (frame: placement.frame, element: $0) }
        }
        // 每个应用只做一次抑制和恢复：该标志是以应用为作用域的。
        for group in Dictionary(grouping: targets, by: { $0.element.app.processIdentifier }).values {
            let restore = AXWindowAccess.suppressEnhancedUserInterface(on: group[0].element.application)
            defer { restore() }
            for target in group { write(target.frame, to: target.element.window) }
        }
    }

    private static func write(_ frame: CGRect, to window: AXUIElement) {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        if AXWindowAccess.bool(window, kAXMinimizedAttribute) == true {
            _ = AXWindowAccess.unminimize(window)
        }
        // 在写入前检查，因此无法定位的窗口会保持原样。
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return }
        _ = AXWindowAccess.write(
            frame, anchor: .topLeading, to: window, current: current,
            canResize: AXWindowAccess.isSettable(kAXSizeAttribute, on: window), canvas: nil)
    }

    /// AX 不上报最小尺寸，因此一次被拒绝的缩放能教会它；再问一次以排除延迟。
    private static func learnMinimums(
        from plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, into store: RoomMinimumSizeStore
    ) async -> Bool {
        let refusing = plan.placements.filter { placement in
            guard let window = snapshot.elements[placement.handle]?.window,
                let actual = AXWindowAccess.frame(of: window)
            else { return false }
            return exceeds(actual.size, placement.frame.size)
        }
        guard !refusing.isEmpty else { return false }
        for placement in refusing {
            guard let window = snapshot.elements[placement.handle]?.window else { continue }
            _ = AXWindowAccess.setSize(placement.frame.size, on: window)
        }
        try? await Task.sleep(for: settleDelay)
        var learned = false
        for placement in refusing {
            guard let element = snapshot.elements[placement.handle],
                let actual = AXWindowAccess.frame(of: element.window)
            else { continue }
            let wanted = placement.frame.size
            let refused = CGSize(
                width: actual.width > wanted.width + slack ? actual.width : 0,
                height: actual.height > wanted.height + slack ? actual.height : 0)
            if store.learn(refused, for: element.bundleID) { learned = true }
        }
        return learned
    }

    private static func exceeds(_ actual: CGSize, _ wanted: CGSize) -> Bool {
        actual.width > wanted.width + slack || actual.height > wanted.height + slack
    }

    /// 从后往前、一次一个应用，以确保主窗口最终置顶并聚焦。
    private static func raise(_ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot) async {
        let elements = plan.placements.compactMap { snapshot.elements[$0.handle] }
        guard let main = elements.first else { return }
        for element in elements.dropFirst().reversed() {
            AXWindowAccess.raise(element.window, in: element.application)
            try? await Task.sleep(for: raisePacing)
        }
        AXWindowAccess.focus(main.window, in: main.application, of: main.app)
    }

    /// 对晚到或被弹回的 frame 做一次纠正；不做循环，否则会抖动。
    private static func verify(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, minimums: RoomMinimumSizeStore
    ) {
        let off = plan.placements.filter { placement in
            guard let element = snapshot.elements[placement.handle],
                let actual = AXWindowAccess.frame(of: element.window)
            else { return false }
            return !lands(actual, on: placement.frame, minimum: minimums.size(for: element.bundleID))
        }
        place(off, in: snapshot)
    }

    /// 足够接近：在应用取整误差内，或仅因它所保留的最小尺寸而偏大。
    private static func lands(_ actual: CGRect, on wanted: CGRect, minimum: CGSize) -> Bool {
        let width =
            abs(actual.width - wanted.width) <= resizeSlack
            || actual.width <= max(wanted.width, minimum.width) + slack
        let height =
            abs(actual.height - wanted.height) <= resizeSlack
            || actual.height <= max(wanted.height, minimum.height) + slack
        return width && height && abs(actual.minX - wanted.minX) <= slack
            && abs(actual.minY - wanted.minY) <= slack
    }

    // MARK: - Stepping back

    /// 没有 ID 的窗口，或回家写入失败的窗口，宁可原地不动也不冒险丢失。
    private static func park(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) -> Int {
        let screens = snapshot.screens.map(\.screen)
        var parked = 0
        for handle in plan.parks {
            guard let window = snapshot.window(handle), let element = snapshot.elements[handle],
                let windowID = window.windowID,
                let host = WindowPlacementEngine.screen(containing: window.frame, in: screens)
                    ?? screens.first,
                ledger.record(
                    RoomParkingLedger.Entry(
                        windowID: windowID, bundleID: window.bundleID, title: window.title,
                        frame: window.frame))
            else { continue }
            let others = screens.filter { $0.id != host.id }.map(\.frame)
            let origin = RoomParking.origin(
                for: window.frame.size, on: host.visibleFrame, avoiding: others)
            if AXWindowAccess.setPosition(origin, on: element.window) { parked += 1 }
        }
        return parked
    }

    /// 即将隐藏的应用会带走它的窗口，因此它们中任何一个都不能继续停泊。
    private static func returnWindowsOfHiddenApps(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) {
        let staying = Set(plan.placements.map(\.handle)).union(plan.parks)
        let screens = snapshot.screens.map(\.screen.frame)
        let returned = snapshot.windows.compactMap { window -> UInt32? in
            guard !staying.contains(window.handle), let element = snapshot.elements[window.handle]
            else { return nil }
            return unpark(window, element: element, screens: screens, ledger: ledger)
        }
        ledger.forget(returned)
    }

    /// 窗口回到原位后的 ID；返回 nil 则将其回家路径留在磁盘上供下次尝试。
    private static func unpark(
        _ window: RoomLiveWindow, element: WindowInventory.Element, screens: [CGRect],
        ledger: RoomParkingLedger
    ) -> UInt32? {
        guard let windowID = window.windowID, let entry = ledger.entry(for: windowID),
            entry.bundleID == window.bundleID
        else { return nil }
        let home = RoomParking.returnFrame(for: entry.frame, screens: screens)
        let restore = AXWindowAccess.suppressEnhancedUserInterface(on: element.application)
        defer { restore() }
        write(home, to: element.window)
        guard let now = AXWindowAccess.frame(of: element.window),
            abs(now.minX - home.minX) <= resizeSlack, abs(now.minY - home.minY) <= resizeSlack
        else { return nil }
        return windowID
    }

    /// 活跃应用无法隐藏，因此房间的主窗口会被首先聚焦。
    private static func hideApps(keeping keeps: Set<String>) -> Set<pid_t> {
        var hidden = Set<pid_t>()
        for app in WindowInventory.candidates()
        where !app.isHidden && !keeps.contains(app.bundleIdentifier ?? "") {
            if !app.hide() {
                AXWindowAccess.setHidden(
                    true, application: AXWindowAccess.application(for: app.processIdentifier))
            }
            hidden.insert(app.processIdentifier)
        }
        return hidden
    }

    /// 之前停泊的窗口只有在确认它大部分回到原位后才会被遗忘。
    private static func forgetPlacedWindows(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) {
        let back = plan.placements.compactMap { placement -> UInt32? in
            guard let windowID = snapshot.window(placement.handle)?.windowID,
                ledger.entry(for: windowID) != nil,
                let window = snapshot.elements[placement.handle]?.window,
                let actual = AXWindowAccess.frame(of: window)
            else { return nil }
            let shared = actual.intersection(placement.frame)
            let area = placement.frame.width * placement.frame.height
            return !shared.isNull && shared.width * shared.height >= area / 2 ? windowID : nil
        }
        ledger.forget(back)
    }

    private static func show(_ app: NSRunningApplication) {
        guard !app.unhide() else { return }
        AXWindowAccess.setHidden(
            false, application: AXWindowAccess.application(for: app.processIdentifier))
    }
}
