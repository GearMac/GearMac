// 文件职责：把扩展的 `ImageLike` 值渲染为菜单栏用的 `NSImage`，包括浅/深色自适应版本与模板图。
// 分层：UI；仅处理菜单栏尺寸（默认 18pt）的位图，符号与字形按深浅两套外观分别绘制。
import SwiftUI

/// 菜单栏图标绘制器：把 `ImageLike` 解析为适应浅/深色外观的 `NSImage`。
@MainActor
enum ExtensionMenuBarImage {
    /// 分别绘制浅色与深色版本，合成一个随外观自动切换的 `NSImage`。
    static func loadAdaptive(_ value: RenderValue?, assetsPath: String, size: CGFloat = 18) async -> NSImage?
    {
        guard let light = await load(value, assetsPath: assetsPath, isDark: false, size: size) else {
            return nil
        }
        guard let dark = await load(value, assetsPath: assetsPath, isDark: true, size: size),
            !Task.isCancelled
        else { return light }
        let image = NSImage(size: light.size, flipped: false) { rect in
            let source = NSAppearance.currentDrawing().isDark ? dark : light
            source.draw(in: rect)
            return true
        }
        image.isTemplate = light.isTemplate && dark.isTemplate
        return image
    }

    /// 按指定外观把值渲染为固定尺寸的菜单栏 `NSImage`，支持圆形遮罩与 tint 着色。
    static func load(_ value: RenderValue?, assetsPath: String, isDark: Bool, size: CGFloat) async -> NSImage?
    {
        guard let resolved = ExtensionImage.resolve(value, assetsPath: assetsPath, isDark: isDark) else {
            return nil
        }
        let source: NSImage?
        var template = false
        switch resolved.source {
        case .symbol(let name):
            source = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            template = resolved.tint == nil
        case .glyph(let text):
            source = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                (text as NSString).draw(
                    in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size - 2)])
                return true
            }
        default:
            // 这里只绘制符号或字形；调色板已负责加载全部位图。
            source = await ExtensionImage.load(resolved, isDark: isDark, animates: true)
        }
        guard !Task.isCancelled, let source, source.size.width > 0, source.size.height > 0 else { return nil }
        let tint = resolved.tint.map(NSColor.init)
        let circular = resolved.isCircular
        let result = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if circular { NSBezierPath(ovalIn: rect).addClip() }
            let scale = min(rect.width / source.size.width, rect.height / source.size.height)
            let fitted = NSRect(
                x: (rect.width - source.size.width * scale) / 2,
                y: (rect.height - source.size.height * scale) / 2,
                width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: fitted)
            if let tint {
                tint.setFill()
                rect.fill(using: .sourceIn)
            }
            return true
        }
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size * 2), pixelsHigh: Int(size * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        bitmap.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            result.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        image.isTemplate = template
        return image
    }
}
