// 文件职责：软件更新窗口与更新流程的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 更新窗口（标题、副标题、按钮、阶段、阻塞原因与失败文案）的键。
enum UpdatesKey: String, LocalizableKey {
    case windowTitle = "updates.windowTitle"
    case versionUnknown = "updates.version.unknown"

    // 标题
    case titleChecking = "updates.title.checking"
    case titleUpToDate = "updates.title.upToDate"
    case titleLocalBuild = "updates.title.localBuild"
    case titleAvailable = "updates.title.available"
    case titleInstalled = "updates.title.installed"
    case titleFailed = "updates.title.failed"

    // 副标题
    case subtitleVersion = "updates.subtitle.version"
    case subtitleLocalBuild = "updates.subtitle.localBuild"
    case subtitleAvailable = "updates.subtitle.available"
    case subtitleRelaunch = "updates.subtitle.relaunch"

    case somethingWentWrong = "updates.somethingWentWrong"

    // 按钮
    case buttonCancel = "updates.button.cancel"
    case buttonOK = "updates.button.ok"
    case buttonLater = "updates.button.later"
    case buttonUpdateNow = "updates.button.updateNow"
    case buttonTryAgain = "updates.button.tryAgain"
    case buttonRelaunch = "updates.button.relaunch"
    case buttonClose = "updates.button.close"

    // 阻塞原因
    case blockerExpandingSnippet = "updates.blocker.expandingSnippet"
    case blockerRunningExtension = "updates.blocker.runningExtension"
    case blockerUninstalling = "updates.blocker.uninstalling"
    case blockerRecordingHotKey = "updates.blocker.recordingHotKey"
    case blockerDialogOpen = "updates.blocker.dialogOpen"
    case blockerPaletteOpen = "updates.blocker.paletteOpen"

    // 安装阶段
    case phaseDownloading = "updates.phase.downloading"
    case phaseExtracting = "updates.phase.extracting"
    case phaseVerifying = "updates.phase.verifying"
    case phaseReplacing = "updates.phase.replacing"

    // 失败与恢复建议
    case failDownload = "updates.fail.download"
    case failExtract = "updates.fail.extract"
    case failNoAppInArchive = "updates.fail.noAppInArchive"
    case failQuarantined = "updates.fail.quarantined"
    case failBundleMismatch = "updates.fail.bundleMismatch"
    case failIdentityMismatch = "updates.fail.identityMismatch"
    case failVersionMismatch = "updates.fail.versionMismatch"
    case failReplace = "updates.fail.replace"
    case failServerAnswered = "updates.fail.serverAnswered"
    case failReachGitHub = "updates.fail.reachGitHub"
    case recoveryDownloadFromGitHub = "updates.recovery.downloadFromGitHub"
    case recoveryApplicationsNotWritable = "updates.recovery.applicationsNotWritable"
    case recoveryNothingInstalled = "updates.recovery.nothingInstalled"

