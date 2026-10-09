// 文件职责：启动器（Launcher）的本地化键与中英词表：条目类别标题、操作菜单、设置页与兜底文案。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 启动器界面、操作菜单与设置页的文案键。
enum LauncherKey: String, LocalizableKey {
    // 操作菜单
    case favoriteAdd = "launcher.action.favoriteAdd"
    case favoriteRemove = "launcher.action.favoriteRemove"
    case favoriteMoveUp = "launcher.action.favoriteMoveUp"
    case favoriteMoveDown = "launcher.action.favoriteMoveDown"
    case resetRanking = "launcher.action.resetRanking"
    case hideFromSearch = "launcher.action.hideFromSearch"
    case restartApplication = "launcher.action.restartApplication"
    case quitApplication = "launcher.action.quitApplication"
    case forceQuitApplication = "launcher.action.forceQuitApplication"
    case uninstallApplication = "launcher.action.uninstallApplication"
    case backgroundRefreshEnable = "launcher.action.backgroundRefreshEnable"
    case backgroundRefreshDisable = "launcher.action.backgroundRefreshDisable"
    case refreshNow = "launcher.action.refreshNow"
    case configureExtension = "launcher.action.configureExtension"
    case uninstallExtension = "launcher.action.uninstallExtension"
    case showInFinder = "launcher.action.showInFinder"
    case configureFallbacks = "launcher.action.configureFallbacks"

    // 前置卡片
    case cardCalculator = "launcher.card.calculator"
    case cardMeeting = "launcher.card.meeting"
    case cardColor = "launcher.card.color"

    // 分组与空态
    case sectionResults = "launcher.section.results"
    case sectionFavorites = "launcher.section.favorites"
    case sectionSuggestions = "launcher.section.suggestions"
    case sectionConfigureHelp = "launcher.section.configureHelp"
    case emptyNoApps = "launcher.empty.noApps"

    // 主操作
    case copyAnswer = "launcher.primary.copyAnswer"
    case copyColor = "launcher.primary.copyColor"
    case openInCalendar = "launcher.primary.openInCalendar"
    case joinMeeting = "launcher.primary.joinMeeting"
    case openApplication = "launcher.primary.openApplication"
    case copyColorAs = "launcher.primary.copyColorAs"

    // 紧凑收藏行
    case showAll = "launcher.compact.showAll"

    // 设置页
    case searchApps = "launcher.settings.searchApps"
    case searchApplications = "launcher.settings.searchApplications"
    case searchSystemSettings = "launcher.settings.searchSystemSettings"
    case addApplication = "launcher.settings.addApplication"
    case stopExcludingFormat = "launcher.settings.stopExcludingFormat"
    case fallbacksNothingToOffer = "launcher.settings.fallbacks.empty"
    case fallbacksFooter = "launcher.settings.fallbacks.footer"
    case moveUpFormat = "launcher.settings.moveUpFormat"
    case moveDownFormat = "launcher.settings.moveDownFormat"
    case offerAsFallbackFormat = "launcher.settings.offerAsFallbackFormat"
    case showInLauncherFormat = "launcher.settings.showInLauncherFormat"
    case enableFormat = "launcher.settings.enableFormat"
    case offHidesAll = "launcher.settings.offHidesAll"
    case nothingHereYet = "launcher.settings.nothingHereYet"
    case noMatchesFormat = "launcher.settings.noMatchesFormat"
    case addEllipsis = "launcher.settings.addEllipsis"
    case addScopeHelp = "launcher.settings.addScopeHelp"
    case restoreDefaults = "launcher.settings.restoreDefaults"
    case chooseScopesMessage = "launcher.settings.chooseScopesMessage"
    case addScopePrompt = "launcher.settings.addScopePrompt"

