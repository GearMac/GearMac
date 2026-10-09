// 文件职责：房间预览的 AppKit 控制器，负责每台显示器上一个可穿透点击的预览面板及其卡片模型的显示、滑动与淡出。
// 分层：UI（@MainActor AppKit）；面板永不成为 key window，仅作只读展示。
// 改编自 Rooms (MIT)：https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
import SwiftUI

/// 预览中的一个待放置窗口。同一窗口保持相同 id，因此其卡片可以平滑滑动。
struct RoomPreviewCard: Identifiable, Equatable {
    let id: String
    /// AX 坐标，即布局方案解析所用的空间。
    var frame: CGRect
    var appName: String
    var title: String
    var appURL: URL?
}

/// 每个显示器的预览面板所绘制的内容：由后往前的卡片，以及需要避让的面板。
@MainActor
@Observable
final class RoomPreviewModel {
    var cards: [RoomPreviewCard] = []
    /// 面板在 AX 空间中的 frame，卡片的图标会避开它。
    var avoiding: CGRect?
}

/// 持有预览面板：每个显示器一个可穿透点击的面板，位于面板之下。
@MainActor
final class RoomPreviewController {
    private let model = RoomPreviewModel()
    private var panels: [RoomPreviewPanel] = []

    var isShowing: Bool { !panels.isEmpty }

    /// `cards` 由后往前；`avoiding` 是面板在屏幕坐标中的 frame。
    func show(_ cards: [RoomPreviewCard], avoiding: CGRect?) {
        let geometry = AXGeometry(screens: NSScreen.screens)
        model.avoiding = avoiding.map(geometry.flip)
        guard isShowing else {
            model.cards = cards
            open(geometry: geometry)
            return
        }
        let glide = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Theme.RoomMotion.glide
        withAnimation(glide) { model.cards = cards }
    }

    /// `settling` 表示 ↵ 之后的保持：窗口在预览下方移入，随后预览淡出。
    func hide(settling: Bool = false) {
        guard isShowing else { return }
        let closing = panels
        panels = []
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            closing.forEach { $0.orderOut(nil) }
            model.cards = []
            return
        }
        let duration = settling ? Theme.Duration.roomSettle : Theme.Duration.exit
        for panel in closing {
            panel.fadeOut(duration: duration) { [weak self] in
                // 淡出期间开始的新的 show 已接管卡片。
                guard let self, !self.isShowing else { return }
                self.model.cards = []
            }
        }
    }

    /// 为每台显示器创建预览面板并展示（开启动画减弱时直接前置）。
    private func open(geometry: AXGeometry) {
        panels = NSScreen.screens.map { screen in
            let frame = geometry.flip(screen.frame)
            let host = NSHostingView(
                rootView: RoomPreviewView(model: model, origin: frame.origin, size: frame.size))
            // frame 由控制器掌握；否则 hosting view 会自行决定窗口大小。
            host.sizingOptions = []
            let panel = RoomPreviewPanel()
            panel.contentView = host
            panel.setFrame(screen.frame, display: false)
            return panel
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for panel in panels {
            if reduceMotion {
                panel.orderFrontRegardless()
            } else {
                panel.fadeIn(duration: Theme.Duration.roomCardEnter) { panel.orderFrontRegardless() }
            }
        }
    }
}

/// 无边框、可穿透点击、永不成为 key window：预览是绘制在面板下方的读数。
private final class RoomPreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .paletteDropGuide
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
