// 文件职责：拖拽调色板时显示对齐参考线的面板控制器，实时指示默认位置（home）与当前拖拽点。
// 分层：UI/Coordinator（AppKit + SwiftUI）；@MainActor，仅在有活跃拖拽时显示。
import AppKit
import SwiftUI

/// 由窗口控制器驱动：只有活跃拖拽才有可作为指向目标的 home 位置。
@MainActor
final class PaletteDropGuideController {
    private var panel: NSPanel?
    private var host: NSHostingView<PaletteDropGuideView>?
    private var screenFrame: CGRect = .zero
    private var home: CGPoint = .zero
    private var dragged: CGPoint = .zero
    private var width: CGFloat = 0
    private var verticalFlash = false
    private var horizontalFlash = false
    private var flashTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// 闪烁提示的轴线：垂直、水平或两者同时。
    enum Axis { case vertical, horizontal, both }

    /// 显示参考线，`home` 为默认位置的左上角（屏幕坐标）。
    func show(home: CGPoint, width: CGFloat, screenFrame: CGRect, dragged: CGPoint) {
        self.home = home
        self.width = width
        self.screenFrame = screenFrame
        self.dragged = dragged
        hideTask?.cancel()
        hideTask = nil
        let panel = ensurePanel()
        panel.setFrame(screenFrame, display: false)
        render()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Duration.dropGuide
            panel.animator().alphaValue = 1
        }
    }

    /// 拖拽中途重新指向。`windowDidMove` 会持续触发，因此无变化的移动不做任何事。
    func move(home: CGPoint, screenFrame: CGRect, dragged: CGPoint) {
        guard self.home != home || self.screenFrame != screenFrame || self.dragged != dragged else {
            return
        }
        let crossedScreens = self.screenFrame != screenFrame
        self.home = home
        self.screenFrame = screenFrame
        self.dragged = dragged
        if crossedScreens { panel?.setFrame(screenFrame, display: false) }
        render()
    }

    /// 沿给定轴短暂闪烁参考线，提示已吸附到该轴。
    func flash(_ axis: Axis) {
        flashTask?.cancel()
        verticalFlash = axis != .horizontal
        horizontalFlash = axis != .vertical
        render()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Duration.dropGuide * 2))
            guard !Task.isCancelled, let self else { return }
            verticalFlash = false
            horizontalFlash = false
            render()
            flashTask = nil
        }
    }

    /// 淡出并隐藏参考线面板。
    func hide() {
        flashTask?.cancel()
        flashTask = nil
        verticalFlash = false
        horizontalFlash = false
        guard let panel, panel.isVisible else { return }
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Duration.dropGuide
            panel.animator().alphaValue = 0
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Duration.dropGuide))
            guard !Task.isCancelled, let self else { return }
            panel.orderOut(nil)
            hideTask = nil
        }
    }

    // MARK: - Private

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let host = NSHostingView(rootView: guides)
        // 帧由控制器拥有；不设此选项宿主视图会自行决定窗口尺寸。
        host.sizingOptions = []
        let panel = PaletteDropGuidePanel()
        panel.contentView = host
        self.host = host
        self.panel = panel
        return panel
    }

    private func render() {
        host?.rootView = guides
    }

    /// AppKit 的 y 从屏幕原点向上增长，SwiftUI 的 y 从窗口顶部向下增长。
    private var guides: PaletteDropGuideView {
        PaletteDropGuideView(
            topLeft: CGPoint(x: home.x - screenFrame.minX, y: screenFrame.maxY - home.y),
            width: width, horizontalDistance: abs(dragged.x - home.x),
            verticalDistance: abs(dragged.y - home.y),
            verticalFlash: verticalFlash, horizontalFlash: horizontalFlash)
    }
}

/// 无边框、鼠标穿透、永不成为 key：参考线只是读数，不是可交互表面。
private final class PaletteDropGuidePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .paletteDropGuide
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
