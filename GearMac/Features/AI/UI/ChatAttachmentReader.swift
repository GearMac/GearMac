// 文件职责：把文件或粘贴的图片校验、限尺寸后转换为输入框可暂存的附件负载（图片 / 文档）。
// 分层：Service（非主线程执行，nonisolated）；不 import SwiftUI，只依赖 AppKit 与附件策略/预算常量。
import AppKit

/// 把文件或粘贴的图片转换成输入框需要暂存的内容；所有调用都在主线程之外执行。
nonisolated enum ChatAttachmentReader {
    /// 在脱离主线程的读取过程中携带暂存文件的结果。
    struct Staged: Sendable {
        let payload: ChatAttachment.Payload
        let name: String
        let preview: Data?
    }

    /// 用拒绝结果而非 nil，这样一次粘贴里坏掉的文件会被指名报错而不是无声消失。
    enum Outcome: Sendable {
        case staged(Staged)
        case failed(ChatAttachmentRefusal)
    }

    private static let maxImageEdge: CGFloat = 1_568

    /// 把粘贴/拖入的图片数据压到尺寸上限内并生成暂存的图片负载。
    static func image(_ data: Data) -> Outcome {
        guard let png = boundedPNG(data) else { return .failed(.size) }
        return .staged(
            Staged(
                payload: .image(AIImage(data: png, mimeType: "image/png")), name: "Image",
                preview: preview(png)))
    }

    /// 先查大小再读取，因此四 GB 的 CSV 永远不会被整体读入内存。
    static func read(_ file: URL) -> Outcome {
        let name = file.lastPathComponent
        guard let kind = AIAttachmentPolicy.kind(forFileName: name) else {
            return .failed(.unsupported(file.pathExtension.lowercased()))
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ceiling =
            kind == .text ? AIAttachmentBudget.maxInlinedTextBytes : AIAttachmentBudget.maxBytes
        guard size <= ceiling else { return .failed(kind == .text ? .textTooLong : .size) }
        guard let bytes = try? Data(contentsOf: file) else { return .failed(.unreadable) }
        let mimeType = AIAttachmentPolicy.mimeType(forFileName: name)
        switch kind {
        case .image:
            guard let png = boundedPNG(bytes) else { return .failed(.unreadable) }
            return .staged(
                Staged(
                    payload: .image(AIImage(data: png, mimeType: "image/png")), name: name,
                    preview: preview(png)))
        case .pdf:
            return .staged(
                Staged(
                    payload: .document(AIDocument(data: bytes, mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        case .text:
            // 从解码后的字符串重新编码，因此无法解码的字节会被拒绝而不是产生乱码。
            guard let decoded = String(data: bytes, encoding: .utf8) else {
                return .failed(.undecodable)
            }
            return .staged(
                Staged(
                    payload: .document(
                        AIDocument(data: Data(decoded.utf8), mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        }
    }

    /// 胶囊的缩略图，在这里编码一次，避免在头部每敲一次键就解码一次。
    private static func preview(_ png: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: png) else { return nil }
        return scaled(source, toFit: 40)
    }

    /// 保证 PNG 最长边不超过 maxImageEdge：已符合则原样输出，否则等比缩小。
    private static func boundedPNG(_ data: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: data) else { return nil }
        guard max(source.pixelsWide, source.pixelsHigh) > Int(maxImageEdge) else {
            return source.representation(using: .png, properties: [:])
        }
        return scaled(source, toFit: maxImageEdge)
    }

    /// 把位图等比缩放到最长边为 edge，并返回 PNG 数据。
    private static func scaled(_ source: NSBitmapImageRep, toFit edge: CGFloat) -> Data? {
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let scale = min(1, edge / max(width, height))
        let size = NSSize(
            width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        guard
            let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: scaled)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .png, properties: [:])
    }
}
