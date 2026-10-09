// 文件职责：对话框编排器，以 async/await 暴露确认、选择、提示、失败上报及各类专用输入弹窗。
// 分层：Coordinator/UI；@MainActor，串行呈现模态面板，同一时刻只允许一个 continuation 存活。
import AppKit
import SwiftUI

/// GearMac 自有的对话框；`NSAlert` 的嵌套 run loop 会让快捷键叠加出多个弹窗。
@MainActor
final class DialogController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let onPresentationChanged: (Bool) -> Void
    private var panel: DialogPanel?
    private var continuation: CheckedContinuation<Int, Never>?

    init(settings: AppSettings, onPresentationChanged: @escaping (Bool) -> Void) {
        self.settings = settings
        self.onPresentationChanged = onPresentationChanged
    }

    /// 二选一确认框；用户点中确认按钮时返回 true。
    func confirm(
        title: String, message: String?, symbol: String?, tone: DialogTone, confirmTitle: String,
        confirmRole: DialogAction.Role, dismissTitle: String = "Cancel"
    ) async -> Bool {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [
                DialogAction(title: confirmTitle, role: confirmRole),
                DialogAction(title: dismissTitle, role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1)
        return await present(request) == 0
    }

    /// 超过两个选项时使用；`options` 按分发顺序排列，最后一项为取消。
    func choose(
        title: String, message: String?, symbol: String?, tone: DialogTone,
        options: [DialogAction], defaultIndex: Int
    ) async -> Int {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone, actions: options,
            defaultIndex: defaultIndex, cancelIndex: options.count - 1)
        return await present(request)
    }

    /// 只有一个“OK”的信息提示框，不返回选择结果。
    func notice(title: String, message: String, symbol: String, tone: DialogTone) async {
        let cancel = DialogAction(title: settings.text(WindowsKey.dialogOK), role: .cancel)
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [cancel], defaultIndex: 0, cancelIndex: 0)
        _ = await present(request)
    }

    /// 与 `confirm` 不同，用于已经出错的场景；若用户选择了恢复操作则返回 true。
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        var actions = [DialogAction(title: settings.text(WindowsKey.dialogOK), role: .cancel)]
        if let recovery { actions.append(DialogAction(title: recovery)) }
        // 存在恢复操作时 ↵ 落在恢复操作上，而不是落在仅作关闭的 OK 上。
        let recoveryIndex = recovery == nil ? nil : actions.count - 1
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: .danger,
            actions: actions, defaultIndex: recoveryIndex ?? 0, cancelIndex: 0)
        return await present(request) == recoveryIndex
    }

    /// 弹出音量选择对话框；取消时返回 nil。
    func pickVolume(current: Float32) async -> Float32? {
        let volume = VolumeState(level: Double(current))
        let request = DialogRequest(
            title: settings.text(WindowsKey.dialogVolumeTitle),
            message: settings.text(WindowsKey.dialogVolumeMessage), symbol: "speaker.wave.2",
            tone: .neutral,
            actions: [
                DialogAction(title: settings.text(WindowsKey.dialogVolumeTitle)),
                DialogAction(title: settings.text(WindowsKey.dialogCancel), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .volume(volume))
        guard await present(request) == 0 else { return nil }
        return Float32(volume.level)
    }

    /// 新建日程草稿对话框；取消或草稿无效时返回 nil。
    func createEvent() async -> EventDraft? {
        let state = EventDraftState()
        let request = DialogRequest(
            title: settings.text(WindowsKey.dialogEventTitle),
            message: settings.text(WindowsKey.dialogEventMessage),
            symbol: "calendar.badge.plus", tone: .neutral,
            actions: [
                DialogAction(title: settings.text(WindowsKey.dialogEventConfirm)),
                DialogAction(title: settings.text(WindowsKey.dialogCancel), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .eventDraft(state))
        guard await present(request) == 0, state.draft.isValid else { return nil }
        return state.draft
    }

    /// 为片段模板补齐缺失参数；取消时返回 nil。
    func fillSnippetArguments(
        snippetName: String, arguments: [SnippetTemplateEngine.MissingArgument]
    ) async -> [String: String]? {
        let state = SnippetArgumentsState(arguments: arguments)
        let request = DialogRequest(
            title: snippetName, message: settings.text(WindowsKey.dialogSnippetMessage),
            symbol: "curlybraces",
            tone: .neutral,
            actions: [
                DialogAction(title: settings.text(WindowsKey.dialogSnippetConfirm)),
                DialogAction(title: settings.text(WindowsKey.dialogCancel), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .snippetArguments(state))
        guard await present(request) == 0 else { return nil }
        return state.values
    }

    /// 在面板中串行呈现一个请求，返回用户选择的按钮索引。
    private func present(_ request: DialogRequest) async -> Int {
        // 以 continuation 为占用标记，避免仍在淡出的面板吞掉下一次呈现。
        guard continuation == nil else { return request.cancelIndex }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            onPresentationChanged(true)
            let width =
                switch request.accessory {
                case nil, .volume: metrics.size.dialogCompactWidth
                case .eventDraft, .snippetArguments: metrics.size.dialogWidth
                }
            let content = hostingView(
                DialogView(
                    request: request, width: width,
                    onChoose: { [weak self] index in
                        guard Self.accepts(index, for: request) else { return }
                        self?.finish(index)
                    }),
                width: width, minHeight: 0)
            let panel = DialogPanel(content: content, cornerRadius: metrics.radius.panel)
            panel.handlesArrowKeys = request.accessory?.claimsArrowKeys ?? false
            panel.delegate = self
            panel.onKey = { [weak self] key in
                guard let self else { return }
                switch key {
                case .cancel:
                    finish(request.cancelIndex)
                case .confirm:
                    guard Self.accepts(request.defaultIndex, for: request) else { return }
                    finish(request.defaultIndex)
                case .increment, .decrement:
                    // 用按键操作滑块会落在与“音量加/减”相同的取值上。
                    guard case .volume(let volume) = request.accessory else { return }
                    volume.level = VolumeLevel.stepped(volume.level, up: key == .increment)
                }
            }
            self.panel = panel
            place(panel)
            show(panel)
        }
    }

    /// 移动全尺寸的玻璃面板，避免缩放内容导致的瞬时描边。
    private func show(_ panel: NSPanel) {
        let destination = panel.frame
        panel.alphaValue = Theme.DialogMotion.initialOpacity
        panel.setFrameOrigin(
            NSPoint(x: destination.minX, y: destination.minY - Theme.DialogMotion.offset))
        // 与命令面板一样不激活应用：取得键盘焦点但不把用户切出当前应用。
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Duration.dialogEnter
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // 移动已缓存的表面，避免在每个整点帧步进处重绘玻璃效果。
            panel.animator().setFrame(destination, display: false)
            panel.animator().alphaValue = 1
        }
    }

    /// 主操作被拒绍时保持对话框打开，效果等同于按钮置灰。
    private static func accepts(_ index: Int, for request: DialogRequest) -> Bool {
        guard index == request.defaultIndex, case .eventDraft(let state) = request.accessory else {
            return true
        }
        return state.draft.isValid
    }

    /// 在淡出结束前就恢复调用方，避免动画拖慢确认流程。
    private func finish(_ index: Int) {
        guard let continuation else { return }
        self.continuation = nil
        onPresentationChanged(false)
        let closing = panel
        panel = nil
        closing?.delegate = nil
        closing?.onKey = nil
        continuation.resume(returning: index)
        closing?.fadeOut(duration: Theme.Duration.dialogExit)
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }

    /// 以指定宽度与最小高度包装 SwiftUI 视图，并按适配尺寸测量高度。
    private func hostingView(_ view: some View, width: CGFloat, minHeight: CGFloat) -> NSView {
        let hosting = NSHostingView(
            rootView: AnyView(
                view.environment(\.metrics, metrics).environment(settings)))
        // 先在固定宽度下测量：消息会换行，因此高度由宽度决定。
        hosting.setFrameSize(NSSize(width: width, height: minHeight))
        let fitted = hosting.fittingSize
        hosting.setFrameSize(NSSize(width: width, height: max(fitted.height, minHeight)))
        return hosting
    }

    /// 将面板居中放置于鼠标所在屏幕，并略微上移做视觉居中。
    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    /// 视觉居中：完全按几何居中时对话框看起来偏低，命令面板同理。
    private static let centerLift: CGFloat = 0.08
    // MARK: - NSWindowDelegate

    /// 在 AppKit 自身选定 first responder 之后执行，视图的聚焦请求无法比这更早生效。
    func windowDidBecomeKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        panel.focusFirstTextField()
    }

    /// 点击其他位置按取消处理，避免留下无人管理的对话框。
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        panel.onKey?(.cancel)
    }
}
