// 文件职责：在加入会议前展示摄像头自检预览面板，并把用户的选择（加入/取消）以 Bool 异步返回给调用方。
// 分层：UI＋Coordinator（@MainActor）；同一时刻最多一个面板，面板关闭时随之停止摄像头。
import AppKit
import SwiftUI

/// 拥有「先看看自己」预览面板：同一时刻只允许一个，且面板关闭时摄像头随之停止。
@MainActor
final class CameraPreviewController {
    private let session = CameraSession()
    /// 注入 SwiftUI 环境，使预览视图能读取界面语言。
    private let settings: AppSettings
    private var panel: CameraPanel?
    private var continuation: CheckedContinuation<Bool, Never>?
    /// 在整个摄像头预热期间也保持为 true，避免重复快捷键叠加出多个预览。
    private var presenting = false

    /// 注入设置；预览视图通过环境读取它。
    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 先等摄像头就绪：在启动中的会话上覆盖面板会显示黑色画面。
    func present(meeting: MeetingEvent, now: Date) async -> Bool {
        guard !presenting else { return false }
        presenting = true
        defer { presenting = false }
        let feed = await session.start()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(meeting: meeting, now: now, feed: feed)
        }
    }

    /// 构建预览视图与面板，居中到鼠标所在屏幕并以淡入方式展示。
    private func show(meeting: MeetingEvent, now: Date, feed: CameraSession.Feed) {
        let view = CameraPreviewView(
            meeting: meeting, now: now, feed: feed,
            onJoin: { [weak self] in self?.finish(true) },
            onCancel: { [weak self] in self?.finish(false) })
        let hosting = NSHostingView(rootView: view.environment(settings))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in self?.finish(action == .primary) }
        self.panel = panel
        panel.centerOnCursorScreen()
        // 与面板一样不激活应用：取得键盘焦点，但不把用户从其应用中拉走。
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    /// 结束本次预览，返回用户是否选择加入，并淡出面板后停止摄像头。
    private func finish(_ taken: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        let closing = panel
        panel = nil
        closing?.onAction = nil
        continuation.resume(returning: taken)
        // 摄像头跟随面板一起关闭，而不是先于它：淡出中途拆除会让画面变黑。
        closing?.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // 除非淡出期间又弹出了一个已接管摄像头的预览。
            guard let self, !presenting else { return }
            session.stop()
        }
    }
}
