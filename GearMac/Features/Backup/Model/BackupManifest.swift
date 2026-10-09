// 文件职责：定义备份 bundle 的清单，记录格式版本、应用版本、创建时间与各类别条目数。
// 分层：Model；读取方必须先与清单约定一致才能读取其他内容。
import Foundation

/// bundle 的目录（清单）：读取方必须先与其约定一致，才能接触其他内容。
struct BackupManifest: Codable, Sendable, Equatable {
    /// 读取方只接受这个值。它不是迁移点——参见 docs/features/backup.md。
    static let currentFormat = 1

    var format = Self.currentFormat
    /// 仅用于让查看报告的人知道文件来自哪个版本；代码中绝不据此分支。
    var appVersion: String
    var createdAt: Date
    /// 以 `BackupCategory.rawValue` 为键；键缺失即表示选择器将该行置灰。
    var counts: [String: Int]

    /// 清单中包含条目的类别集合。
    var categories: Set<BackupCategory> {
        Set(BackupCategory.allCases.filter { counts[$0.rawValue] != nil })
    }

    /// 返回某类别的条目数，缺失时为 0。
    func count(_ category: BackupCategory) -> Int { counts[category.rawValue] ?? 0 }
}

/// 备份格式错误类型。
enum BackupFormatError: LocalizedError, Equatable {
    case unreadable
    case unsupportedFormat(found: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return L10n.string(BackupKey.errorCannotRead, language: .english)
        case .unsupportedFormat(let found):
            return String(
                format: L10n.string(BackupKey.errorUnsupportedFormat, language: .english),
                found, BackupManifest.currentFormat)
        }
    }

    /// 按指定语言解析错误文案。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .unreadable:
            return L10n.string(BackupKey.errorCannotRead, language: language)
        case .unsupportedFormat(let found):
            return String(
                format: L10n.string(BackupKey.errorUnsupportedFormat, language: language),
                found, BackupManifest.currentFormat)
        }
    }
}
