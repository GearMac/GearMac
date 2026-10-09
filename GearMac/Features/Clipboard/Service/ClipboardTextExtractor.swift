// 文件职责：从图片与 PDF 中通过 Vision OCR 提取文本，并对尺寸、页数与字节数做上限控制。
// 分层：Service；nonisolated 纯工具枚举，不触碰 UI 与持久化。
import Foundation
import ImageIO
import PDFKit
import Vision

/// 剪贴板文本提取器：对图片与 PDF 执行 OCR，并限制输出规模。
nonisolated enum ClipboardTextExtractor {
    static let maximumTextBytes = 32_000
    private static let maximumFileBytes = 32_000_000
    private static let maximumPages = 64
    private static let maximumDimension = 4096
    private static let maximumPixels = 2048 * 2048
    private static let stripHeight = 2048
    /// 比任何一行文本都高，保证每一行都完整落在至少一条切片内。
    private static let stripOverlap = 256

    /// 提取失败的原因：内容不可读。
    enum Failure: Error { case unreadable }

    /// 从指定文件提取文本：PDF 走文本层或渲染 OCR，图片走 OCR；超出限制时返回空串。
    static func extract(at url: URL, isPDF: Bool) async throws -> String {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
            size <= maximumFileBytes
        else { return "" }
        if isPDF { return try await extractPDF(url) }
        guard let image = autoreleasepool(invoking: { image(at: url) }) else { throw Failure.unreadable }
        return bounded(try await recognize(image))
    }

    /// 读取图片并按像素上限生成缩略图，读取失败返回 nil。
    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        let scale = min(1, sqrt(Double(maximumPixels) / width / height))
        let dimension = Int(min(Double(maximumDimension), max(1, max(width, height) * scale)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 采用整宽切片，避免文本行被按列切断，从而保持阅读顺序。
    private static func recognize(_ image: CGImage) async throws -> String {
        var text = ""
        for top in stride(from: 0, to: max(1, image.height - stripOverlap), by: stripHeight - stripOverlap) {
            try Task.checkCancellation()
            let height = min(stripHeight, image.height - top)
            let rect = CGRect(x: 0, y: top, width: image.width, height: height)
            guard let strip = image.cropping(to: rect) else { continue }
            let owned = ownedRows(isFirst: top == 0, isLast: top + height == image.height, height: height)
            let content = try await recognizeStrip(strip, keepingCentresIn: owned)
            if !text.isEmpty, !content.isEmpty { text += "\n" }
            text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
            if text.utf8.count >= maximumTextBytes - 4 { return text }
        }
        return text
    }

    /// 相邻切片从中间平分重叠区域，使重叠处的文本行恰好只保留一次。
    private static func ownedRows(isFirst: Bool, isLast: Bool, height: Int) -> Range<Double> {
        let lower = isFirst ? -.infinity : Double(stripOverlap / 2)
        let upper = isLast ? .infinity : Double(height - stripOverlap / 2)
        return lower..<upper
    }

    /// 对单条切片执行 Vision 文本识别，只保留中心落在指定行范围内的结果。
    private static func recognizeStrip(
        _ strip: CGImage, keepingCentresIn rows: Range<Double>
    ) async throws -> String {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeightFraction = 0
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: strip)
        try Task.checkCancellation()
        let size = CGSize(width: strip.width, height: strip.height)
        return
            observations
            .filter { rows.contains($0.boundingBox.toImageCoordinates(size, origin: .upperLeft).midY) }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// 提取 PDF 文本：优先使用文本层，无文本的页面渲染后再 OCR。
    private static func extractPDF(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw Failure.unreadable
        }
        var text = ""
        for index in 0..<min(document.pageCount, maximumPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var content = autoreleasepool { page.string ?? "" }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty, let image = autoreleasepool(invoking: { render(page) }) {
                content = try await recognize(image)
            }
            if !text.isEmpty, !content.isEmpty { text += "\n" }
            text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
            if text.utf8.count >= maximumTextBytes - 4 { break }
        }
        return text
    }

    /// 将 PDF 页面渲染为位图，按尺寸与像素上限缩放；失败返回 nil。
    private static func render(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
            bounds.width > 0, bounds.height > 0
        else { return nil }
        let scale = min(
            2, CGFloat(maximumDimension) / max(bounds.width, bounds.height),
            sqrt(CGFloat(maximumPixels) / bounds.width / bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(
            reference.getDrawingTransform(
                .mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }

    /// 按 UTF-8 字节上限裁剪文本，并保证不在多字节字符中间截断。
    private static func bounded(_ text: String, bytes: Int = maximumTextBytes) -> String {
        var prefix = text.utf8.prefix(max(0, bytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }
}
