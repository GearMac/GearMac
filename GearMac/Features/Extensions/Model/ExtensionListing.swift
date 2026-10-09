// 文件职责：描述扩展商店列表中的单个扩展条目（尚未下载），并提供图标 URL 选择与下载量格式化。
// 分层：Model；仅纯数据与格式化逻辑，不 import AppKit/SwiftUI。
import Foundation

/// 商店列表中的单个扩展，尚未下载。
struct ExtensionListing: Identifiable, Hashable, Sendable {
    let id: String
    /// manifest 中的 `name`，也是安装时的主键。
    let name: String
    let title: String
    let summary: String
    let author: String
    let lightIconURL: URL?
    let darkIconURL: URL?
    let commandCount: Int
    let downloadCount: Int?
    /// 构建好的 zip；商店会对其签名，因此该 URL 在安装时拉取，绝不复用。
    let downloadURL: URL
    /// 更新比对依据：商店每发布一个版本它就会变化。
    let commitSHA: String?

    /// 深/浅色图标任一侧可为另一侧兼顶，使仅有单一图稿的列表项也能正常绘制。
    func iconURL(isDark: Bool) -> URL? {
        isDark ? (darkIconURL ?? lightIconURL) : (lightIconURL ?? darkIconURL)
    }

    /// 124218 → "124k"。超过一千后的精确数字在列表中只是噪声。
    static func abbreviate(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return "\(count / 1_000)k"
        default:
            let millions = Double(count) / 1_000_000
            return String(format: millions < 10 ? "%.1fM" : "%.0fM", millions)
        }
    }
}
