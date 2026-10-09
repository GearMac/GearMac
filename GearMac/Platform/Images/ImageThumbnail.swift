// 文件职责：用 ImageIO 把图片降采样为所需尺寸并做内存受限的缓存加载，另提供像素尺寸读取。
// 分层：Service；不依赖 SwiftUI，解码在后台线程执行。
import AppKit
import ImageIO

/// 降采样、内存受限的图片加载：ImageIO 只解码到所需尺寸。
enum ImageThumbnail {
    /// 长图按宽高比抬高解码预算后，单张卡片位图可达 MB 级，行内层预算随之放大。
    private static let cache = ThumbnailCache(
        rowBytes: 32 * 1024 * 1024, previewBytes: 48 * 1024 * 1024)

    /// 关闭面板时释放预览位图；行内缩略图保留，以便再次打开时命中。
    static func purgePreviews() {
        cache.purgePreviews()
    }

    /// 只读缓存、绝不访问磁盘，使已热的缩略图能在同一帧内渲染完成。
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    /// 刚解码、此后不变的 `NSImage` 可以安全跨 actor 边界传递。
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// 返回长边限制在 `maxPixel` 内的缩略图，按路径与尺寸缓存；同步解码。
    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.store(
            image, for: url, maxPixel: maxPixel, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// 覆盖式缓存读取：宽高比已知（此前解码过）才可能命中，保持同帧渲染。
    static func cachedCovering(_ url: URL, box: CGSize, scale: CGFloat) -> NSImage? {
        guard let aspect = cache.aspect(for: url) else { return nil }
        return cached(
            url, maxPixel: ThumbnailCover.longEdge(aspect: aspect, box: box, pixelScale: scale))
    }

    /// 覆盖式异步解码：长边由显示框、像素密度与宽高比共同决定，长图随之抬高预算。
    static func loadCovering(_ url: URL, box: CGSize, scale: CGFloat) async -> NSImage? {
        if let hit = cachedCovering(url, box: box, scale: scale) { return hit }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: decodeCovering(url, box: box, scale: scale))
        }.value.image
    }

    /// 宽高比只读元数据；解码长边不超过源图，小图不放大出无谓像素。
    private static func decodeCovering(_ url: URL, box: CGSize, scale: CGFloat) -> NSImage? {
        let native = pixelSize(of: url)
        let aspect = native.map { $0.width / $0.height } ?? 1
        cache.storeAspect(aspect, for: url)
        var longEdge = ThumbnailCover.longEdge(aspect: aspect, box: box, pixelScale: scale)
        if let native { longEdge = min(longEdge, max(native.width, native.height)) }
        return load(url, maxPixel: longEdge)
    }

    /// 从图片元数据读取像素尺寸——不做完整解码。
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
