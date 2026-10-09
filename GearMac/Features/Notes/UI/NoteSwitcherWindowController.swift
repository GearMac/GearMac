// 文件职责：管理笔记切换器（搜索/切换笔记）的子窗口，负责其定位、尺寸自适应与快捷键转发。
// 分层：UI 窗口层；`@MainActor` 限定，作为笔记面板的子窗口跟随宿主移动。
import AppKit
import SwiftUI

/// 笔记面板的子窗口，因此它跟随宿主的每次移动，同时又能超出宿主尺寸。
@MainActor
final class NoteSwitcherWindowController: NSObject, NSWindowDelegate {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private var height = Theme.Size.noteSwitcher.height

    /// 绑定所属的 NotesCoordinator。
    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    /// 在宿主窗口下方显示切换器，并将其设为宿主的子窗口。
    func show(under host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, under: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    /// 隐藏切换器并解除与宿主的子窗口关系。
    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// 像弹出框一样关闭；焦点保留在点击发生的位置。
    func windowDidResignKey(_ notification: Notification) {
        guard coordinator.isSwitcherPresented else { return }
        coordinator.closeSwitcher(focusEditor: false)
    }

    // MARK: - Private

    /// 若面板尚未创建则惰性创建，并配置回调与快捷键。
    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NoteSwitcherView { [weak self] in self?.resize(toContentHeight: $0) }
            .environment(coordinator)
            .environment(coordinator.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteSwitcher,
            styleMask: .borderless,
            acceptsMain: false)
        panel.delegate = self
        let dismiss: () -> Void = { [weak coordinator] in coordinator?.closeSwitcher() }
        panel.onEscape = dismiss
        panel.onDeleteChord = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        // 切换器弹出时笔记窗口不是 key，因此需要在这里处理其关闭快捷键。
        panel.commandChords = [
            "n": { [weak coordinator] in coordinator?.createNote() },
            "w": dismiss,
            "p": dismiss
        ]
        self.panel = panel
        return panel
    }

    /// 将面板居中定位到宿主窗口下方的固定偏移处。
    private func anchor(_ panel: NotesPanel, under host: NSWindow) {
        let size = CGSize(width: Theme.Size.noteSwitcher.width, height: height)
        let host = host.frame
        let origin = CGPoint(
            x: host.midX - size.width / 2,
            y: host.maxY - Theme.Size.noteTitlebar - Theme.Size.noteSwitcherDrop - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    /// 根据内容高度调整面板尺寸（不超过上限），变化不大时跳过以兔抖动。
    private func resize(toContentHeight content: CGFloat) {
        let fitted = min(Theme.Size.noteSwitcher.height, Theme.Size.noteSearchHeight + content)
        guard abs(fitted - height) > 0.5 else { return }
        height = fitted
        guard let panel, let host = panel.parent else { return }
        anchor(panel, under: host)
        panel.invalidateShadow()
    }
}