    // 兜底行
    case fallbackVerbQuickAI = "launcher.fallback.verb.quickAI"
    case fallbackVerbSearchFiles = "launcher.fallback.verb.searchFiles"
    case fallbackVerbRunShellCommand = "launcher.fallback.verb.runShellCommand"
    case fallbackVerbDefine = "launcher.fallback.verb.define"
    case fallbackVerbQuicklink = "launcher.fallback.verb.quicklink"
    case fallbackSectionTitleFormat = "launcher.fallback.sectionTitleFormat"

    // 条目类别：分组标题
    case kindApplicationSection = "launcher.kind.application.section"
    case kindSystemSettingsSection = "launcher.kind.systemSettings.section"
    case kindCommandSection = "launcher.kind.command.section"
    case kindQuickActionSection = "launcher.kind.quickAction.section"
    case kindCustomCommandSection = "launcher.kind.customCommand.section"
    case kindSnippetSection = "launcher.kind.snippet.section"
    case kindSystemActionSection = "launcher.kind.systemAction.section"
    case kindWindowCommandSection = "launcher.kind.windowCommand.section"
    case kindWindowLayoutSection = "launcher.kind.windowLayout.section"
    case kindRoomSection = "launcher.kind.room.section"
    case kindQuicklinkSection = "launcher.kind.quicklink.section"
    case kindAppleShortcutSection = "launcher.kind.appleShortcut.section"
    case kindExtensionSection = "launcher.kind.extension.section"
    case kindMeetingSection = "launcher.kind.meeting.section"

    // 条目类别：打开动词
    case kindApplicationVerb = "launcher.kind.application.verb"
    case kindSystemSettingsVerb = "launcher.kind.systemSettings.verb"
    case kindCommandVerb = "launcher.kind.command.verb"
    case kindQuickActionVerb = "launcher.kind.quickAction.verb"
    case kindCustomCommandVerb = "launcher.kind.customCommand.verb"
    case kindSnippetVerb = "launcher.kind.snippet.verb"
    case kindSystemActionVerb = "launcher.kind.systemAction.verb"
    case kindWindowCommandVerb = "launcher.kind.windowCommand.verb"
    case kindWindowLayoutVerb = "launcher.kind.windowLayout.verb"
    case kindRoomVerb = "launcher.kind.room.verb"
    case kindQuicklinkVerb = "launcher.kind.quicklink.verb"
    case kindAppleShortcutVerb = "launcher.kind.appleShortcut.verb"
    case kindExtensionVerb = "launcher.kind.extension.verb"
    case kindMeetingVerb = "launcher.kind.meeting.verb"

    // 条目类别：单数标签（行尾与副标题）
    case kindApplicationLabel = "launcher.kind.application.label"
    case kindSystemSettingsLabel = "launcher.kind.systemSettings.label"
    case kindCommandLabel = "launcher.kind.command.label"
    case kindQuickActionLabel = "launcher.kind.quickAction.label"
    case kindCustomCommandLabel = "launcher.kind.customCommand.label"
    case kindSnippetLabel = "launcher.kind.snippet.label"
    case kindSystemActionLabel = "launcher.kind.systemAction.label"
    case kindWindowCommandLabel = "launcher.kind.windowCommand.label"
    case kindWindowLayoutLabel = "launcher.kind.windowLayout.label"
    case kindRoomLabel = "launcher.kind.room.label"
    case kindQuicklinkLabel = "launcher.kind.quicklink.label"
    case kindAppleShortcutLabel = "launcher.kind.appleShortcut.label"
    case kindExtensionLabel = "launcher.kind.extension.label"
    case kindMeetingLabel = "launcher.kind.meeting.label"

