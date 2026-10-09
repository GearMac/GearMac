// 文件职责：窗口切换器协调器，负责快捷键唤起、步进选择、松开修饰键时切换、窗口抬升与权限提示。
// 分层：Coordinator；@MainActor，通过本地事件监听器把握「按住/松开」节奏。
import AppKit

/// 窗口切换功能的协调器：管理唤出、步进、切换与权限提示。
@MainActor
final class WindowSwitchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: WindowSwitchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// 当重复按下且仍按住修饰键时启用：松开即切换，行为类似 ⌘Tab。
    private var releaseMonitor: Any?
    /// 参与「按住不放」判断的修饰键集合。
    private static let chordModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(
        settings: AppSettings, appIndex: AppIndex, session: WindowSwitchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 根据设置同步窗口切换命令的可见性；功能关闭时重置会话并返回启动器模式。
    func applyEnabled() {
        appIndex.setCommandsVisible([.switchWindows], settings.navigationEnabled)
        guard !settings.navigationEnabled else { return }
        session.reset()
        if palette.mode == .switchWindows { palette.prepare(mode: .launcher) }
    }

    /// 唤出切换器；已在展示时改为步进，否则先清理旧监听再打开面板。
    func show() {
        guard settings.navigationEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        if paletteCoordinator.isShowing(.switchWindows) { return step() }
        disarmSwitchOnRelease()
        paletteCoordinator.togglePalette(mode: .switchWindows)
    }

    /// 首次步进落在当前窗口之后的一个窗口上，也就是列表初始选中的位置。
    private func step() {
        let count = session.filtered.count
        guard count > 0 else { return }
        palette.selection = (palette.selection + 1) % count
        palette.followToken = UUID()
        armSwitchOnRelease()
    }

    /// 单次按下仍然用于搜索：只有按住组合键并再次步进时，才在松开时切换。
    private func armSwitchOnRelease() {
        let held = NSEvent.modifierFlags.intersection(Self.chordModifiers)
        guard !held.isEmpty, releaseMonitor == nil else { return }
        releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            let event = $0
            guard let self, event.modifierFlags.isDisjoint(with: held) else { return event }
            self.switchOnRelease()
            return event
        }
    }

    /// 移除松开监听的本地事件监视器。
    private func disarmSwitchOnRelease() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    /// 松开修饰键时，切换到当前选中项。
    private func switchOnRelease() {
        disarmSwitchOnRelease()
        let rows = session.filtered
        guard paletteCoordinator.isShowing(.switchWindows), rows.indices.contains(palette.selection)
        else { return }
        activate(rows[palette.selection])
    }

    /// 每次打开都重新扫描（包括重新唤起）：隐藏已丢弃上一次快照。
    func load() {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        session.present(WindowSwitchSweep.snapshot(ranks: WindowZOrder.appRanks()))
    }

    /// 切换到指定条目：处理权限、元素失效与最小化恢复，并抬升窗口。
    func activate(_ entry: WindowSwitchEntry) {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        // 在隐藏之前解析：隐藏会重置会话，从而清空元素表。
        guard let element = session.element(for: entry.handle), !element.app.isTerminated else {
            Task { await self.reportGone(entry) }
            return
        }
        // 恢复焦点会重新激活被替换的 App，与下面的抬升操作竞争。
        paletteCoordinator.hidePalette(restoreFocus: false)
        if entry.isMinimized { _ = AXWindowAccess.unminimize(element.window) }
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
    }

    // MARK: - Reporting

    /// 在权限缺失时提示失败，并可打开辅助功能设置。
    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: settings.text(WindowSwitcherKey.permissionTitle),
            message: settings.text(WindowSwitcherKey.permissionMessage),
            symbol: "macwindow.on.rectangle",
            recovery: settings.text(WindowSwitcherKey.permissionRecovery))
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    /// 目标窗口已关闭而无法切换时的提示。
    private func reportGone(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: String(
                format: settings.text(WindowSwitcherKey.goneTitle), entry.displayTitle),
            message: settings.text(WindowSwitcherKey.goneMessage),
            symbol: "macwindow.on.rectangle", tone: .danger)
    }
}