    static let table: [String: L10nEntry] = [
        UpdatesKey.windowTitle.rawValue: L10nEntry("Software Update", "软件更新"),
        UpdatesKey.versionUnknown.rawValue: L10nEntry("unknown", "未知"),

        UpdatesKey.titleChecking.rawValue: L10nEntry("Checking for updates…", "正在检查更新…"),
        UpdatesKey.titleUpToDate.rawValue: L10nEntry("%@ is up to date", "%@ 已是最新版本"),
        UpdatesKey.titleLocalBuild.rawValue: L10nEntry(
            "%@ doesn't update itself", "%@ 不自我更新"),
        UpdatesKey.titleAvailable.rawValue: L10nEntry(
            "%@ %@ is available", "%@ %@ 可供更新"),
        UpdatesKey.titleInstalled.rawValue: L10nEntry("Update installed", "更新已安装"),
        UpdatesKey.titleFailed.rawValue: L10nEntry("Update failed", "更新失败"),

        UpdatesKey.subtitleVersion.rawValue: L10nEntry("Version %@", "版本 %@"),
        UpdatesKey.subtitleLocalBuild.rawValue: L10nEntry(
            "This is a local build — rebuild it to move it forward.",
            "这是本地构建 — 重新构建即可推进。"),
        UpdatesKey.subtitleAvailable.rawValue: L10nEntry("You have %@.", "你当前是 %@。"),
        UpdatesKey.subtitleRelaunch.rawValue: L10nEntry(
            "Relaunch to start using it.", "重新启动即可使用。"),

        UpdatesKey.somethingWentWrong.rawValue: L10nEntry("Something went wrong.", "出了点问题。"),

        UpdatesKey.buttonCancel.rawValue: L10nEntry("Cancel", "取消"),
        UpdatesKey.buttonOK.rawValue: L10nEntry("OK", "好的"),
        UpdatesKey.buttonLater.rawValue: L10nEntry("Later", "稍后"),
        UpdatesKey.buttonUpdateNow.rawValue: L10nEntry("Update Now", "立即更新"),
        UpdatesKey.buttonTryAgain.rawValue: L10nEntry("Try Again", "重试"),
        UpdatesKey.buttonRelaunch.rawValue: L10nEntry("Relaunch", "重新启动"),
        UpdatesKey.buttonClose.rawValue: L10nEntry("Close", "关闭"),

        UpdatesKey.blockerExpandingSnippet.rawValue: L10nEntry(
            "Waiting for a snippet to finish expanding.", "正在等待片段展开完成。"),
        UpdatesKey.blockerRunningExtension.rawValue: L10nEntry(
            "Waiting for a running extension command to finish.", "正在等待运行中的扩展命令结束。"),
        UpdatesKey.blockerUninstalling.rawValue: L10nEntry(
            "Waiting for the uninstaller to finish.", "正在等待卸载程序完成。"),
        UpdatesKey.blockerRecordingHotKey.rawValue: L10nEntry(
            "Finish recording the shortcut first.", "请先完成快捷键录制。"),
        UpdatesKey.blockerDialogOpen.rawValue: L10nEntry(
            "Close the open dialog first.", "请先关闭已打开的对话框。"),
        UpdatesKey.blockerPaletteOpen.rawValue: L10nEntry(
            "Close GearMac's window first.", "请先关闭 GearMac 的窗口。"),

        UpdatesKey.phaseDownloading.rawValue: L10nEntry(
            "Downloading… %@ of %@", "正在下载…%@ / %@"),
        UpdatesKey.phaseExtracting.rawValue: L10nEntry("Expanding…", "正在解压…"),
        UpdatesKey.phaseVerifying.rawValue: L10nEntry("Verifying…", "正在验证…"),
        UpdatesKey.phaseReplacing.rawValue: L10nEntry("Replacing GearMac…", "正在替换 GearMac…"),

        UpdatesKey.failDownload.rawValue: L10nEntry(
            "The download did not finish. %@", "下载未完成。%@"),
        UpdatesKey.failExtract.rawValue: L10nEntry(
            "The downloaded archive could not be expanded. %@", "无法解压下载的归档。%@"),
        UpdatesKey.failNoAppInArchive.rawValue: L10nEntry(
            "The downloaded archive does not contain GearMac.", "下载的归档中不包含 GearMac。"),
        UpdatesKey.failQuarantined.rawValue: L10nEntry(
            "macOS quarantined the downloaded app and GearMac could not clear the flag.",
            "macOS 已将下载的应用隔离，GearMac 无法清除该标记。"),
        UpdatesKey.failBundleMismatch.rawValue: L10nEntry(
            "The downloaded app is not this build of GearMac.", "下载的应用不是这个 GearMac 构建。"),
        UpdatesKey.failIdentityMismatch.rawValue: L10nEntry(
            "The downloaded app is not signed by the identity this copy was signed with.",
            "下载的应用不是由此副本的签名身份签署的。"),
        UpdatesKey.failVersionMismatch.rawValue: L10nEntry(
            "The downloaded app is version %@, not %@.", "下载的应用版本是 %@，而不是 %@。"),
        UpdatesKey.failReplace.rawValue: L10nEntry(
            "GearMac could not be replaced. %@", "无法替换 GearMac。%@"),
        UpdatesKey.failServerAnswered.rawValue: L10nEntry(
            "The server answered %@.", "服务器返回 %@。"),
        UpdatesKey.failReachGitHub.rawValue: L10nEntry(
            "GearMac could not reach GitHub.", "GearMac 无法连接到 GitHub。"),
        UpdatesKey.recoveryDownloadFromGitHub.rawValue: L10nEntry(
            "Nothing was installed. Download the release from GitHub instead, so you can check it yourself.",
            "未安装任何内容。请改为从 GitHub 下载该版本，以便自行核验。"),
        UpdatesKey.recoveryApplicationsNotWritable.rawValue: L10nEntry(
            "Nothing was installed. This usually means /Applications is not writable by your account.",
            "未安装任何内容。这通常意味着你的账户无权写入 /Applications。"),
        UpdatesKey.recoveryNothingInstalled.rawValue: L10nEntry(
            "Nothing was installed.", "未安装任何内容。"),
    ]
}
