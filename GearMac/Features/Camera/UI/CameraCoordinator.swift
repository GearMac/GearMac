// 文件职责：独立摄像头面板的协调器：开/关面板、切换摄像头、拍照并写入剪贴板。
// 分层：Coordinator（@MainActor）；同一时刻只有一个面板，面板关闭时摄像头随之停止。
import AppKit
import SwiftUI

/// 拥有独立的摄像头界面：同一时刻只有一个面板，且面板关闭时摄像头随之停止。
@MainActor
@Observable
final class CameraCoordinator {
    private(set) var feed: CameraSession.Feed = .noCamera
    private(set) var canSwitchCamera = false
    /// 在本次启动中记住该设置，重新打开命令时保留你已满意的画面朝向。
    var mirrored = true

    @ObservationIgnored private let session = CameraSession(.capture)
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var panel: CameraPanel?
    /// 在整个摄像头预热期间也保持为 true，避免重复快捷键叠加出多个面板。
    @ObservationIgnored private var opening = false

    /// 注入 `AppCore`；以 unowned 持有，避免循环引用。
    init(core: AppCore) {
        self.core = core
    }

    /// 先等摄像头就绪：在启动中的会话上覆盖面板会显示黑色舞台。
    func show() async {
        // 系统 UI 会收回失去 key 的面板，这里重新取回，使 ↵ 和 Esc 能再次送达。
        if let panel {
            panel.makeKey()
            return
        }
        guard !opening else { return }
        opening = true
        defer { opening = false }
        feed = await session.start()
        canSwitchCamera = session.hasMultipleDevices
        present()
    }

    /// 淡出并关闭面板，随后停止摄像头。
    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.onAction = nil
        // 摄像头跟随面板一起关闭，而不是先于它：淡出中途拆除会让画面变黑。
        closing.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // 除非淡出期间又弹出了一个已接管摄像头的面板。
            guard let self, !opening else { return }
            session.stop()
        }
    }

    /// 切换到下一个可用摄像头。
    func switchCamera() {
        Task { await session.switchToNextDevice() }
    }

    /// 拍照后面板随之关闭：命令已完成，摄像头指示灯也一并熄灭。
    func takePhoto() {
        guard case .live = feed else { return }
        let mirrored = mirrored
        Task {
            let png = await session.capturePhoto(mirrored: mirrored)
            close()
            guard let png else {
                core.showMessage(core.settings.text(CameraKey.photoFailed), tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage(core.settings.text(CameraKey.photoCopied))
        }
    }

    /// 构建并淡入摄像头面板，居中到鼠标所在屏幕。
    private func present() {
        // 注入设置，使面板内的视图能读取界面语言。
        let hosting = NSHostingView(
            rootView: CameraView(coordinator: self).environment(core.settings))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in
            guard let self else { return }
            if action == .primary { takePhoto() } else { close() }
        }
        self.panel = panel
        panel.centerOnCursorScreen()
        // 与面板一样不激活应用：取得键盘焦点，但不把用户从其应用中拉走。
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }
}
