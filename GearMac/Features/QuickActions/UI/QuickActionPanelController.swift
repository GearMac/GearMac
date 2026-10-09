// 文件职责：持有 Quick Action 结果面板的唯一实例，负责面板的创建、定位、高度调整、键位回调与关闭。
// 分层：UI；@MainActor 兼任 NSWindowDelegate，统一管理面板生命周期。
import AppKit
import SwiftUI

/// 持有结果面板：同一时刻仅一个，面板显示期间目标应用会保持其选中文本。
@MainActor
final class QuickActionPanelController: NSObject, NSWindowDelegate {
    private var panel: QuickActionPanel?
    private var state: QuickActionPanelState?
    private var settings: AppSettings?
    private var onReplace: ((String) -> Void)?
    private var onRetranslate: ((Locale.Language) -> Void)?

    /// 与指针错开，避免面板正好出现在触发它的那只手下方。
    private static let cursorOffset: CGFloat = 12
    private static let screenMargin: CGFloat = 8
    /// 系统「语言与地区」设置面板的 bundle ID。
    private static let languageSettingsPane = "com.apple.Localization-Settings.extension"

    /// 展示结果面板：装配 SwiftUI 结果视图、绑定按键回调并按光标位置摆放。
    func present(
        _ state: QuickActionPanelState,
        settings: AppSettings,
        metrics: InterfaceMetrics,
        languages: [Locale.Language],
        onRetranslate: @escaping (Locale.Language) -> Void,
        onReplace: @escaping (String) -> Void
    ) {
        dismiss()
        self.state = state
        self.settings = settings
        self.onReplace = onReplace
        self.onRetranslate = onRetranslate

        let hosting = NSHostingView(
            rootView: QuickActionResultView(
                state: state,
                languages: languages,
                onReplace: { [weak self] in self?.replace(state.output) },
                onCopy: { [weak self] in self?.copyOutput() },
                onCancel: { [weak self] in self?.dismiss() },
                onRetranslate: { [weak self] in self?.onRetranslate?($0) },
                onOpenLanguageSettings: { [weak self] in self?.openLanguageSettings() },
                onHeight: { [weak self] in self?.resize(toHeight: $0) }
            ).environment(\.metrics, metrics).environment(settings))
        // 由控制器掌控窗口框架；否则回复变长时面板顶边会漂移。
        hosting.sizingOptions = []
        // 取其最高值，避免首帧高度不足；视图会立即上报真实高度。
        hosting.setFrameSize(
            NSSize(width: metrics.size.quickActionPanel, height: metrics.size.quickActionPanelBody))

        let panel = QuickActionPanel(content: hosting)
        panel.delegate = self
        panel.onKey = { [weak self] key in
            guard let self, let state = self.state else { return }
            switch key {
            case .replace: if state.canReplace { self.replace(state.output) }
            case .copy: if state.canCopy { self.copyOutput() }
            case .cancel: self.dismiss()
            }
        }
        self.panel = panel
        placeAtCursor(panel)
        // 与调色板一样不激活应用：获得键盘焦点又不把用户从其应用里拽出来。
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    /// 关闭并释放当前面板，清空回调与状态。
    func dismiss() {
        guard let closing = panel else { return }
        panel = nil
        state = nil
        settings = nil
        onReplace = nil
        onRetranslate = nil
        closing.delegate = nil
        closing.onKey = nil
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    /// 将当前结果复制到剪贴板：判定结果序列化为文本，其余为输出本身。
    private func copyOutput() {
        guard let state else { return }
        Paster.copyPlainText(state.copyText(language: settings?.language ?? .english))
    }

    /// 关闭面板并打开系统的语言与地区设置面板。
    private func openLanguageSettings() {
        dismiss()
        AppLauncher.openSettingsPane(bundleID: Self.languageSettingsPane)
    }

    /// 关闭面板后回调替换，将结果写回目标选区。
    private func replace(_ text: String) {
        let callback = onReplace
        dismiss()
        callback?(text)
    }

    /// 以当前左上角为锚点向下生长，因此拖动后到达的回复不会把面板弹回原处。
    private func resize(toHeight height: CGFloat) {
        guard let panel, height > 0, abs(height - panel.frame.height) > 0.5 else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let width = panel.frame.width
        panel.setFrame(
            NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height),
            display: true)
        clampOnScreen(panel)
    }

    /// 以鼠标位置为基准摆放面板，并确保其停留在屏幕可见区域内。
    private func placeAtCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: mouse.x + Self.cursorOffset,
                y: mouse.y - Self.cursorOffset - size.height))
        clampOnScreen(panel)
    }

    /// 将面板约束在当前屏幕的可见范围内，避免超出边界。
    private func clampOnScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = panel.frame
        let x = min(
            max(frame.minX, visible.minX + Self.screenMargin),
            max(visible.maxX - frame.width - Self.screenMargin, visible.minX + Self.screenMargin))
        let y = min(
            max(frame.minY, visible.minY + Self.screenMargin),
            max(visible.maxY - frame.height - Self.screenMargin, visible.minY + Self.screenMargin))
        guard x != frame.minX || y != frame.minY else { return }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    /// 面板失去键盘焦点时自动关闭。
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        dismiss()
    }
}
