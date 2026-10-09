// 文件职责：通过 QuickLookThumbnailing 为任意文件类型渲染内容缩略图，并缓存结果。
// 分层：Service；不依赖 SwiftUI，缓存与渲染分离。
import AppKit
import QuickLookThumbnailing

/// 任意文件类型的内容缩略图——视频首帧、PDF 页面，否则回退为该类型的图标。
enum FilePreviewThumbnail {
    /// 覆盖式解码会按需抬高大图预算，行内层预算随之放大。
    private static let cache = ThumbnailCache(
        rowBytes: 24 * 1024 * 1024, previewBytes: 32 * 1024 * 1024)

    /// 只读缓存、绝不访问磁盘，使已热的格子能在同一帧内渲染完成。
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    /// 释放预览位图。
    static func purgePreviews() {
        cache.purgePreviews()
    }

    /// 覆盖式缓存读取：宽高比已知（此前渲染过）才可能命中，保持同帧渲染。
    static func cachedCovering(_ url: URL, box: CGSize, scale: CGFloat) -> NSImage? {
        guard let aspect = cache.aspect(for: url) else { return nil }
        return cached(
            url, maxPixel: ThumbnailCover.longEdge(aspect: aspect, box: box, pixelScale: scale))
    }

    /// 覆盖式异步渲染：图像文件按元数据宽高比定预算，其余类型按方形图标。
    static func loadCovering(_ url: URL, box: CGSize, scale: CGFloat) async -> NSImage? {
        if let hit = cachedCovering(url, box: box, scale: scale) { return hit }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let native = ImageThumbnail.pixelSize(of: url)
        let aspect = native.map { $0.width / $0.height } ?? 1
        var longEdge = ThumbnailCover.longEdge(aspect: aspect, box: box, pixelScale: scale)
        if let native { longEdge = min(longEdge, max(native.width, native.height)) }
        cache.storeAspect(aspect, for: url)
        // QL 的 size 计 pt、scale 放大像素；scale 1 让 longEdge 直接就是像素预算。
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: longEdge, height: longEdge), scale: 1,
            representationTypes: .all)
        let rendered = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request)
        guard let cgImage = rendered?.cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.store(
            image, for: url, maxPixel: longEdge, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
