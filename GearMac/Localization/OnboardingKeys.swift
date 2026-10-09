// 文件职责：首次启动引导向导的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 引导向导（窗口标题、各步骤标题/副标题、按钮与状态）的文案键。
enum OnboardingKey: String, LocalizableKey {
    // 窗口
    case windowTitle = "onboarding.windowTitle"

    // 步骤标题
    case titleWelcome = "onboarding.title.welcome"
    case titleEnablePasting = "onboarding.title.enablePasting"
    case titleImportRaycast = "onboarding.title.importRaycast"
    case titleAllSet = "onboarding.title.allSet"

    // 步骤副标题
    case subtitleShortcut = "onboarding.subtitle.shortcut"
    case subtitlePasting = "onboarding.subtitle.pasting"
    case subtitleImport = "onboarding.subtitle.import"

    // 就绪文案
    case readyPress = "onboarding.ready.press"
    case readySetShortcut = "onboarding.ready.setShortcut"

    // 快捷键步骤
    case rowAppLauncher = "onboarding.row.appLauncher"
    case rowAppLauncherSubtitle = "onboarding.row.appLauncherSubtitle"
    case rowLaunchAtLogin = "onboarding.row.launchAtLogin"
    case rowLaunchAtLoginSubtitle = "onboarding.row.launchAtLoginSubtitle"
    case captionChangeAnytime = "onboarding.caption.changeAnytime"

    // 辅助功能步骤
    case rowAccessibility = "onboarding.row.accessibility"
    case rowAccessibilitySubtitle = "onboarding.row.accessibilitySubtitle"
    case captionEnableLater = "onboarding.caption.enableLater"
    case statusGranted = "onboarding.status.granted"
    case statusNotGranted = "onboarding.status.notGranted"

    // Raycast 导入步骤
    case rowRaycastExport = "onboarding.row.raycastExport"
    case buttonChoose = "onboarding.button.choose"
    case rowPassphrase = "onboarding.row.passphrase"
    case rowPassphraseSubtitle = "onboarding.row.passphraseSubtitle"
    case captionImportLater = "onboarding.caption.importLater"
    case fileSubtitleRaycast = "onboarding.fileSubtitle.raycast"
    case fileSubtitleNotRaycast = "onboarding.fileSubtitle.notRaycast"
    case fileChooseHint = "onboarding.file.chooseHint"

    // 完成步骤
    case captionDone = "onboarding.caption.done"

    // 按钮
    case buttonBack = "onboarding.button.back"
    case buttonSkip = "onboarding.button.skip"
    case buttonImporting = "onboarding.button.importing"
    case buttonContinue = "onboarding.button.continue"
    case buttonGrantAccess = "onboarding.button.grantAccess"
    case buttonImport = "onboarding.button.import"
    case buttonGetStarted = "onboarding.button.getStarted"

