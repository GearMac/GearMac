// 文件职责：从显示框、像素密度与图片宽高比推导覆盖式缩略图的解码长边。
// 分层：Service；纯函数，不做任何 IO。
import CoreGraphics

/// 覆盖（scaledToFill）解码预算：极端长图在 2048px 封顶，与文本识别的条带宽度同源。
enum ThumbnailCover {
    static let maxLongEdge: CGFloat = 2048

    /// 覆盖显示框后不放大所需的最小解码长边；宽高比越极端，长边越长。
    static func longEdge(aspect: CGFloat, box: CGSize, pixelScale: CGFloat) -> CGFloat {
        min(
            maxLongEdge,
            (max(box.width / aspect, box.height * aspect) * pixelScale).rounded(.up))
    }
}
