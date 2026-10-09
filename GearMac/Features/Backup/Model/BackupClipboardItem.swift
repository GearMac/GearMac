// 文件职责：定义可移植形式的剪贴板记录（图片仅保存 bundle 内文件名），用于备份与还原。
// 分层：Model；与运行时的 `ClipboardItem` 区分，后者保存本机文件路径。
import Foundation

/// 可移植形式的剪贴板记录：不同于 `ClipboardItem`，后者的 `imagePath` 指向某一台 Mac 上的文件。
struct BackupClipboardItem: Codable, Sendable, Equatable {
    /// 剪贴板记录的类型。
    enum Kind: String, Codable, Sendable {
        case text
        case image
        case file
    }

    var kind: Kind
    var text: String?
    /// bundle 内 `clipboard/images/` 下的文件名，绝不是路径。
    var imageName: String?
    var createdAt: Date
    var sourceBundleID: String?
    var pinnedAt: Date?
    /// 用户为条目打的标签；可选字段，旧归档解出为 nil。
    var tag: String?
}
