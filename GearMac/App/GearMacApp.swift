// 文件职责：应用入口（@main）：声明两个菜单栏场景（主菜单栏项与日历菜单栏项）、应用菜单命令，并桥接 AppKit AppDelegate。
// 分层：UI（SwiftUI App）；只做场景与命令声明，业务状态与窗口均由 AppCore/AppKit controller 管理。
import SwiftUI

/// 应用入口；把 AppKit 生命周期交给 `AppDelegate`，其余场景在 `body` 中声明。
@main
struct GearMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // 区分发布渠道："GearMac"、"GearMac-dev" 或 "GearMac Beta"。
    private let appName = Bundle.main.appDisplayName

    /// 两个彼此独立的菜单栏项：各由一个偏好控制，且互不读取对方状态。
    /// 只声明两个菜单栏场景；标题窗口和浮动面板由 AppKit controller 管理。
    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        MenuBarExtra(isInserted: calendarMenuBarInsertion) {
            CalendarMenuBarMenu()
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }
    }

    /// 在 body 中读取以接入 Observation；SwiftUI 会回传 binding，因此只有真正变化时才写入。
    private var menuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.showInMenuBar
        return Binding(
            get: { isInserted },
            set: { inserted in
                guard inserted != settings.showInMenuBar else { return }
                settings.showInMenuBar = inserted
            })
    }

    /// 通过 AppSettings 写入：把菜单栏项拖出必须停止时钟，并同步移动设置中的选择器。
    private var calendarMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.calendarMenuBarDisplay != .disabled && !isCalendarMenuBarHiddenWhenEmpty
        return Binding(
            get: { isInserted },
            set: { inserted in
                if inserted {
                    guard settings.calendarMenuBarDisplay == .disabled else { return }
                    settings.calendarMenuBarDisplay = .meetingIcon
                } else {
                    // SwiftUI 会把我们自己的移除动作回传到这里；只有用户拖出才意味着「关闭它」。
                    guard !isCalendarMenuBarHiddenWhenEmpty, settings.calendarMenuBarDisplay != .disabled
                    else { return }
                    settings.calendarMenuBarDisplay = .disabled
                }
            })
    }

    /// 在 body 中读取，因此当 coordinator 的标志翻转时 Observation 会重建场景。
    private var isCalendarMenuBarHiddenWhenEmpty: Bool {
        AppCore.shared.settings.calendarMenuBarHidesWhenEmpty
            && !AppCore.shared.calendarCoordinator.hasMenuBarEvent
    }

    /// 只声明而不用赋值给 `NSApp.mainMenu`：SwiftUI 会在任何场景变化时重建菜单。
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(menuText(MenuBarKey.aboutFormat)) { AppCore.shared.settingsCoordinator.showAbout() }
            Button(menuText(MenuBarKey.checkForUpdates)) {
                AppCore.shared.updateCoordinator.checkForUpdates()
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button(menuText(MenuBarKey.settings)) { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button(menuText(MenuBarKey.closeWindow)) {
                // 聊天窗口在最前时会自行关闭；否则 ⌘Q 归「设置」所有。
                guard !AppCore.shared.aiChatCoordinator.closeWindowIfKey() else { return }
                AppCore.shared.settingsCoordinator.closeSettings()
            }
            .keyboardShortcut("q")
        }
    }

    /// 应用菜单文案；读取 `language` 形成观察依赖，语言切换后菜单随之重建。
    private func menuText(_ key: MenuBarKey) -> String {
        String(format: AppCore.shared.settings.text(key), appName)
    }
}
