// 文件职责：为设置页提供选择文件夹的打开面板。
// 分层：UI；@MainActor，且需主动激活应用以显示面板。
import AppKit

/// 设置行用来选取某功能存放其文件的唯一文件夹的打开面板。
@MainActor
enum FolderPicker {
    /// 弹出面板让用户选择一个（可新建的）文件夹，取消时返回 nil。
    /// `language` 缺省跟随系统语言；调用方可传入用户的语言偏好以覆盖。
    static func choose(
        message: String, startingAt directory: URL, language: AppLanguage = .system
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.string(PlatformKey.folderPickerPrompt, language: language)
        panel.message = message
        panel.directoryURL = directory
        // GearMac 是 accessory 应用，不这样做的话面板会开在最前应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
