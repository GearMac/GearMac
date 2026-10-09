// 文件职责：定义菜单栏入口的 SwiftUI 视图：图标标签（MenuBarLabel）与下拉菜单（MenuBarMenu）。
// 分层：UI（SwiftUI 视图）；只读取 AppCore 的状态与动作，不持有任何功能状态。
import SwiftUI

/// GearMac 自己的菜单栏图标；它不携带任何功能状态，因此没有任何功能能隐藏或改变它的形态。
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image("MenuBarIcon")
            .accessibilityLabel(appName)
    }
}

/// 状态栏下拉菜单：提供打开启动器、剪贴板历史、检查更新、支持与设置等入口。
struct MenuBarMenu: View {
    let appName: String

    /// 读取 `language` 会登记 Observation 依赖，因此切换语言后菜单文案即时更新。
    private var settings: AppSettings { AppCore.shared.settings }

    var body: some View {
        Button(format(MenuBarKey.openFormat)) {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        // 通过 Observation 读取，因此关闭该功能时对应菜单项会一并消失。
        if settings.clipboardEnabled {
            Button(settings.text(MenuBarKey.clipboardHistory)) {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
        }
        Divider()
        Button(settings.text(MenuBarKey.checkForUpdates)) {
            AppCore.shared.updateCoordinator.checkForUpdates()
        }
        Button(format(MenuBarKey.supportFormat)) { AppCore.shared.supportCoordinator.showSupport() }
        Button(settings.text(MenuBarKey.settings)) { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // 不绑定 ⌘Q：应用菜单已把它绑到「关闭设置」，两个互相矛盾的 ⌘Q 会造成误导。
        Button(format(MenuBarKey.quitFormat)) { NSApp.terminate(nil) }
    }

    /// 带应用名的入口文案：译文里以 `%@` 占位，由 `appName` 填充。
    private func format(_ key: MenuBarKey) -> String {
        String(format: settings.text(key), appName)
    }
}
