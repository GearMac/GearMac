// 文件职责：用 QuickLookUI 的 QLPreviewView 在面板内实时预览单个文件（可滚动、可播放）。
// 分层：UI；NSViewRepresentable 包装 QLPreviewView。
import QuickLookUI
import SwiftUI

/// 单个文件的实时 QuickLook 视图：即文档本体，可按其本身方式滚动与播放。
struct QuickLookSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        // 用方向键浏览列表时不能触发影片播放，且面板的生命周期长于任何一次预览。
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard view.previewItem as? URL != url else { return }
        view.previewItem = url as NSURL
    }

    /// 预览会一直持有解码器直到被关闭，而这里是最后一次释放机会。
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
