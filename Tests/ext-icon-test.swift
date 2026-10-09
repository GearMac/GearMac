// 文件职责：验证扩展图标的归一化绘制、缺失/异常输入的兜底，以及 SVG 中 Raycast 调色板颜色名在明暗模式下的解析与内联 data URL 解码。
// 分层：测试 harness；以 96pt 固定画布栅格化后按像素断言，涉及 AppKit 绘制，须在主线程运行。

import AppKit
import Foundation
import SwiftUI

@main
@MainActor
struct ExtensionIconTests {
    static var failures = 0

    /// 断言：条件为假时累计失败并打印 FAIL。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 图稿会被归一化，因此源图的透明留白不会改变它的绘制尺寸。
    static func artworkIsNormalized() {
        guard let bleed = writePNG("bleed", inset: 0), let padded = writePNG("padded", inset: 96)
        else { return expect(false, "the fixtures write") }
        defer {
            try? FileManager.default.removeItem(at: bleed.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: padded.deletingLastPathComponent())
        }

        guard let full = inkExtent(ExtensionIconCache.icon(atPath: bleed.path)),
            let margin = inkExtent(ExtensionIconCache.icon(atPath: padded.path))
        else { return expect(false, "both fixtures rasterize") }

        expect(abs(full - margin) <= 0.03, "padding can't change the drawn size: \(full) vs \(margin)")
        expect(
            full < IconCache.appIconExtent - 0.03,
            "artwork draws below an app icon's \(IconCache.appIconExtent): \(full)")
    }

    /// 文件缺失时仍返回图标，保证列表行不会出现空槽位。
    static func missingFileFallsBack() {
        let icon = ExtensionIconCache.icon(atPath: "/nonexistent/\(UUID().uuidString).png")
        expect(icon.size.width > 0, "a missing icon falls back to the puzzle-piece tile")
    }

