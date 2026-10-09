// 文件职责：系统动作的本地化键与中英词表（动作名、确认文案、反馈与失败提示）。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 系统动作（展示名、确认弹窗、执行反馈与失败提示）的文案键。
enum SystemActionsKey: String, LocalizableKey {
    // 动作展示名
    case lockScreen = "systemActions.action.lockScreen"
    case sleep = "systemActions.action.sleep"
    case sleepDisplays = "systemActions.action.sleepDisplays"
    case restart = "systemActions.action.restart"
    case shutDown = "systemActions.action.shutDown"
    case logOut = "systemActions.action.logOut"
    case showScreenSaver = "systemActions.action.showScreenSaver"
    case playPause = "systemActions.action.playPause"
    case nextTrack = "systemActions.action.nextTrack"
    case previousTrack = "systemActions.action.previousTrack"
    case toggleMute = "systemActions.action.toggleMute"
    case toggleMicrophoneMute = "systemActions.action.toggleMicrophoneMute"
    case volumeUp = "systemActions.action.volumeUp"
    case volumeDown = "systemActions.action.volumeDown"
    case setVolume = "systemActions.action.setVolume"
    case volume0 = "systemActions.action.volume0"
    case volume25 = "systemActions.action.volume25"
    case volume50 = "systemActions.action.volume50"
    case volume75 = "systemActions.action.volume75"
    case volume100 = "systemActions.action.volume100"
    case showDesktop = "systemActions.action.showDesktop"
    case toggleAppearance = "systemActions.action.toggleAppearance"
    case toggleStageManager = "systemActions.action.toggleStageManager"
    case openTrash = "systemActions.action.openTrash"
    case emptyTrash = "systemActions.action.emptyTrash"
    case ejectAllDisks = "systemActions.action.ejectAllDisks"
    case toggleHiddenFiles = "systemActions.action.toggleHiddenFiles"
    case hideOtherApps = "systemActions.action.hideOtherApps"
    case unhideAllApps = "systemActions.action.unhideAllApps"
    case quitAllApps = "systemActions.action.quitAllApps"
    case dismissNotifications = "systemActions.action.dismissNotifications"
    case toggleBluetooth = "systemActions.action.toggleBluetooth"

    // 确认弹窗
    case confirmRestartTitle = "systemActions.confirm.restartTitle"
    case confirmShutDownTitle = "systemActions.confirm.shutDownTitle"
    case confirmLogOutTitle = "systemActions.confirm.logOutTitle"
    case confirmEmptyTrashTitle = "systemActions.confirm.emptyTrashTitle"
    case confirmEmptyTrashMessage = "systemActions.confirm.emptyTrashMessage"
    case confirmSessionEndingMessage = "systemActions.confirm.sessionEndingMessage"
    case confirmQuitAllOne = "systemActions.confirm.quitAllOne"
    case confirmQuitAllMany = "systemActions.confirm.quitAllMany"
    case confirmQuitAllMessage = "systemActions.confirm.quitAllMessage"
    case confirmQuitAll = "systemActions.confirm.quitAll"
    case failureTitle = "systemActions.confirm.failureTitle"
    case openSystemSettings = "systemActions.confirm.openSystemSettings"
    case searchPrompt = "systemActions.searchPrompt"

    // 执行反馈
    case feedbackMicrophoneMuted = "systemActions.feedback.microphoneMuted"
    case feedbackMicrophoneUnmuted = "systemActions.feedback.microphoneUnmuted"
    case feedbackDarkAppearance = "systemActions.feedback.darkAppearance"
    case feedbackLightAppearance = "systemActions.feedback.lightAppearance"
    case feedbackStageManagerOn = "systemActions.feedback.stageManagerOn"
    case feedbackStageManagerOff = "systemActions.feedback.stageManagerOff"
    case feedbackTrashAlreadyEmpty = "systemActions.feedback.trashAlreadyEmpty"
    case feedbackTrashEmptied = "systemActions.feedback.trashEmptied"
    case feedbackNoDisksToEject = "systemActions.feedback.noDisksToEject"
    case feedbackDiskEjected = "systemActions.feedback.diskEjected"
    case feedbackDisksEjected = "systemActions.feedback.disksEjected"
    case feedbackHiddenFilesShown = "systemActions.feedback.hiddenFilesShown"
    case feedbackHiddenFilesHidden = "systemActions.feedback.hiddenFilesHidden"
    case feedbackNothingWasHidden = "systemActions.feedback.nothingWasHidden"
    case feedbackAllAppsUnhidden = "systemActions.feedback.allAppsUnhidden"
    case feedbackNoNotifications = "systemActions.feedback.noNotifications"
    case feedbackNotificationsDismissed = "systemActions.feedback.notificationsDismissed"
    case feedbackBluetoothOn = "systemActions.feedback.bluetoothOn"
    case feedbackBluetoothOff = "systemActions.feedback.bluetoothOff"

