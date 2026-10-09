// 文件职责：根据文件类型选择并渲染对应预览视图（QuickLook / PDF / 媒体 / 纯文本），必要时先读取文件头部进行嗵探。
// 分层：UI；SwiftUI 视图，文件头读取在后台任务中执行。
import SwiftUI

/// 按适合该文件的方式渲染。由预览面板与 ⌘Y 浮层共用。
struct FileSearchSurface: View {
    let url: URL
    var autoplays = false
    @State private var sniffed: Sniffed?

    /// 扩展名无法确定类型时读取的文件头部，每次选中读取一次。
    private struct Sniffed: Sendable {
        let url: URL
        let kind: FileSearchPreviewKind
        let text: String?
    }

    /// 足够读取一个源文件，同时限定了排除二进制文件所需付出的代价。
    private nonisolated static let headLimit = 256 * 1024

    var body: some View {
        surface.task(id: url) { await sniff() }
    }

    /// 按已确定的预览类型渲染对应视图；类型尚未确定时先置空。
    @ViewBuilder private var surface: some View {
        let sniffed = self.sniffed?.url == url ? self.sniffed : nil
        switch FileSearchPreviewKind(pathExtension: url.pathExtension) ?? sniffed?.kind {
        case .quickLook: QuickLookSurface(url: url)
        case .pdf: PDFSurface(url: url)
        case .media: FileSearchMediaPlayer(url: url, autoplays: autoplays)
        case .text: PlainTextSurface(text: sniffed?.text ?? "")
        case nil: Color.clear
        }
    }

    /// 当扩展名不足以判断类型时，在后台读取文件头部并嗵探。
    private func sniff() async {
        guard FileSearchPreviewKind(pathExtension: url.pathExtension) == nil else { return }
        let url = url
        let read = await Task.detached(priority: .userInitiated) { Self.readHead(of: url) }.value
        // 取消选中并不会停止读取，因此迟到的读取结果不能落到下一个文件上。
        guard !Task.isCancelled else { return }
        sniffed = read
    }

    /// 读取文件头部字节并判断预览类型（含文本内容）。
    private nonisolated static func readHead(of url: URL) -> Sniffed {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Sniffed(url: url, kind: .quickLook, text: nil)
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: headLimit)) ?? Data()
        let kind = FileSearchPreviewKind(
            pathExtension: url.pathExtension, head: head, isWholeFile: head.count < headLimit)
        let text = kind == .text ? String(decoding: head, as: UTF8.self) : nil
        return Sniffed(url: url, kind: kind, text: text)
    }
}