    /// 没有 SVG 渲染器认识 Raycast 颜色名，因此该形状实际不绘制任何内容。
    static func paletteColorsInSVGResolve() async {
        // 每个配额类扩展都会绘制的用量圆环：一条轨道和一段圆弧，都带颜色名。
        let ring = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100px" height="100px"><circle cx="50" \
            cy="50" r="40" stroke-width="10" stroke="raycast-secondary-text" fill="none" />\
            <path d="M 50 10 A 40 40 0 0 0 20 25" stroke="raycast-green" stroke-width="10" \
            fill="none" /></svg>
            """
        let drawn = await drawnInk(ring, isDark: true)
        expect(drawn != nil, "the rewritten ring draws ink")
        // 两种编码都要覆盖：base64 会让扫描看不到颜色名，因此必须解码负载。
        let asBase64 = await drawnInk(ring, isDark: true, base64: true)
        expect(asBase64 != nil, "a base64 ring draws ink too")
        // Detail markdown 的尺寸查询参数跟在负载之后，不属于负载内容。
        let sized = await drawnInk(ring, isDark: true, query: "?raycast-width=32")
        expect(sized != nil, "a sized payload still draws")

        // 重写以完整名称匹配：更长未知名称内部出现的已知名不得被替换。
        let unknown = await drawnInk(circle(stroke: "raycast-green-invented"), isDark: true)
        expect(unknown == nil, "an unknown name is left whole, and draws nothing")
        let known = await drawnInk(circle(stroke: "raycast-green"), isDark: true)
        expect(known != nil, "the known name it shadows still resolves")

        let transparent =
            "<svg width=\"100\" height=\"100\"><rect width=\"100\" height=\"100\" "
            + "fill=\"transparent\"/><circle cx=\"50\" cy=\"50\" r=\"10\" fill=\"#000\"/></svg>"
        let transparentExtent = await drawnInk(transparent, isDark: false) ?? 1
        expect(transparentExtent < 0.3, "transparent fills no canvas")

        // 明暗模式对每条色阶的取值都不同，因此取色必须跟随所绘制的画布表面。
        let ramp = circle(stroke: "raycast-primary-text")
        let dark = await drawnColor(ramp, isDark: true)
        let light = await drawnColor(ramp, isDark: false)
        expect(dark?.brightnessComponent ?? 0 > 0.9, "the dark ramp strokes white ink")
        expect(light?.brightnessComponent ?? 1 < 0.1, "the light ramp strokes black ink")

        // 照片不包含颜色名，也不会被当作文本解码：它的字节必须原样送达解码器。
        let png = writePNG("photo", inset: 0).flatMap { try? Data(contentsOf: $0) }
        let photo = URL(string: "data:image/png;base64,\(png?.base64EncodedString() ?? "")")!
        let passed = await ExtensionIconCache.loadInlineAsync(
            photo, palette: ExtensionImage.svgPalette(isDark: true))
        expect(passed != nil, "an inline photo is passed through untouched")
    }

    /// 一个描边圆环，线宽足够大，使 96pt 栅格能干净地采样到颜色。
    static func circle(stroke: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100px\" height=\"100px\"><circle "
            + "cx=\"50\" cy=\"50\" r=\"36\" stroke-width=\"24\" stroke=\"\(stroke)\" "
            + "fill=\"none\" /></svg>"
    }

    /// 按列表行的绘制方式构造 SVG：用调色板解码 `data:` URL。
    static func drawnImage(
        _ svg: String, isDark: Bool, base64: Bool = false, query: String = ""
    ) async -> NSImage? {
        let allowed = CharacterSet(charactersIn: "<>\"# %{}|\\^~[]`").inverted
        let payload =
            base64
            ? Data(svg.utf8).base64EncodedString()
            : svg.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let header = base64 ? "data:image/svg+xml;base64," : "data:image/svg+xml,"
        guard let url = URL(string: header + payload + query) else { return nil }
        return await ExtensionIconCache.loadInlineAsync(
            url, palette: ExtensionImage.svgPalette(isDark: isDark))
    }

    /// 绘制给定 SVG 并返回其墨迹范围，用于判断是否真的画出了内容。
    static func drawnInk(
        _ svg: String, isDark: Bool, base64: Bool = false, query: String = ""
    ) async -> CGFloat? {
        await drawnImage(svg, isDark: isDark, base64: base64, query: query).flatMap(inkExtent)
    }

    /// 未解析的名称绝不会产生的颜色，因为该形状根本不绘制内容。
    static func drawnColor(_ svg: String, isDark: Bool) async -> NSColor? {
        await drawnImage(svg, isDark: isDark).flatMap(inkColor)
    }

    /// 两种编码的 `data:` URL，并附加 Detail markdown 的尺寸查询参数。
    static func inlineDataURLsDecode() async {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" \
            fill="none" stroke="currentColor"><path d="M2 12 L22 12"/></svg>
            """
        let escaped = CharacterSet(charactersIn: "<>\"# %{}|\\^~[]`").inverted
        guard let encoded = svg.addingPercentEncoding(withAllowedCharacters: escaped) else {
            return expect(false, "the fixture encodes")
        }

        for suffix in ["", "?raycast-width=200&raycast-height=200"] {
            let url = URL(string: "data:image/svg+xml,\(encoded)\(suffix)")!
            let image = await ExtensionIconCache.loadInlineAsync(url, palette: [:])
            expect(image?.size == NSSize(width: 24, height: 24), "percent-encoded SVG\(suffix)")
        }

        let pngURL = writePNG("inline", inset: 0)
        defer { pngURL.map { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
        let png = pngURL.flatMap { try? Data(contentsOf: $0) }
        guard let png else { return expect(false, "the PNG fixture writes") }
        let base64 = URL(string: "data:image/png;base64,\(png.base64EncodedString())")!
        let decoded = await ExtensionIconCache.loadInlineAsync(base64, palette: [:])
        expect(decoded != nil, "base64 payload decodes")

        let broken = URL(string: "data:image/png;base64,not-base-64")!
        let rejected = await ExtensionIconCache.loadInlineAsync(broken, palette: [:])
        expect(rejected == nil, "a broken payload is nil")
    }

    /// 在透明画布上绘制一个红色方块，四边各内缩 `inset` 像素。
    static func writePNG(_ name: String, inset: Int) -> URL? {
        let side = 512
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.red.setFill()
        NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-icon-test-\(UUID().uuidString)")
        guard let data = rep.representation(using: .png, properties: [:]),
            (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true))
                != nil
        else { return nil }
        let url = dir.appendingPathComponent("\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// alpha 包围盒较长的一边，以画布尺寸为比例表示。
    static func inkExtent(_ image: NSImage) -> CGFloat? {
        rasterize(image).flatMap { rep in
            var minX = 96, maxX = -1, minY = 96, maxY = -1
            for y in 0..<96 {
                for x in 0..<96 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / 96
        }
    }

    /// 绘制出的最不透明像素；调色板色阶的描边不会达到完全不透明。
    static func inkColor(_ image: NSImage) -> NSColor? {
        guard let rep = rasterize(image) else { return nil }
        var best: NSColor?
        var strongest: CGFloat = 0.5
        for y in 0..<96 {
            for x in 0..<96 {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > strongest else {
                    continue
                }
                strongest = color.alphaComponent
                best = color.usingColorSpace(.sRGB)
            }
        }
        return best
    }

    /// 把图像绘制到固定 96pt 画布，所有像素断言都读取该结果。
    static func rasterize(_ image: NSImage) -> NSBitmapImageRep? {
        let side = 96
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 依次运行全部检查，最后按失败数决定退出码。
    static func main() async {
        artworkIsNormalized()
        missingFileFallsBack()
        await inlineDataURLsDecode()
        await paletteColorsInSVGResolve()

        print(failures == 0 ? "Extension icon tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
