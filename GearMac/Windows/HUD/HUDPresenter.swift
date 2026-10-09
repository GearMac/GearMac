// 文件职责：HUD 通用呈现器：同一时刻只显示一个，负责替换、淡入淡出与驻留后自动消失。
// 分层：Coordinator/UI；@MainActor，持有并复用单个面板。
import AppKit
import SwiftUI

/// 两个 HUD 的公共行为：同一时刻只有一个，支持替换、淡入、驻留与淡出。
@MainActor
final class HUDPresenter {
    /// 面板相对可见区域底部的位置。
    enum Anchor {
        case edgeInset(CGFloat)
        case heightFraction(CGFloat)
    }

    private let anchor: Anchor
    private let dwell: TimeInterval
    private let screen: () -> NSScreen?
    private var panel: HUDPanel?
    private var dismissal: Task<Void, Never>?

    init(anchor: Anchor, dwell: TimeInterval, screen: @escaping () -> NSScreen?) {
        self.anchor = anchor
        self.dwell = dwell
        self.screen = screen
    }

    /// `size` 为 nil 时交由 SwiftUI 测量；进度类提示不自动隐藏，等待被替换。
    func show(_ view: some View, size: CGSize? = nil, dwells: Bool = true, interactive: Bool = false) {
        let panel = panel ?? make(acceptsMouseEvents: interactive)
        panel.ignoresMouseEvents = !interactive
        let host = NSHostingView(rootView: view)
        // 挂载后不要用 `host.frame` 取尺寸：AppKit 会把它重置为内容矩形。
        let content = size ?? host.fittingSize
        host.setFrameSize(content)
        panel.setContentSize(content)
        panel.contentView = host
        place(panel)
        // 屏幕上的面板可能正在淡出，因此让它重新显示，而不是再开一个。
        if panel.isVisible {
            panel.cancelFade()
        } else {
            panel.fadeIn(duration: Theme.Duration.enter) { panel.orderFrontRegardless() }
        }
        if dwells { scheduleDismissal() } else { dismissal?.cancel() }
    }

    /// 立即取消自动关闭并淡出当前面板。
    func dismiss() {
        dismissal?.cancel()
        guard let panel, panel.isVisible else { return }
        panel.fadeOut(duration: Theme.Duration.exit)
    }

    /// 重新计时自动关闭，使重复触发延长驻留而不是重播整段动画。
    func extend() {
        guard let panel, panel.isVisible else { return }
        panel.cancelFade()
        scheduleDismissal()
    }

    /// 当前是否有面板正在显示。
    var isShowing: Bool { panel?.isVisible ?? false }

    /// 按驻留时长排定自动淡出任务。
    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self, dwell] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.panel?.fadeOut(duration: Theme.Duration.exit)
        }
    }

    /// 创建并记录当前面板实例。
    private func make(acceptsMouseEvents: Bool) -> HUDPanel {
        let panel = HUDPanel(acceptsMouseEvents: acceptsMouseEvents)
        self.panel = panel
        return panel
    }

    /// 按锚点把面板水平居中并置于指定的纵向位置。
    private func place(_ panel: NSPanel) {
        guard let visible = screen()?.visibleFrame else { return }
        let y: CGFloat
        switch anchor {
        case .edgeInset(let inset):
            y = visible.minY + inset
        case .heightFraction(let fraction):
            y = visible.minY + visible.height * fraction
        }
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: y))
    }
}