    static let table: [String: L10nEntry] = [
        // 操作菜单
        LauncherKey.favoriteAdd.rawValue: L10nEntry("Add to Favorites", "添加到收藏"),
        LauncherKey.favoriteRemove.rawValue: L10nEntry("Remove from Favorites", "从收藏中移除"),
        LauncherKey.favoriteMoveUp.rawValue: L10nEntry("Move Favorite Up", "收藏上移"),
        LauncherKey.favoriteMoveDown.rawValue: L10nEntry("Move Favorite Down", "收藏下移"),
        LauncherKey.resetRanking.rawValue: L10nEntry("Reset Ranking", "重置排序"),
        LauncherKey.hideFromSearch.rawValue: L10nEntry("Hide from Search", "从搜索中隐藏"),
        LauncherKey.restartApplication.rawValue: L10nEntry("Restart Application", "重启应用"),
        LauncherKey.quitApplication.rawValue: L10nEntry("Quit Application", "退出应用"),
        LauncherKey.forceQuitApplication.rawValue: L10nEntry(
            "Force Quit Application", "强制退出应用"),
        LauncherKey.uninstallApplication.rawValue: L10nEntry(
            "Uninstall Application", "卸载应用"),
        LauncherKey.backgroundRefreshEnable.rawValue: L10nEntry(
            "Enable Background Refresh", "开启后台刷新"),
        LauncherKey.backgroundRefreshDisable.rawValue: L10nEntry(
            "Disable Background Refresh", "关闭后台刷新"),
        LauncherKey.refreshNow.rawValue: L10nEntry("Refresh Now", "立即刷新"),
        LauncherKey.configureExtension.rawValue: L10nEntry("Configure Extension", "配置扩展"),
        LauncherKey.uninstallExtension.rawValue: L10nEntry("Uninstall Extension", "卸载扩展"),
        LauncherKey.showInFinder.rawValue: L10nEntry("Show in Finder", "在访达中显示"),
        LauncherKey.configureFallbacks.rawValue: L10nEntry("Configure Fallbacks…", "配置兜底项…"),

        // 前置卡片
        LauncherKey.cardCalculator.rawValue: L10nEntry("Calculator", "计算器"),
        LauncherKey.cardMeeting.rawValue: L10nEntry("Meeting", "会议"),
        LauncherKey.cardColor.rawValue: L10nEntry("Color", "颜色"),

        // 分组与空态
        LauncherKey.sectionResults.rawValue: L10nEntry("Results", "结果"),
        LauncherKey.sectionFavorites.rawValue: L10nEntry("Favorites", "收藏"),
        LauncherKey.sectionSuggestions.rawValue: L10nEntry("Suggestions", "推荐"),
        LauncherKey.sectionConfigureHelp.rawValue: L10nEntry("Configure…", "配置…"),
        LauncherKey.emptyNoApps.rawValue: L10nEntry("No apps found", "未找到应用"),

        // 主操作
        LauncherKey.copyAnswer.rawValue: L10nEntry("Copy Answer", "复制答案"),
        LauncherKey.copyColor.rawValue: L10nEntry("Copy Color", "复制颜色"),
        LauncherKey.openInCalendar.rawValue: L10nEntry("Open in Calendar", "在日历中打开"),
        LauncherKey.joinMeeting.rawValue: L10nEntry("Join Meeting", "加入会议"),
        LauncherKey.openApplication.rawValue: L10nEntry("Open Application", "打开应用"),
        LauncherKey.copyColorAs.rawValue: L10nEntry("Copy Color as…", "复制颜色为…"),

        // 紧凑收藏行
        LauncherKey.showAll.rawValue: L10nEntry("Show all  ↓", "显示全部  ↓"),

        // 设置页
        LauncherKey.searchApps.rawValue: L10nEntry("Search apps…", "搜索应用…"),
        LauncherKey.searchApplications.rawValue: L10nEntry(
            "Search applications…", "搜索应用程序…"),
        LauncherKey.searchSystemSettings.rawValue: L10nEntry(
            "Search System Settings…", "搜索系统设置…"),
        LauncherKey.addApplication.rawValue: L10nEntry("Add Application…", "添加应用…"),
        LauncherKey.stopExcludingFormat.rawValue: L10nEntry(
            "Stop excluding %@", "不再排除 %@"),
        LauncherKey.fallbacksNothingToOffer.rawValue: L10nEntry(
            "Nothing to offer — their features are off.",
            "暂无可用项——相关功能均已关闭。"),
        LauncherKey.fallbacksFooter.rawValue: L10nEntry(
            "Shown below every search as “Use … with”. Includes quicklinks with an {argument}.",
            "每次搜索时以「与…一起使用」展示在结果下方。包含带有 {argument} 的快速链接。"),
        LauncherKey.moveUpFormat.rawValue: L10nEntry("Move %@ up", "上移 %@"),
        LauncherKey.moveDownFormat.rawValue: L10nEntry("Move %@ down", "下移 %@"),
        LauncherKey.offerAsFallbackFormat.rawValue: L10nEntry(
            "Offer %@ as a fallback", "将 %@ 作为兜底项提供"),
        LauncherKey.showInLauncherFormat.rawValue: L10nEntry(
            "Show %@ in launcher", "在启动器中显示 %@"),
        LauncherKey.enableFormat.rawValue: L10nEntry("Enable %@", "启用%@"),
        LauncherKey.offHidesAll.rawValue: L10nEntry(
            "Off hides all of them and stops their shortcuts.",
            "关闭后将隐藏全部项目并停用其快捷键。"),
        LauncherKey.nothingHereYet.rawValue: L10nEntry("Nothing here yet.", "这里还什么都没有。"),
        LauncherKey.noMatchesFormat.rawValue: L10nEntry(
            "No matches for “%@”.", "没有匹配“%@”的结果。"),
        LauncherKey.addEllipsis.rawValue: L10nEntry("Add…", "添加…"),
        LauncherKey.addScopeHelp.rawValue: L10nEntry(
            "Add a folder or application to search.", "添加要搜索的文件夹或应用程序。"),
        LauncherKey.restoreDefaults.rawValue: L10nEntry("Restore Defaults", "恢复默认"),
        LauncherKey.chooseScopesMessage.rawValue: L10nEntry(
            "Choose folders or applications to include in the launcher.",
            "选择要纳入启动器的文件夹或应用程序。"),
        LauncherKey.addScopePrompt.rawValue: L10nEntry("Add", "添加"),

        // 兜底行
        LauncherKey.fallbackVerbQuickAI.rawValue: L10nEntry("Ask Quick AI", "询问 Quick AI"),
        LauncherKey.fallbackVerbSearchFiles.rawValue: L10nEntry("Search Files", "搜索文件"),
        LauncherKey.fallbackVerbRunShellCommand.rawValue: L10nEntry(
            "Run Shell Command", "运行 Shell 命令"),
        LauncherKey.fallbackVerbDefine.rawValue: L10nEntry("Define Word", "查询单词"),
        LauncherKey.fallbackVerbQuicklink.rawValue: L10nEntry("Open Quicklink", "打开快速链接"),
        LauncherKey.fallbackSectionTitleFormat.rawValue: L10nEntry(
            "Use “%@” with…", "将“%@”用于…"),

        // 条目类别：分组标题
        LauncherKey.kindApplicationSection.rawValue: L10nEntry("Applications", "应用程序"),
        LauncherKey.kindSystemSettingsSection.rawValue: L10nEntry(
            "System Settings", "系统设置"),
        LauncherKey.kindCommandSection.rawValue: L10nEntry("Commands", "命令"),
        LauncherKey.kindQuickActionSection.rawValue: L10nEntry("Quick Actions", "快捷操作"),
        LauncherKey.kindCustomCommandSection.rawValue: L10nEntry(
            "Custom Commands", "自定义命令"),
        LauncherKey.kindSnippetSection.rawValue: L10nEntry("Snippets", "片段"),
        LauncherKey.kindSystemActionSection.rawValue: L10nEntry("System Actions", "系统操作"),
        LauncherKey.kindWindowCommandSection.rawValue: L10nEntry(
            "Window Management", "窗口管理"),
        LauncherKey.kindWindowLayoutSection.rawValue: L10nEntry("Window Layouts", "窗口布局"),
        LauncherKey.kindRoomSection.rawValue: L10nEntry("Rooms", "房间"),
        LauncherKey.kindQuicklinkSection.rawValue: L10nEntry("Quicklinks", "快速链接"),
        LauncherKey.kindAppleShortcutSection.rawValue: L10nEntry(
            "Apple Shortcuts", "快捷指令"),
        LauncherKey.kindExtensionSection.rawValue: L10nEntry("Extensions", "扩展"),
        LauncherKey.kindMeetingSection.rawValue: L10nEntry("Meetings", "会议"),

        // 条目类别：打开动词
        LauncherKey.kindApplicationVerb.rawValue: L10nEntry("Open Application", "打开应用"),
        LauncherKey.kindSystemSettingsVerb.rawValue: L10nEntry(
            "Open System Setting", "打开系统设置"),
        LauncherKey.kindCommandVerb.rawValue: L10nEntry("Run Command", "运行命令"),
        LauncherKey.kindQuickActionVerb.rawValue: L10nEntry(
            "Run Quick Action", "运行快捷操作"),
        LauncherKey.kindCustomCommandVerb.rawValue: L10nEntry(
            "Run Custom Command", "运行自定义命令"),
        LauncherKey.kindSnippetVerb.rawValue: L10nEntry("Paste Snippet", "粘贴片段"),
        LauncherKey.kindSystemActionVerb.rawValue: L10nEntry(
            "Run System Action", "运行系统操作"),
        LauncherKey.kindWindowCommandVerb.rawValue: L10nEntry("Move Window", "移动窗口"),
        LauncherKey.kindWindowLayoutVerb.rawValue: L10nEntry(
            "Arrange Windows", "排列窗口"),
        LauncherKey.kindRoomVerb.rawValue: L10nEntry("Enter Room", "进入房间"),
        LauncherKey.kindQuicklinkVerb.rawValue: L10nEntry("Open Quicklink", "打开快速链接"),
        LauncherKey.kindAppleShortcutVerb.rawValue: L10nEntry("Run Shortcut", "运行快捷指令"),
        LauncherKey.kindExtensionVerb.rawValue: L10nEntry("Run Command", "运行命令"),
        LauncherKey.kindMeetingVerb.rawValue: L10nEntry("Join Meeting", "加入会议"),

        // 条目类别：单数标签
        LauncherKey.kindApplicationLabel.rawValue: L10nEntry("Application", "应用程序"),
        LauncherKey.kindSystemSettingsLabel.rawValue: L10nEntry("System Setting", "系统设置"),
        LauncherKey.kindCommandLabel.rawValue: L10nEntry("Command", "命令"),
        LauncherKey.kindQuickActionLabel.rawValue: L10nEntry("Quick Action", "快捷操作"),
        LauncherKey.kindCustomCommandLabel.rawValue: L10nEntry("Custom Command", "自定义命令"),
        LauncherKey.kindSnippetLabel.rawValue: L10nEntry("Snippet", "片段"),
        LauncherKey.kindSystemActionLabel.rawValue: L10nEntry("System Action", "系统操作"),
        LauncherKey.kindWindowCommandLabel.rawValue: L10nEntry("Window Command", "窗口命令"),
        LauncherKey.kindWindowLayoutLabel.rawValue: L10nEntry("Window Layout", "窗口布局"),
        LauncherKey.kindRoomLabel.rawValue: L10nEntry("Room", "房间"),
        LauncherKey.kindQuicklinkLabel.rawValue: L10nEntry("Quicklink", "快速链接"),
        LauncherKey.kindAppleShortcutLabel.rawValue: L10nEntry("Apple Shortcut", "快捷指令"),
        LauncherKey.kindExtensionLabel.rawValue: L10nEntry("Extension", "扩展"),
        LauncherKey.kindMeetingLabel.rawValue: L10nEntry("Meeting", "会议"),
    ]
}
