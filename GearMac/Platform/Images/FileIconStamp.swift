// 文件职责：计算文件图标标记（icon stamp），用于判断粘贴进 bundle 的图标是否发生变化。
// 分层：Service；仅读取文件资源元数据，不持有状态。
import Foundation

/// 粘贴的图标会在 bundle 内写入 `Icon\r` 并翻转 FinderInfo 中的一位。
enum FileIconStamp {
    private static let keys: Set<URLResourceKey> = [
        .contentModificationDateKey, .attributeModificationDateKey, .fileSizeKey
    ]

    /// 返回路径及其 `Icon\r` 的组合哈希值；图标变化时该值随之变化。
    static func value(for url: URL) -> Int {
        var hasher = Hasher()
        combine(url, into: &hasher)
        combine(URL(fileURLWithPath: url.path + "/Icon\r"), into: &hasher)
        return hasher.finalize()
    }

    /// 不存在的路径不贡献任何值，因此新增 `Icon\r` 会改变整份标记。
    private static func combine(_ url: URL, into hasher: inout Hasher) {
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        hasher.combine(values.contentModificationDate)
        hasher.combine(values.attributeModificationDate)
        hasher.combine(values.fileSize)
    }
}
