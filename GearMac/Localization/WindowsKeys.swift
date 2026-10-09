// 文件职责：独立窗口（关于页、对话框、HUD）的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// Windows 目录下关于页、对话框与 HUD 的文案键。
enum WindowsKey: String, LocalizableKey {
    // 关于页
    case aboutVersionFormat = "windows.about.versionFormat"
    case aboutCheckForUpdates = "windows.about.checkForUpdates"
    case aboutTagline = "windows.about.tagline"
    case aboutSupportTitle = "windows.about.supportTitle"
    case aboutSupportBlurb = "windows.about.supportBlurb"
    case aboutSupportButton = "windows.about.supportButton"
    case aboutCopyright = "windows.about.copyright"
    case aboutLinkWebsite = "windows.about.link.website"
    case aboutLinkGitHub = "windows.about.link.github"
    case aboutLinkDiscord = "windows.about.link.discord"
    case aboutLinkDiscordDetail = "windows.about.link.discordDetail"
    case aboutLinkX = "windows.about.link.x"
    case aboutLinkEmail = "windows.about.link.email"

    // 对话框通用按钮
    case dialogOK = "windows.dialog.ok"
    case dialogCancel = "windows.dialog.cancel"

    // 设置音量
    case dialogVolumeTitle = "windows.dialog.volume.title"
    case dialogVolumeMessage = "windows.dialog.volume.message"

    // 新建日程
    case dialogEventTitle = "windows.dialog.event.title"
    case dialogEventMessage = "windows.dialog.event.message"
    case dialogEventConfirm = "windows.dialog.event.confirm"

    // 片段参数
    case dialogSnippetMessage = "windows.dialog.snippet.message"
    case dialogSnippetConfirm = "windows.dialog.snippet.confirm"

    // HUD
    case hudMuted = "windows.hud.muted"
    case hudCancelFormat = "windows.hud.cancelFormat"
    case volumeSliderLabel = "windows.volumeSlider.label"

    static let table: [String: L10nEntry] = [
        WindowsKey.aboutVersionFormat.rawValue: L10nEntry(
            "Version %@ (%@)", "版本 %@（%@）"),
        WindowsKey.aboutCheckForUpdates.rawValue: L10nEntry(
            "Check for Updates", "检查更新"),
        WindowsKey.aboutTagline.rawValue: L10nEntry(
            "A tiny, native macOS launcher.", "一个小巧的原生 macOS 启动器。"),
        WindowsKey.aboutSupportTitle.rawValue: L10nEntry("Support", "赞助"),
        WindowsKey.aboutSupportBlurb.rawValue: L10nEntry(
            "Free and open source, funded out of pocket.", "免费开源，由作者自掏腰包维护。"),
        WindowsKey.aboutSupportButton.rawValue: L10nEntry("Support…", "赞助…"),
        WindowsKey.aboutCopyright.rawValue: L10nEntry(
            "© 2026 GearMac · Released under AGPL-3.0",
            "© 2026 GearMac · 以 AGPL-3.0 许可发布"),
        WindowsKey.aboutLinkWebsite.rawValue: L10nEntry("Website", "官网"),
        WindowsKey.aboutLinkGitHub.rawValue: L10nEntry("GitHub", "GitHub"),
        WindowsKey.aboutLinkDiscord.rawValue: L10nEntry("Discord", "Discord"),
        WindowsKey.aboutLinkDiscordDetail.rawValue: L10nEntry(
            "Join the GearMac community", "加入 GearMac 社区"),
        WindowsKey.aboutLinkX.rawValue: L10nEntry("X", "X"),
        WindowsKey.aboutLinkEmail.rawValue: L10nEntry("Email", "邮件"),

        WindowsKey.dialogOK.rawValue: L10nEntry("OK", "好"),
        WindowsKey.dialogCancel.rawValue: L10nEntry("Cancel", "取消"),

        WindowsKey.dialogVolumeTitle.rawValue: L10nEntry("Set Volume", "设置音量"),
        WindowsKey.dialogVolumeMessage.rawValue: L10nEntry(
            "Choose the output volume.", "选择输出音量。"),

        WindowsKey.dialogEventTitle.rawValue: L10nEntry("New Event", "新建日程"),
        WindowsKey.dialogEventMessage.rawValue: L10nEntry(
            "It goes on the calendar new events go to.", "它将写入新日程默认使用的日历。"),
        WindowsKey.dialogEventConfirm.rawValue: L10nEntry("Create", "创建"),

        WindowsKey.dialogSnippetMessage.rawValue: L10nEntry(
            "Fill in the template fields.", "填写模板字段。"),
        WindowsKey.dialogSnippetConfirm.rawValue: L10nEntry("Expand", "展开"),

        WindowsKey.hudMuted.rawValue: L10nEntry("Muted", "已静音"),
        WindowsKey.hudCancelFormat.rawValue: L10nEntry("Cancel %@", "取消 %@"),
        WindowsKey.volumeSliderLabel.rawValue: L10nEntry("Output volume", "输出音量"),
    ]
}