    static let table: [String: L10nEntry] = [
        OnboardingKey.windowTitle.rawValue: L10nEntry(
            "Welcome to GearMac", "欢迎使用 GearMac"),

        OnboardingKey.titleWelcome.rawValue: L10nEntry(
            "Welcome to GearMac", "欢迎使用 GearMac"),
        OnboardingKey.titleEnablePasting.rawValue: L10nEntry(
            "Enable Pasting", "启用粘贴"),
        OnboardingKey.titleImportRaycast.rawValue: L10nEntry(
            "Import from Raycast", "从 Raycast 导入"),
        OnboardingKey.titleAllSet.rawValue: L10nEntry(
            "You're all set", "一切就绪"),

        OnboardingKey.subtitleShortcut.rawValue: L10nEntry(
            "Set a shortcut to summon the launcher from anywhere.",
            "设置一个快捷键，随时随地唤出启动器。"),
        OnboardingKey.subtitlePasting.rawValue: L10nEntry(
            "Let GearMac paste items back into the app you were using.",
            "让 GearMac 把内容粘贴回你正在使用的应用。"),
        OnboardingKey.subtitleImport.rawValue: L10nEntry(
            "Bring your shortcuts, favorites, and clipboard history along.",
            "把快捷方式、收藏和剪贴板历史一并带过来。"),

        OnboardingKey.readyPress.rawValue: L10nEntry(
            "Press %@ anytime to start using GearMac.",
            "随时按下 %@ 即可开始使用 GearMac。"),
        OnboardingKey.readySetShortcut.rawValue: L10nEntry(
            "GearMac is ready. Set a shortcut in Settings to summon it.",
            "GearMac 已就绪。在设置中设置快捷键即可唤出。"),

        OnboardingKey.rowAppLauncher.rawValue: L10nEntry("App Launcher", "应用启动器"),
        OnboardingKey.rowAppLauncherSubtitle.rawValue: L10nEntry(
            "Press this shortcut to open GearMac.",
            "按下此快捷键即可打开 GearMac。"),
        OnboardingKey.rowLaunchAtLogin.rawValue: L10nEntry("Launch at login", "登录时启动"),
        OnboardingKey.rowLaunchAtLoginSubtitle.rawValue: L10nEntry(
            "Start GearMac automatically when you log in.",
            "登录时自动启动 GearMac。"),
        OnboardingKey.captionChangeAnytime.rawValue: L10nEntry(
            "You can change these anytime in Settings.",
            "你随时可以在设置中更改这些选项。"),

        OnboardingKey.rowAccessibility.rawValue: L10nEntry("Accessibility", "辅助功能"),
        OnboardingKey.rowAccessibilitySubtitle.rawValue: L10nEntry(
            "Allows pasting clipboard items and expanded snippets into active apps.",
            "允许把剪贴板内容和展开的片段粘贴到当前应用。"),
        OnboardingKey.captionEnableLater.rawValue: L10nEntry(
            "Optional — you can enable this later in Settings › Permissions.",
            "可选 — 你可以稍后在设置 › 权限中启用。"),
        OnboardingKey.statusGranted.rawValue: L10nEntry("Granted", "已授予"),
        OnboardingKey.statusNotGranted.rawValue: L10nEntry("Not granted", "未授予"),

        OnboardingKey.rowRaycastExport.rawValue: L10nEntry("Raycast Export", "Raycast 导出文件"),
        OnboardingKey.buttonChoose.rawValue: L10nEntry("Choose…", "选择…"),
        OnboardingKey.rowPassphrase.rawValue: L10nEntry("Passphrase", "口令"),
        OnboardingKey.rowPassphraseSubtitle.rawValue: L10nEntry(
            "The password you set when exporting from Raycast.",
            "你在从 Raycast 导出时设置的密码。"),
        OnboardingKey.captionImportLater.rawValue: L10nEntry(
            "Optional — you can import later in Settings › Backup.",
            "可选 — 你可以稍后在设置 › 备份中导入。"),
        OnboardingKey.fileSubtitleRaycast.rawValue: L10nEntry(
            "%@ — Raycast export", "%@ — Raycast 导出文件"),
        OnboardingKey.fileSubtitleNotRaycast.rawValue: L10nEntry(
            "%@ — not a Raycast export", "%@ — 不是 Raycast 导出文件"),
        OnboardingKey.fileChooseHint.rawValue: L10nEntry(
            "Choose a .rayconfig file exported from Raycast v2.0 or newer.",
            "选择从 Raycast v2.0 或更高版本导出的 .rayconfig 文件。"),

        OnboardingKey.captionDone.rawValue: L10nEntry(
            "Everything's ready. Hit Get Started to open the launcher.",
            "一切就绪。点击「开始使用」即可打开启动器。"),

        OnboardingKey.buttonBack.rawValue: L10nEntry("Back", "返回"),
        OnboardingKey.buttonSkip.rawValue: L10nEntry("Skip", "跳过"),
        OnboardingKey.buttonImporting.rawValue: L10nEntry("Importing…", "正在导入…"),
        OnboardingKey.buttonContinue.rawValue: L10nEntry("Continue", "继续"),
        OnboardingKey.buttonGrantAccess.rawValue: L10nEntry("Grant Access", "授予访问权限"),
        OnboardingKey.buttonImport.rawValue: L10nEntry("Import", "导入"),
        OnboardingKey.buttonGetStarted.rawValue: L10nEntry("Get Started", "开始使用"),
    ]
}
