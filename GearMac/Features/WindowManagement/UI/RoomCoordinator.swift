// 文件职责：房间（Rooms）功能的核心协调器，负责房间的存在性、进入流程与门禁、预览、选择器及清理，并编排窗口搬运。
// 分层：Coordinator；@MainActor @Observable，所有窗口操作经串行任务队列执行，避免两趟搬运相互抵消。
// 改编自 Rooms (MIT)：https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit

/// 持有房间：存在性、唯一的进入入口及其门禁、预览、选择器与清理。
@MainActor
@Observable
final class RoomCoordinator {
    @ObservationIgnored private let store: RoomStore
    @ObservationIgnored private let minimums: RoomMinimumSizeStore
    @ObservationIgnored private let ledger: RoomParkingLedger
    @ObservationIgnored private let session: RoomSession
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let appIndex: AppIndex
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private let visibility: VisibilityStore
    @ObservationIgnored private let ranking: LauncherRankingStore
    @ObservationIgnored private let aliases: AliasStore
    @ObservationIgnored private let palette: PaletteState
    @ObservationIgnored private let paletteCoordinator: PaletteCoordinator
    /// 仅用于对话框与消息 HUD 展示；该类不持有它的任何状态。
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let preview = RoomPreviewController()
    /// 窗口操作按顺序逐个执行：两趟同时进行会互相抵消。
    @ObservationIgnored private var work: Task<Void, Never>?
    /// 当 ↵ 已把预览交给其下移入的窗口时置位。
    @ObservationIgnored private var isEntering = false
    /// 选择器预选其窗口的房间，在读取桌面之前暂存。
    @ObservationIgnored private var pendingPreselection: Room?
    /// 自功能上次关闭以来被房间隐藏的 App；用户自己的 ⌘H 不会记录在这里。
    @ObservationIgnored private var hiddenByRooms = Set<pid_t>()
    /// 进行中的桌面读取，使同一轮内的两次打开只扫描一次。
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// 最近进入且尚未离开的房间，Rooms 界面会标记它。
    private(set) var currentRoomID: UUID?

    init(
        store: RoomStore, minimums: RoomMinimumSizeStore, ledger: RoomParkingLedger,
        session: RoomSession, settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.minimums = minimums
        self.ledger = ledger
        self.session = session
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private static let commands: Set<CommandID> = [.switchRoom, .createRoom]

    // MARK: - Feature presence

    /// 根据设置同步房间在启动器中的可见性与命令注册状态。
    func applyRoomsPresence() {
        let enabled = settings.windowManagementEnabled
        appIndex.setWindowRooms(enabled && settings.windowRoomsShowInLauncher ? store.rooms : [])
        appIndex.setCommandsVisible(Self.commands, enabled)
        appIndex.setCommandsListed(Self.commands, settings.windowRoomsShowInLauncher)
    }

    /// 关闭功能时把所有被停放的窗口带回原位，并恢复房间隐藏的 App。
    func applyEnabled() {
        applyRoomsPresence()
        guard !settings.windowManagementEnabled else { return }
        if palette.mode == .rooms || palette.mode == .roomWindows { palette.prepare(mode: .launcher) }
        let hidden = hiddenByRooms
        hiddenByRooms = []
        currentRoomID = nil
        inTurn { [ledger] in await RoomRunner.restoreEverything(hiddenApps: hidden, ledger: ledger) }
    }

    /// 崩溃遗留的停放窗口在启动时回到原位；不恢复隐藏项，也不移动其他窗口。
    func recoverParkedWindows() {
        guard !ledger.isEmpty, Permissions.isAccessibilityTrusted() else { return }
        inTurn { [ledger] in RoomRunner.returnParkedWindows(ledger: ledger) }
    }

    /// 同步执行，确保 GearMac 退出后没有窗口留在屏幕外。
    func prepareForTermination() {
        work?.cancel()
        work = nil
        preview.hide()
        RoomRunner.returnParkedWindows(ledger: ledger)
    }

    // MARK: - The Rooms screen

    /// 打开 Rooms 界面；无辅助功能权限时先申请并提示。
    func showRooms() {
        guard settings.windowManagementEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { await reportPermissionFailure() }
            return
        }
        paletteCoordinator.togglePalette(mode: .rooms)
    }

