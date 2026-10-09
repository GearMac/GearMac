// 文件职责：编排菜单搜索——解析目标应用、驱动 Session 读取菜单，并把激活请求转化为 AX 按下。
// 分层：Coordinator；`@MainActor`，与调色板/权限/设置协作，不直接渲染视图。
import AppKit

/// 菜单搜索的编排者：负责目标应用解析、快照加载与菜单项激活。
@MainActor
final class MenuSearchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: MenuSearchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// 当前打开的快照所属的应用；激活时始终针对它重新解析，绝不改换目标。
    private var frozenApp: NSRunningApplication?
    /// 所有行共用的一个解码结果；每次展示只解析一次，避免列表反复读取图标。
    private(set) var frozenIconURL: URL?
    private(set) var frozenIconStamp: Int = 0

    /// 注入设置、应用索引、Session、调色板状态与核心对象。
    init(
        settings: AppSettings, appIndex: AppIndex, session: MenuSearchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 按设置切换命令可见性；关闭导航时重置会话并退回启动器模式。
    func applyEnabled() {
        appIndex.setCommandsVisible([.searchMenuItems], settings.navigationEnabled)
        guard !settings.navigationEnabled else { return }
        session.reset()
        if palette.mode == .menuSearch { palette.prepare(mode: .launcher) }
    }

    /// 检查辅助功能权限后打开菜单搜索面板。
    func show() {
        guard settings.navigationEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        paletteCoordinator.togglePalette(mode: .menuSearch)
    }

    /// 每次打开都重新遍历（包括恢复窗口）：隐藏时已丢弃上一次快照。
    func load() {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        let app = paletteCoordinator.targetApp
        frozenApp = app
        if let url = app?.bundleURL {
            frozenIconURL = url
            frozenIconStamp = FileIconStamp.value(for: url)
        } else {
            frozenIconURL = nil
            frozenIconStamp = 0
        }
        let target = MenuSearchTarget.classify(
            appName: app?.localizedName,
            isSelf: app?.bundleIdentifier == Bundle.main.bundleIdentifier,
            hasMenuBar: app?.activationPolicy == .regular,
            isExcluded: app?.bundleIdentifier
                .map(settings.menuSearchDisabledApps.contains) ?? false)
        switch target {
        case .searchable:
            if let app {
                session.startWalk(
                    target: target, pid: app.processIdentifier,
                    showsAppleMenu: settings.menuSearchShowsAppleMenu)
            } else {
                session.present(target: .noApplication, snapshot: [])
            }
        case .excluded, .selfTarget, .menuLess, .noApplication:
            session.present(target: target, snapshot: [])
        }
    }

    /// 针对冻结的目标应用重新解析菜单项并执行按下；失败时上报通知。
    func activate(_ item: MenuSearchItem) {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        guard let app = frozenApp, !app.isTerminated else {
            Task { await self.reportGone(targetName: session.targetName) }
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        app.activate()
        let application = AXMenuAccess.application(for: app.processIdentifier)
        guard
            let leaf = AXMenuAccess.resolveLeaf(
                in: application, path: item.parentComponents, title: item.title),
            AXMenuAccess.isActionable(leaf),
            AXMenuAccess.press(leaf)
        else {
            Task { await self.reportPressFailure(item: item) }
            return
        }
    }

    // MARK: - Reporting

    /// 上报缺少辅助功能权限，并在用户选择时打开系统设置。
    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: settings.text(MenuSearchKey.permissionTitle),
            message: settings.text(MenuSearchKey.permissionMessage),
            symbol: "menubar.rectangle",
            recovery: settings.text(MenuSearchKey.permissionRecovery))
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    /// 上报目标应用已退出、无法激活菜单项。
    private func reportGone(targetName: String?) async {
        await core.showNotice(
            title: settings.text(MenuSearchKey.goneTitle),
            message: targetName.map {
                String(format: settings.text(MenuSearchKey.goneMessageApp), $0)
            }
                ?? settings.text(MenuSearchKey.goneMessageGeneric),
            symbol: "menubar.rectangle", tone: .danger)
    }

    /// 上报菜单在按下前已变化、需要重新搜索。
    private func reportPressFailure(item: MenuSearchItem) async {
        await core.showNotice(
            title: String(
                format: settings.text(MenuSearchKey.pressFailedTitle), item.title),
            message: settings.text(MenuSearchKey.pressFailedMessage),
            symbol: "menubar.rectangle", tone: .danger)
    }
}
