// 文件职责：在进程内用 PDFKit 绘制 PDF 预览，使滚轮滚动行为与 QuickLook 的文本视图一致。
// 分层：UI；NSViewRepresentable 包装 PDFView。
import PDFKit
import SwiftUI

/// 在进程内绘制的 PDF，滚轮能像作用于 QuickLook 文本视图那样作用于它。
struct PDFSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PreviewPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: ()) {
        view.document = nil
    }
}

/// 点击页面不能把键盘焦点从搜索框移开。
private final class PreviewPDFView: PDFView, KeyboardFocusRefusing {}