    /// 每次打开都重新读取桌面，在界面出现一轮之后执行，避免等待 AX。
    func load() {
        guard settings.windowManagementEnabled, Permissions.isAccessibilityTrusted() else { return }
        guard !session.isLoaded, loading == nil else { return }
        loading = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            self.loading = nil
            guard !Task.isCancelled, self.isScreenOpen else { return }
            self.session.present(
                RoomWindowSweep.snapshot(), parked: Set(self.ledger.entries.keys))
            self.applyPreselection()
        }
    }

    /// 离开两个 Rooms 界面时丢弃桌面快照与预览，除非有房间正在进入。
    func screensDidClose() {
        pendingPreselection = nil
        loading?.cancel()
        loading = nil
        session.reset()
        if !isEntering { preview.hide() }
    }

    /// 面板隐藏时重置会话并隐藏预览（正在进入时除外）。
    func paletteDidHide() {
        guard !isEntering else { return }
        pendingPreselection = nil
        loading?.cancel()
        loading = nil
        session.reset()
        preview.hide()
    }

    private var isScreenOpen: Bool {
        palette.isVisible && (palette.mode == .rooms || palette.mode == .roomWindows)
    }

    /// 根据查询过滤房间：按最近进入排序做模糊匹配，并追加编辑/新建行。
    func rows(for query: String) -> [RoomRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recent = store.rooms.sorted(by: Room.enteredMoreRecently)
        let folded = FuzzyMatch.Query(trimmed)
        let matched =
            folded.isEmpty
            ? recent
            : recent.enumerated()
                .compactMap { position, room -> (Room, Int, Int)? in
                    let fields = SearchFields(
                        [SearchAlias.name(room.name)]
                            + room.windows.map { SearchAlias.owner($0.appName) })
                    return SearchRelevance.quality(folded, fields: fields).map { (room, $0, position) }
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
                .map(\.0)
        var rows = matched.map(RoomRow.room)
        if !trimmed.isEmpty {
            let existing = store.room(named: trimmed)
            rows.append(existing.map { .edit($0) } ?? .create(name: trimmed))
        }
        return rows
    }

    /// 房间在目标显示器上适用的布局。
    func layout(of room: Room) -> RoomLayoutKind {
        room.layout(onDisplay: targetDisplayUUID)
    }

    /// 当前生效的界面语言；供屏幕在无法使用 `@Environment` 的场景（如主操作标题）取用。
    var language: AppLanguage { settings.resolvedLanguage }

    /// Tab：切换到此显示适用的下一个布局，预览随之滑动。
    func cycleLayout(of room: Room, backwards: Bool) {
        guard let snapshot = session.snapshot, let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return }
        let choices = RoomPlan.layoutChoices(
            for: room, windows: snapshot.windows, on: screen, gap: gap,
            minimums: minimums.sizes, claimed: store.claimedWindowIDs(excluding: room.id))
        guard
            let next = RoomPlan.nextLayout(
                after: room.layout(onDisplay: screen.display.uuid), in: choices,
                backwards: backwards)
        else {
            core.showMessage(
                settings.text(WindowKey.roomOnlyOneLayout), tone: .neutral)
            return
        }
        // 界面会即时预览所选房间的变化，因此卡片由这里驱动滑动。
        store.setLayout(next, for: room.id, onDisplay: screen.display.uuid)
    }

    /// 房间在该显示器上的外观，依据界面读取的桌面快照绘制。
    func preview(_ room: Room?) {
        guard let room, let snapshot = session.snapshot,
            let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return preview.hide() }
        let plan = RoomPlan.make(
            room, windows: snapshot.windows, on: screen, gap: gap, minimums: minimums.sizes,
            claimed: store.claimedWindowIDs(excluding: room.id))
        let cards = plan.placements.compactMap { placement in
            snapshot.window(placement.handle).map { card(for: $0, at: placement.frame) }
        }
        guard !cards.isEmpty else { return preview.hide() }
        // 由后往前绘制，使主窗口的卡片最终位于顶层，与其窗口本身一致。
        preview.show(cards.reversed(), avoiding: paletteCoordinator.panelFrame)
    }

    // MARK: - Entering

    /// Rooms 行、启动器条目、快捷键与面板共用的唯一进入入口。
    func enterRoom(id: UUID) {
        guard settings.windowManagementEnabled, let room = store.room(id: id) else { return }
        // 窗口在其下方移入时预览保持显示，随后淡出。
        isEntering = preview.isShowing
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let context = RoomRunner.Context(
            gap: gap, displayUUID: targetDisplayUUID,
            claimed: store.claimedWindowIDs(excluding: room.id), minimums: minimums, ledger: ledger)
        inTurn { [weak self] in
            let outcome = await RoomRunner.enter(room, context: context)
            guard let self else { return }
            self.isEntering = false
            self.preview.hide(settling: true)
            self.session.reset()
            self.hiddenByRooms.formUnion(outcome.hiddenApps)
            if outcome.placed > 0 {
                self.currentRoomID = room.id
                self.store.markEntered(id: room.id, at: Date())
            }
            await self.report(outcome, for: room)
        }
    }

    /// 把窗口操作排入串行队列：等待上一项完成后执行，任务取消则不执行。
    private func inTurn(_ body: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await body()
        }
    }

    // MARK: - Making and editing rooms

    /// 为 Rooms 界面上命名的房间打开选择器；若尚无名称，则先回到该界面。
    func createRoom(named name: String = "") {
        guard settings.windowManagementEnabled else { return }
        guard !name.isEmpty else {
            if paletteCoordinator.isShowing(.rooms) { nameIsMissing() } else { showRooms() }
            return
        }
        guard Permissions.ensureAccessibility() else {
            Task { await reportPermissionFailure() }
            return
        }
        openPicker(editing: nil, name: name)
    }

    /// 打开选择器以编辑已有房间的窗口成员。
    func editWindows(of room: Room) {
        openPicker(editing: room, name: room.name)
    }

    private func openPicker(editing room: Room?, name: String) {
        if paletteCoordinator.isVisible {
            palette.push(mode: .roomWindows)
        } else {
            paletteCoordinator.showPalette(mode: .roomWindows)
        }
        session.beginPicking(named: name, editing: room?.id, picked: [])
        // push 不会经由协调器打开界面，因此在这里读取桌面。
        load()
        preselect(room)
    }

    /// 被编辑房间的窗口按其顺序初始选中；新房间则初始不选任何项。
    private func preselect(_ room: Room?) {
        pendingPreselection = room
        applyPreselection()
    }

    /// 在桌面读取完成后执行：此前没有可匹配的窗口。
    private func applyPreselection() {
        guard let room = pendingPreselection, let snapshot = session.snapshot else { return }
        pendingPreselection = nil
        let assignment = RoomWindowMatcher.assign(
            room.windows, to: snapshot.windows, claimed: store.claimedWindowIDs(excluding: room.id))
        // 没有打开窗口的成员以其 App 形式保留在房间中，不会被丢弃。
        let picks = room.windows.indices.map { index -> RoomSession.Pick in
            if let live = assignment[index] { return .window(handle: snapshot.windows[live].handle) }
            let window = room.windows[index]
            return .app(
                RoomSession.App(
                    bundleID: window.bundleID, name: window.appName,
                    url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleID)))
        }
        // 同一 App 的两个已关闭窗口会合并为它们现在代表的那个 App。
        var seen = Set<RoomSession.Pick>()
        session.beginPicking(
            named: room.name, editing: room.id, picked: picks.filter { seen.insert($0).inserted })
        previewPicked()
    }

    /// 切换某个窗口/App 的选中状态，并同步刷新预览。
    func togglePick(_ pick: RoomSession.Pick) {
        session.togglePick(pick)
        previewPicked()
    }

    /// 匹配 `query` 的已打开窗口，然后是未打开的 App：它们以 App 形式加入。
    func pickerRows(for query: String) -> [RoomPickerRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows =
            trimmed.isEmpty
            ? session.pickable
            : session.pickable.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.appName.localizedCaseInsensitiveContains(trimmed)
            }
        let open = Set(session.pickable.map(\.bundleID))
        let pickedApps = session.picked.compactMap { pick -> RoomSession.App? in
            guard case .app(let app) = pick else { return nil }
            return app
        }
        // 无查询时只显示已选中的 App：整个「应用程序」文件夹只会造成干扰。
        let apps =
            trimmed.isEmpty
            ? pickedApps
            : appIndex.apps.lazy
                .filter { $0.kind == .application && $0.name.localizedCaseInsensitiveContains(trimmed) }
                .compactMap { entry -> RoomSession.App? in
                    guard let bundleID = entry.bundleID, !open.contains(bundleID) else { return nil }
                    return RoomSession.App(bundleID: bundleID, name: entry.name, url: entry.url)
                }
                .prefix(Self.appResultLimit).map { $0 }
        return windows.map(RoomPickerRow.window) + apps.map(RoomPickerRow.app)
    }

    private static let appResultLimit = 30

    /// 已选成员在此处将构成的房间：Auto 布局，按选取顺序排列。
    func previewPicked() {
        guard let snapshot = session.snapshot, let screen = snapshot.screen(uuid: targetDisplayUUID)
        else { return }
        let members = session.picked.compactMap { member(for: $0, in: snapshot) }
        let frames = RoomLayoutEngine.frames(
            count: members.count, kind: .auto, in: screen.screen.visibleFrame, gap: gap,
            minimums: members.map { minimums.size(for: $0.bundleID) })
        let cards = zip(members, frames).map { member, frame in
            RoomPreviewCard(
                id: member.id, frame: frame, appName: member.appName, title: member.title,
                appURL: member.appURL)
        }
        guard !cards.isEmpty else { return preview.hide() }
        preview.show(cards.reversed(), avoiding: paletteCoordinator.panelFrame)
    }

    private struct Member {
        let id: String
        let bundleID: String
        let appName: String
        let title: String
        let appURL: URL?
    }

    private func member(for pick: RoomSession.Pick, in snapshot: RoomWindowSweep.Snapshot) -> Member? {
        switch pick {
        case .window(let handle):
            guard let window = snapshot.window(handle) else { return nil }
            return Member(
                id: card(for: window, at: .zero).id, bundleID: window.bundleID,
                appName: window.appName, title: window.title, appURL: window.appURL)
        case .app(let app):
            return Member(
                id: "app:" + app.bundleID, bundleID: app.bundleID, appName: app.name, title: "",
                appURL: app.url)
        }
    }

    /// 未输入房间名时的提示。
    func nameIsMissing() {
        core.showMessage(settings.text(WindowKey.roomNameMissing), tone: .neutral)
    }

    /// 选择器中的 ⌘↵：已选窗口与 App 按选取顺序组成该房间。
    func savePicked() {
        guard let snapshot = session.snapshot else { return }
        let picks = session.picked
        guard !picks.isEmpty else {
            core.showMessage(settings.text(WindowKey.roomPickOne), tone: .neutral)
            return
        }
        let name = session.roomName
        let base = session.editingID.flatMap(store.room(id:)) ?? Room(name: name)
        let windows = picks.compactMap { pick -> RoomLiveWindow? in
            guard case .window(let handle) = pick else { return nil }
            return snapshot.window(handle)
        }
        var room = base
        if !windows.isEmpty {
            guard let (learned, _) = learn(base, from: windows, in: snapshot, keepsOrder: true)
            else { return }
            room = learned
        }
        // `learn` 保持选取顺序，因此其窗口逐个插回 App 之间。
        var learnedWindows = room.windows.makeIterator()
        room.windows = picks.compactMap { pick in
            switch pick {
            case .window: return learnedWindows.next()
            case .app(let app):
                return RoomWindow(bundleID: app.bundleID, appName: app.name, title: "")
            }
        }
        room.name = name
        do {
            if session.editingID == nil { try store.add(room) } else { try store.update(room) }
        } catch {
            core.showMessage(error.localizedMessage(settings.resolvedLanguage), tone: .danger)
            return
        }
        enterRoom(id: room.id)
    }

    /// 记住房间已打开窗口当前的排布：最接近的布局，或完全按现状。
    func rememberArrangement(of room: Room) {
        guard let snapshot = session.snapshot else { return }
        let assignment = RoomWindowMatcher.assign(
            room.windows, to: snapshot.windows, claimed: store.claimedWindowIDs(excluding: room.id))
        let arranged = room.windows.indices.filter { index in
            assignment[index].map { !snapshot.windows[$0].isMinimized && !snapshot.windows[$0].isAppHidden }
                ?? false
        }
        let windows = arranged.compactMap { assignment[$0].map { snapshot.windows[$0] } }
        // 按标题或 App 填充的成员会有新的 ID，只有匹配器知道它在此处。
        let kept = room.windows.indices.filter { !arranged.contains($0) }.map { room.windows[$0] }
        guard !windows.isEmpty else {
            core.showMessage(
                String(format: settings.text(WindowKey.roomNoneOpen), room.name), tone: .neutral)
            return
        }
        guard
            let (updated, reading) = learn(
                room, from: windows, keeping: kept, in: snapshot, keepsOrder: false)
        else { return }
        do {
            try store.update(updated)
        } catch {
            core.showMessage(error.localizedMessage(settings.resolvedLanguage), tone: .danger)
            return
        }
        core.showMessage(
            String(
                format: settings.text(WindowKey.roomRemembered), room.name,
                reading.kind.localizedTitle(settings.resolvedLanguage)), tone: .success)
    }

    /// 在大多数窗口共用的显示器上读取，因为排布信息就在那里。
    private func learn(
        _ room: Room, from windows: [RoomLiveWindow], keeping kept: [RoomWindow] = [],
        in snapshot: RoomWindowSweep.Snapshot, keepsOrder: Bool
    ) -> (Room, RoomArrangement.Reading)? {
        let screens = snapshot.screens.map(\.screen)
        let hosts = windows.map { WindowPlacementEngine.screen(containing: $0.frame, in: screens)?.id }
        let counts = Dictionary(grouping: hosts.compactMap { $0 }, by: { $0 }).mapValues(\.count)
        let host = counts.max { $0.value < $1.value }?.key
        guard
            let screen = snapshot.screens.first(where: { $0.screen.id == host })
                ?? snapshot.screen(uuid: targetDisplayUUID)
        else { return nil }
        let result = RoomArrangement.learn(
            room, from: windows, keeping: kept, on: screen, spansDisplays: counts.count > 1, gap: gap,
            minimums: windows.map { minimums.size(for: $0.bundleID) }, keepsOrder: keepsOrder)
        return (result.room, result.reading)
    }

    /// 确认后删除该房间，并清理其快捷键与启动器引用。
    func deleteRoom(_ room: Room) {
        Task { [weak self] in
            guard let self else { return }
            let confirmed = await self.core.confirm(
                title: String(
                    format: self.settings.text(WindowKey.deleteTitle), room.name),
                message: self.settings.text(WindowKey.roomDeleteMessage),
                symbol: Room.sfSymbol, confirmTitle: self.settings.text(WindowKey.actionDelete))
            guard confirmed, let removed = self.store.remove(id: room.id) else { return }
            if self.currentRoomID == removed.id { self.currentRoomID = nil }
            self.removeReferences(ids: [removed.id], entryIDs: [removed.entryID])
        }
    }

    /// 用导入的房间整体替换现有集合，并清理被移除项的引用；返回写入条数。
    @discardableResult
    func replaceRooms(_ incoming: [Room]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.rooms.map { ($0.id, $0) })
        let count = store.replace(with: incoming)
        let removed = Set(previous.keys).subtracting(store.rooms.map(\.id))
        removeReferences(ids: removed, entryIDs: Set(removed.compactMap { previous[$0]?.entryID }))
        return count
    }

    /// 清理被移除房间的快捷键绑定、收藏、可见性、别名与排序记录。
    private func removeReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.windowRoom(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs { ranking.reset(itemKey: entryID) }
    }

    // MARK: - Helpers

    private var gap: CGFloat { CGFloat(settings.windowGap) }

    /// 面板打开所在的显示器，使房间落在预览绘制的位置。
    private var targetDisplayUUID: String? {
        (settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary).flatMap(AXScreens.uuid)
    }

    private func card(for window: RoomLiveWindow, at frame: CGRect) -> RoomPreviewCard {
        RoomPreviewCard(
            id: window.windowID.map(String.init) ?? "\(window.bundleID)|\(window.handle)",
            frame: frame, appName: window.appName, title: window.title, appURL: window.appURL)
    }

    // MARK: - Reporting

    /// 汇报进入结果：权限受阻、无可放置窗口或部分窗口未打开。
    private func report(_ outcome: RoomRunner.Outcome, for room: Room) async {
        if outcome.isBlockedOnPermission { return await reportPermissionFailure() }
        guard outcome.placed > 0 else {
            await core.showNotice(
                title: String(
                    format: settings.text(WindowKey.roomEnterFailedTitle), room.name),
                message: settings.text(WindowKey.roomEnterFailedMessage),
                symbol: Room.sfSymbol, tone: .danger)
            return
        }
        let missing = Set(outcome.missing).sorted()
        guard !missing.isEmpty else { return }
        core.showMessage(
            String(
                format: settings.text(WindowKey.roomMissing), room.name,
                missing.joined(separator: ", ")), tone: .neutral)
    }

    /// 在权限缺失时提示失败，并可打开辅助功能设置。
    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: settings.text(WindowKey.permissionTitle),
            message: settings.text(WindowKey.roomPermissionMessage),
            symbol: Room.sfSymbol, recovery: settings.text(WindowKey.permissionRecovery))
        if openSettings { Permissions.openAccessibilitySettings() }
    }
}

/// Rooms 界面的一行：一个房间，或作为新房间提供的那个已输入名称。
enum RoomRow: Identifiable, Hashable {
    case room(Room)
    /// 输入的名称属于已有房间：重新选择它的窗口。
    case edit(Room)
    case create(name: String)

    var id: String {
        switch self {
        case .room(let room): room.entryID
        case .edit(let room): "edit:" + room.entryID
        case .create: "create-room"
        }
    }
}