    // 失败提示
    case failScreenSaverMissing = "systemActions.fail.screenSaverMissing"
    case failTrashOpen = "systemActions.fail.trashOpen"
    case failNoSoftwareVolume = "systemActions.fail.noSoftwareVolume"
    case failVolumeControlledExternally = "systemActions.fail.volumeControlledExternally"
    case failVolumeChange = "systemActions.fail.volumeChange"
    case failNoOutputDevice = "systemActions.fail.noOutputDevice"
    case failMuteChange = "systemActions.fail.muteChange"
    case failScreenLockUnavailable = "systemActions.fail.screenLockUnavailable"
    case failScreenLockNotExposed = "systemActions.fail.screenLockNotExposed"
    case failAccessibility = "systemActions.fail.accessibility"
    case failEjectSome = "systemActions.fail.ejectSome"
    case failUnexpectedValue = "systemActions.fail.unexpectedValue"
    case failNotSaved = "systemActions.fail.notSaved"
    case failNotificationDismissControl = "systemActions.fail.notificationDismissControl"
    case failNotificationDismiss = "systemActions.fail.notificationDismiss"
    case failNotificationsRemain = "systemActions.fail.notificationsRemain"
    case failBluetoothUnavailable = "systemActions.fail.bluetoothUnavailable"
    case failBluetoothNotExposed = "systemActions.fail.bluetoothNotExposed"
    case failNoBluetoothController = "systemActions.fail.noBluetoothController"
    case failBluetoothNoChange = "systemActions.fail.bluetoothNoChange"
    case failAutomationPrepare = "systemActions.fail.automationPrepare"
    case failAutomationUnknown = "systemActions.fail.automationUnknown"
    case failAutomationPermission = "systemActions.fail.automationPermission"
    case failNoInputDevice = "systemActions.fail.noInputDevice"
    case failMicNoSoftwareMute = "systemActions.fail.micNoSoftwareMute"
    case failMicControlledExternally = "systemActions.fail.micControlledExternally"
    case failMicMuteChange = "systemActions.fail.micMuteChange"
    case failMicNoConfirm = "systemActions.fail.micNoConfirm"
    case failMicRead = "systemActions.fail.micRead"

