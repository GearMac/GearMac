// 文件职责：定义 Raycast 导入失败的错误类型与面向用户的错误描述。
// 分层：Model；错误文案面向 UI，代码逻辑不据其分支。
import Foundation

/// Raycast 导入失败的错误类型。
enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notRaycastFile:
            return L10n.string(BackupKey.errorNotRaycastFile, language: .english)
        case .incorrectPassphrase:
            return L10n.string(BackupKey.errorIncorrectPassphrase, language: .english)
        case .corrupt:
            return L10n.string(BackupKey.errorCorrupt, language: .english)
        case .tooLarge:
            return L10n.string(BackupKey.errorTooLarge, language: .english)
        }
    }

    /// 按指定语言解析错误文案。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .notRaycastFile:
            return L10n.string(BackupKey.errorNotRaycastFile, language: language)
        case .incorrectPassphrase:
            return L10n.string(BackupKey.errorIncorrectPassphrase, language: language)
        case .corrupt:
            return L10n.string(BackupKey.errorCorrupt, language: language)
        case .tooLarge:
            return L10n.string(BackupKey.errorTooLarge, language: language)
        }
    }
}
