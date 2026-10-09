// 文件职责：管理设置窗口的生命周期与导航会话，把「打开某个设置页/锚点」的请求落实到窗口上。
// 分层：Coordinator；同时只维护一个设置窗口，不持有偏好模型本身。
import SwiftUI

/// 设置窗口的生命周期，与面板相互独立：两者都不会打开或关闭对方。
@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    /// 仅用于环境注入——绝不用于承载本类型自己拥有的状态。
    private unowned let core: AppCore
    /// 已打开窗口的导航会话；它由窗口的 chrome 与视图树持有，因此这里会自动置为 nil。
    private weak var navigation: SettingsNavigationState?
    /// 同一个会话持有其临时的编辑器栈；设置窗口关闭后不会有面板残留。
    private weak var editorPresenter: SettingsEditorPresenter?

    /// 用共享的 `AppCore` 创建协调器，并预置一个「设置」窗口控制器。
    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Settings", contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    /// 新建窗口会直接落在 `tab` 上；已打开的窗口则导航过去，并把这次跳转记入历史。
    /// `tab` 为 nil 时只把窗口显示出来，因此重新打开最小化的窗口会保留原来的页面。
    func showSettings(tab: SettingsTab? = nil, revealing target: SettingsTarget? = nil) {
        if window.focus() {
            if let tab { navigation?.select(tab, revealing: target) }
            return
        }
        let navigation = SettingsNavigationState(tab: tab ?? .general)
        navigation.select(navigation.tab, revealing: target)
        let editorPresenter = SettingsEditorPresenter(core: core, navigation: navigation)
        self.navigation = navigation
        self.editorPresenter = editorPresenter
        let hosting = NSHostingController(
            rootView: SettingsRootView().settingsEnvironment(
                core: core, navigation: navigation, editorPresenter: editorPresenter))
        // Keep the window's size authoritative: an unconstrained fill would drive the frame.
        hosting.sizingOptions = []
        // The back/forward chevrons, the pane title and the sidebar's search field all ride on it.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
        editorPresenter.attach(to: hosting.view.window)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    /// ⌘Q 和窗口的关闭按钮都会走到这里；App 本身继续运行。
    func closeSettings() {
        editorPresenter?.dismissAll()
        window.close()
    }

    /// 若已有设置窗口则将其置前，并返回是否成功。
    func focusExisting() -> Bool {
        window.focus()
    }
}