    static let table: [String: L10nEntry] = [
        SystemActionsKey.lockScreen.rawValue: L10nEntry("Lock Screen", "锁定屏幕"),
        SystemActionsKey.sleep.rawValue: L10nEntry("Sleep", "睡眠"),
        SystemActionsKey.sleepDisplays.rawValue: L10nEntry("Sleep Displays", "显示器睡眠"),
        SystemActionsKey.restart.rawValue: L10nEntry("Restart", "重新启动"),
        SystemActionsKey.shutDown.rawValue: L10nEntry("Shut Down", "关机"),
        SystemActionsKey.logOut.rawValue: L10nEntry("Log Out", "退出登录"),
        SystemActionsKey.showScreenSaver.rawValue: L10nEntry("Show Screen Saver", "显示屏幕保护"),
        SystemActionsKey.playPause.rawValue: L10nEntry("Play / Pause", "播放 / 暂停"),
        SystemActionsKey.nextTrack.rawValue: L10nEntry("Next Track", "下一曲目"),
        SystemActionsKey.previousTrack.rawValue: L10nEntry("Previous Track", "上一曲目"),
        SystemActionsKey.toggleMute.rawValue: L10nEntry("Toggle Mute", "切换静音"),
        SystemActionsKey.toggleMicrophoneMute.rawValue: L10nEntry(
            "Toggle Microphone Mute", "切换麦克风静音"),
        SystemActionsKey.volumeUp.rawValue: L10nEntry("Turn Volume Up", "调高音量"),
        SystemActionsKey.volumeDown.rawValue: L10nEntry("Turn Volume Down", "调低音量"),
        SystemActionsKey.setVolume.rawValue: L10nEntry("Set Volume…", "设置音量…"),
        SystemActionsKey.volume0.rawValue: L10nEntry("Set Volume to 0%", "音量设为 0%"),
        SystemActionsKey.volume25.rawValue: L10nEntry("Set Volume to 25%", "音量设为 25%"),
        SystemActionsKey.volume50.rawValue: L10nEntry("Set Volume to 50%", "音量设为 50%"),
        SystemActionsKey.volume75.rawValue: L10nEntry("Set Volume to 75%", "音量设为 75%"),
        SystemActionsKey.volume100.rawValue: L10nEntry("Set Volume to 100%", "音量设为 100%"),
        SystemActionsKey.showDesktop.rawValue: L10nEntry("Show Desktop", "显示桌面"),
        SystemActionsKey.toggleAppearance.rawValue: L10nEntry(
            "Toggle System Appearance", "切换系统外观"),
        SystemActionsKey.toggleStageManager.rawValue: L10nEntry(
            "Toggle Stage Manager", "切换台前调度"),
        SystemActionsKey.openTrash.rawValue: L10nEntry("Open Trash", "打开废纸篓"),
        SystemActionsKey.emptyTrash.rawValue: L10nEntry("Empty Trash", "清空废纸篓"),
        SystemActionsKey.ejectAllDisks.rawValue: L10nEntry("Eject All Disks", "推出所有磁盘"),
        SystemActionsKey.toggleHiddenFiles.rawValue: L10nEntry(
            "Toggle Hidden Files", "切换隐藏文件"),
        SystemActionsKey.hideOtherApps.rawValue: L10nEntry(
            "Hide All Apps Except Frontmost", "隐藏除最前应用外的所有应用"),
        SystemActionsKey.unhideAllApps.rawValue: L10nEntry(
            "Unhide All Hidden Apps", "取消隐藏所有已隐藏的应用"),
        SystemActionsKey.quitAllApps.rawValue: L10nEntry(
            "Quit All Applications", "退出所有应用"),
        SystemActionsKey.dismissNotifications.rawValue: L10nEntry(
            "Dismiss Notifications", "清除通知"),
        SystemActionsKey.toggleBluetooth.rawValue: L10nEntry("Toggle Bluetooth", "切换蓝牙"),

        SystemActionsKey.confirmRestartTitle.rawValue: L10nEntry(
            "Restart your Mac?", "要重新启动 Mac 吗？"),
        SystemActionsKey.confirmShutDownTitle.rawValue: L10nEntry(
            "Shut down your Mac?", "要关闭 Mac 吗？"),
        SystemActionsKey.confirmLogOutTitle.rawValue: L10nEntry("Log out now?", "现在退出登录？"),
        SystemActionsKey.confirmEmptyTrashTitle.rawValue: L10nEntry(
            "Empty Trash?", "要清空废纸篓吗？"),
        SystemActionsKey.confirmEmptyTrashMessage.rawValue: L10nEntry(
            "The items in the Trash will be permanently deleted.",
            "废纸篓中的项目将被永久删除。"),
        SystemActionsKey.confirmSessionEndingMessage.rawValue: L10nEntry(
            "Applications with unsaved changes may ask you to save.",
            "有未保存更改的应用可能会提示你保存。"),
        SystemActionsKey.confirmQuitAllOne.rawValue: L10nEntry(
            "Quit 1 application?", "要退出 1 个应用吗？"),
        SystemActionsKey.confirmQuitAllMany.rawValue: L10nEntry(
            "Quit %d applications?", "要退出 %d 个应用吗？"),
        SystemActionsKey.confirmQuitAllMessage.rawValue: L10nEntry(
            "Applications with unsaved changes will ask you to save.",
            "有未保存更改的应用会提示你保存。"),
        SystemActionsKey.confirmQuitAll.rawValue: L10nEntry("Quit All", "全部退出"),
        SystemActionsKey.failureTitle.rawValue: L10nEntry(
            "“%@” Failed", "“%@”失败"),
        SystemActionsKey.openSystemSettings.rawValue: L10nEntry(
            "Open System Settings…", "打开系统设置…"),
        SystemActionsKey.searchPrompt.rawValue: L10nEntry(
            "Search system actions…", "搜索系统操作…"),

        SystemActionsKey.feedbackMicrophoneMuted.rawValue: L10nEntry(
            "Microphone Muted", "麦克风已静音"),
        SystemActionsKey.feedbackMicrophoneUnmuted.rawValue: L10nEntry(
            "Microphone Unmuted", "麦克风已取消静音"),
        SystemActionsKey.feedbackDarkAppearance.rawValue: L10nEntry(
            "Dark Appearance", "深色外观"),
        SystemActionsKey.feedbackLightAppearance.rawValue: L10nEntry(
            "Light Appearance", "浅色外观"),
        SystemActionsKey.feedbackStageManagerOn.rawValue: L10nEntry(
            "Stage Manager On", "台前调度已开启"),
        SystemActionsKey.feedbackStageManagerOff.rawValue: L10nEntry(
            "Stage Manager Off", "台前调度已关闭"),
        SystemActionsKey.feedbackTrashAlreadyEmpty.rawValue: L10nEntry(
            "Trash Is Already Empty", "废纸篓已是空的"),
        SystemActionsKey.feedbackTrashEmptied.rawValue: L10nEntry("Trash Emptied", "废纸篓已清空"),
        SystemActionsKey.feedbackNoDisksToEject.rawValue: L10nEntry(
            "No Disks to Eject", "没有可推出的磁盘"),
        SystemActionsKey.feedbackDiskEjected.rawValue: L10nEntry(
            "1 Disk Ejected", "已推出 1 个磁盘"),
        SystemActionsKey.feedbackDisksEjected.rawValue: L10nEntry(
            "%d Disks Ejected", "已推出 %d 个磁盘"),
        SystemActionsKey.feedbackHiddenFilesShown.rawValue: L10nEntry(
            "Hidden Files Shown", "已显示隐藏文件"),
        SystemActionsKey.feedbackHiddenFilesHidden.rawValue: L10nEntry(
            "Hidden Files Hidden", "已隐藏隐藏文件"),
        SystemActionsKey.feedbackNothingWasHidden.rawValue: L10nEntry(
            "Nothing Was Hidden", "没有任何应用被隐藏"),
        SystemActionsKey.feedbackAllAppsUnhidden.rawValue: L10nEntry(
            "All Apps Unhidden", "已取消隐藏所有应用"),
        SystemActionsKey.feedbackNoNotifications.rawValue: L10nEntry(
            "No Notifications", "没有通知"),
        SystemActionsKey.feedbackNotificationsDismissed.rawValue: L10nEntry(
            "Notifications Dismissed", "通知已清除"),
        SystemActionsKey.feedbackBluetoothOn.rawValue: L10nEntry("Bluetooth On", "蓝牙已开启"),
        SystemActionsKey.feedbackBluetoothOff.rawValue: L10nEntry("Bluetooth Off", "蓝牙已关闭"),

        SystemActionsKey.failScreenSaverMissing.rawValue: L10nEntry(
            "The macOS screen saver could not be found.", "找不到 macOS 屏幕保护程序。"),
        SystemActionsKey.failTrashOpen.rawValue: L10nEntry(
            "Finder could not open the Trash.", "Finder 无法打开废纸篓。"),
        SystemActionsKey.failNoSoftwareVolume.rawValue: L10nEntry(
            "The current audio output does not support software volume.",
            "当前音频输出不支持软件音量控制。"),
        SystemActionsKey.failVolumeControlledExternally.rawValue: L10nEntry(
            "The current audio output volume is controlled externally.",
            "当前音频输出音量由外部控制。"),
        SystemActionsKey.failVolumeChange.rawValue: L10nEntry(
            "macOS could not change the output volume (error %@).",
            "macOS 无法更改输出音量（错误 %@）。"),
        SystemActionsKey.failNoOutputDevice.rawValue: L10nEntry(
            "No audio output device is available.", "没有可用的音频输出设备。"),
        SystemActionsKey.failMuteChange.rawValue: L10nEntry(
            "macOS could not change mute state (error %@).",
            "macOS 无法更改静音状态（错误 %@）。"),
        SystemActionsKey.failScreenLockUnavailable.rawValue: L10nEntry(
            "Screen locking is unavailable on this Mac.", "这台 Mac 上无法锁定屏幕。"),
        SystemActionsKey.failScreenLockNotExposed.rawValue: L10nEntry(
            "This macOS version does not expose screen locking.",
            "此 macOS 版本未提供屏幕锁定功能。"),
        SystemActionsKey.failAccessibility.rawValue: L10nEntry(
            "Allow GearMac to control your Mac in Accessibility settings, then try again.",
            "请在辅助功能设置中允许 GearMac 控制你的 Mac，然后重试。"),
        SystemActionsKey.failEjectSome.rawValue: L10nEntry(
            "Some disks could not be ejected:\n\n%@", "部分磁盘无法推出：\n\n%@"),
        SystemActionsKey.failUnexpectedValue.rawValue: L10nEntry(
            "macOS reported an unexpected value for this setting.",
            "macOS 报告了此设置的意外值。"),
        SystemActionsKey.failNotSaved.rawValue: L10nEntry(
            "macOS did not save the requested setting.", "macOS 未保存所请求的设置。"),
        SystemActionsKey.failNotificationDismissControl.rawValue: L10nEntry(
            "This version of Notification Center exposes no dismiss control GearMac can use.",
            "此版本的通知中心没有 GearMac 可用的关闭控件。"),
        SystemActionsKey.failNotificationDismiss.rawValue: L10nEntry(
            "Notification Center did not allow a notification to be dismissed.",
            "通知中心不允许关闭某条通知。"),
        SystemActionsKey.failNotificationsRemain.rawValue: L10nEntry(
            "Some notifications remain after the safety limit was reached.",
            "达到安全上限后仍残留部分通知。"),
        SystemActionsKey.failBluetoothUnavailable.rawValue: L10nEntry(
            "Bluetooth control is unavailable on this Mac.", "这台 Mac 上无法控制蓝牙。"),
        SystemActionsKey.failBluetoothNotExposed.rawValue: L10nEntry(
            "This macOS version does not expose Bluetooth power control.",
            "此 macOS 版本未提供蓝牙电源控制。"),
        SystemActionsKey.failNoBluetoothController.rawValue: L10nEntry(
            "No Bluetooth controller is available.", "没有可用的蓝牙控制器。"),
        SystemActionsKey.failBluetoothNoChange.rawValue: L10nEntry(
            "Bluetooth did not change state. Check GearMac’s Bluetooth permission.",
            "蓝牙状态未改变。请检查 GearMac 的蓝牙权限。"),
        SystemActionsKey.failAutomationPrepare.rawValue: L10nEntry(
            "The system automation could not be prepared.", "无法准备系统自动化。"),
        SystemActionsKey.failAutomationUnknown.rawValue: L10nEntry(
            "Unknown automation error.", "未知的自动化错误。"),
        SystemActionsKey.failAutomationPermission.rawValue: L10nEntry(
            "Allow GearMac to control the requested app in Automation settings, then try again.",
            "请在自动化设置中允许 GearMac 控制所请求的应用，然后重试。"),
        SystemActionsKey.failNoInputDevice.rawValue: L10nEntry(
            "No audio input device is available.", "没有可用的音频输入设备。"),
        SystemActionsKey.failMicNoSoftwareMute.rawValue: L10nEntry(
            "The current microphone does not support software mute.",
            "当前麦克风不支持软件静音。"),
        SystemActionsKey.failMicControlledExternally.rawValue: L10nEntry(
            "The current microphone mute is controlled externally.",
            "当前麦克风静音由外部控制。"),
        SystemActionsKey.failMicMuteChange.rawValue: L10nEntry(
            "macOS could not change microphone mute (error %@).",
            "macOS 无法更改麦克风静音（错误 %@）。"),
        SystemActionsKey.failMicNoConfirm.rawValue: L10nEntry(
            "The microphone did not confirm the mute change. Try again.",
            "麦克风未确认静音更改。请重试。"),
        SystemActionsKey.failMicRead.rawValue: L10nEntry(
            "macOS could not read microphone mute (error %@).",
            "macOS 无法读取麦克风静音（错误 %@）。"),
    ]
}
