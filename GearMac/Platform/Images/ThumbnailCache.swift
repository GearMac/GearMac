// 文件职责：按尺寸分层的缩略图缓存（行内小图与预览大图各自有容量上限）。
// 分层：Service；@unchecked Sendable，状态仅由两个自身线程安全的 `NSCache` 构成。
import AppKit

/// 标为 unchecked：其全部状态就是两个 `let` `NSCache`，而它们本身就是线程安全的。
final class ThumbnailCache: @unchecked Sendable {
    private final class Cache: NSCache<NSString, NSImage> {}

    /// 行内格子的长边门槛：覆盖式卡片缩略图最高解码到 2048px，全部留在行内层以便重开命中。
    private static let rowThreshold: CGFloat = 2048

    private let rows = Cache()
    private let previews = Cache()
    /// 宽高比随首次解码记入，使后续渲染能同帧算出覆盖式缓存键。
    private let aspects = NSCache<NSString, NSNumber>()

    /// 分别为行内与预览两层缓存设置字节预算。
    init(rowBytes: Int, previewBytes: Int) {
        rows.totalCostLimit = rowBytes
        previews.totalCostLimit = previewBytes
    }

    /// 按尺寸选择所属的缓存层。
    private func tier(_ maxPixel: CGFloat) -> Cache {
        maxPixel <= Self.rowThreshold ? rows : previews
    }

    /// 由路径与尺寸拼出缓存键。
    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// 读取缓存中的缩略图。
    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        tier(maxPixel).object(forKey: key(url, maxPixel))
    }

    /// cost 为解码后位图的真实占用，因此容量上限限制的是实际内存。
    func store(_ image: NSImage, for url: URL, maxPixel: CGFloat, cost: Int) {
        tier(maxPixel).setObject(image, forKey: key(url, maxPixel), cost: cost)
    }

    /// 已知图片宽高比时读取；与位图缓存一样由 NSCache 保证线程安全。
    func aspect(for url: URL) -> CGFloat? {
        aspects.object(forKey: url.path as NSString).map { CGFloat($0.doubleValue) }
    }

    func storeAspect(_ aspect: CGFloat, for url: URL) {
        aspects.setObject(NSNumber(value: aspect), forKey: url.path as NSString)
    }

    /// 关闭面板时释放大图位图；行内格子保留，以便再次打开时命中。
    func purgePreviews() {
        previews.removeAllObjects()
    }
}
