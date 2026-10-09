// 文件职责：定义更新流程中可能出现的全部失败类型，并提供面向用户的文案与恢复建议。
// 分层：Service/错误模型（LocalizedError）；下面的文案属于 UI 输出，不得改动。
import Foundation

/// 更新可能失败的全部情形，措辞面向报告这些错误的窗口。
enum UpdateFailure: LocalizedError, Equatable {
    case downloadFailed(String)
    case extractFailed(String)
    case noAppInArchive
    case quarantined
    case bundleMismatch
    case identityMismatch
    case versionMismatch(expected: String, found: String)
    case replaceFailed(String)

    /// 面向用户的错误描述。
    var errorDescription: String? { localizedDescription(.english) }

    /// 可行的恢复建议；无建议时返回 nil。
    var recoverySuggestion: String? { localizedRecoverySuggestion(.english) }

    /// 按指定语言解析错误描述。
    func localizedDescription(_ language: AppLanguage) -> String {
        switch self {
        case .downloadFailed(let detail):
            return String(
                format: L10n.string(UpdatesKey.failDownload, language: language), detail)
        case .extractFailed(let detail):
            return String(format: L10n.string(UpdatesKey.failExtract, language: language), detail)
        case .noAppInArchive:
            return L10n.string(UpdatesKey.failNoAppInArchive, language: language)
        case .quarantined:
            return L10n.string(UpdatesKey.failQuarantined, language: language)
        case .bundleMismatch:
            return L10n.string(UpdatesKey.failBundleMismatch, language: language)
        case .identityMismatch:
            return L10n.string(UpdatesKey.failIdentityMismatch, language: language)
        case .versionMismatch(let expected, let found):
            return String(
                format: L10n.string(UpdatesKey.failVersionMismatch, language: language), found, expected)
        case .replaceFailed(let detail):
            return String(format: L10n.string(UpdatesKey.failReplace, language: language), detail)
        }
    }

    /// 按指定语言解析恢复建议；无建议时返回 nil。
    func localizedRecoverySuggestion(_ language: AppLanguage) -> String? {
        switch self {
        case .identityMismatch, .bundleMismatch, .versionMismatch:
            return L10n.string(UpdatesKey.recoveryDownloadFromGitHub, language: language)
        case .replaceFailed:
            return L10n.string(UpdatesKey.recoveryApplicationsNotWritable, language: language)
        case .quarantined:
            return L10n.string(UpdatesKey.recoveryNothingInstalled, language: language)
        default:
            return nil
        }
    }
}
