// 文件职责：读写 macOS 的 com.apple.quarantine 扩展属性（隔离标记）。
// 分层：Service（直接调用 getxattr/removexattr）；仅处理本地文件，不做网络请求。
import Foundation

/// 属于防护检查而非固定步骤：GearMac 自行下载的归档通常不带隔离标记。
enum Quarantine {
    private static let attribute = "com.apple.quarantine"

    /// 判断该 URL 是否带有隔离标记。
    static func isSet(on url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    /// 解压被隔离的归档会给它写出的每个文件都打上标记，而不只是根目录。
    static func clear(from root: URL) {
        remove(from: root)
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return }
        for case let url as URL in walker { remove(from: url) }
    }

    /// 移除单个路径上的隔离扩展属性。
    private static func remove(from url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(0) }
            return removexattr(path, attribute, XATTR_NOFOLLOW)
        }
    }
}
