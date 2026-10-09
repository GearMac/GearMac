// 文件职责：管理标题层级菜单的子窗口，负责其创建、定位、显示与隐藏。
// 分层：UI 窗口层；`@MainActor` 限定，使用无边框子窗口且不抢编辑器焦点。
import AppKit
import SwiftUI

/// 子窗口形式，使菜单能超出较矮的笔记窗口；它从不从编辑器抢走 key 状态。
@MainActor
final class NoteHeadingMenuWindowController {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?

    /// 绑定所属的 NotesCoordinator。
    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    /// 在宿主窗口上方显示菜单，并将其设为宿主的子窗口。
    func show(above host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, above: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    /// 隐藏菜单并解除与宿主的子窗口关系。
    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// 若面板尚未创建则惰性创建，并缓存复用。
    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: NoteHeadingMenuView().environment(coordinator).environment(coordinator.settings))
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteHeadingMenu,
            styleMask: .borderless,
            acceptsMain: false)
        panel.acceptsKey = false
        self.panel = panel
        return panel
    }

    /// 挂在标题按钮本身上，而它的 frame 从 SwiftUI 工具条传来时是翻转坐标。
    private func anchor(_ panel: NotesPanel, above host: NSWindow) {
        let button = coordinator.headingButtonFrame
        let origin = CGPoint(
            x: host.frame.minX + button.minX,
            y: host.frame.maxY - button.minY + Theme.Spacing.xs)
        panel.setFrame(NSRect(origin: origin, size: Theme.Size.noteHeadingMenu), display: false)
    }
}
