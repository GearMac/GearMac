// 文件职责：Platform 层弹出面板的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// Platform 目录下打开面板的用户可见文案键。
enum PlatformKey: String, LocalizableKey {
    case executablePickerPrompt = "platform.executablePicker.prompt"
    case folderPickerPrompt = "platform.folderPicker.prompt"

    static let table: [String: L10nEntry] = [
        PlatformKey.executablePickerPrompt.rawValue: L10nEntry("Use Command", "使用该命令"),
        PlatformKey.folderPickerPrompt.rawValue: L10nEntry("Use Folder", "使用该文件夹"),
    ]
}
