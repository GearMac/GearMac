// 文件职责：把剪贴板条目转换为拖拽负载，包含文件缩略图、链接双类型以及绘制出的文本预览图。
// 分层：UI；AppKit 拖拽支持，只构造 NSPasteboardItem/NSImage，不修改业务状态。
import AppKit

/// 为剪贴板拖拽负载提供对应的拖拽项与预览图。
extension ClipDragPayload {
    /// 行内缩略图已按该尺寸缓存，因此预览无需重新解码。
    private static let previewPixel: CGFloat = 64

    /// 链接会从单个条目写入两种类型，接收方按自身读取方式取用。
    var dragItem: RowDragItem {
        switch self {
        case .file(let url):
            let tile =
                ImageThumbnail.cached(url, maxPixel: Self.previewPixel)
                ?? FilePreviewThumbnail.cached(url, maxPixel: Self.previewPixel)
            return .file(url, image: tile)
        case .link(let url, let text):
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .URL)
            item.setString(text, forType: .string)
            return RowDragItem(writer: item, image: Self.textImage(text))
        case .text(let text):
            return RowDragItem(writer: text as NSString, image: Self.textImage(text))
        }
    }

    /// 采用绘制而非截图：SwiftUI 绘制到图层，`cacheDisplay` 会返回空白位图。
    private static func textImage(_ copy: String) -> NSImage {
        let line = copy.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let string = NSAttributedString(
            string: String(line.prefix(60)),
            attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
            ])
        let inset = NSSize(width: 10, height: 6)
        let text = string.size()
        let size = NSSize(
            width: min(text.width, 320) + inset.width * 2, height: text.height + inset.height * 2)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(
                roundedRect: rect, xRadius: Theme.Radius.thumbnail, yRadius: Theme.Radius.thumbnail
            ).fill()
            string.draw(
                in: NSRect(
                    x: inset.width, y: inset.height, width: rect.width - inset.width * 2,
                    height: text.height))
            return true
        }
    }
}
