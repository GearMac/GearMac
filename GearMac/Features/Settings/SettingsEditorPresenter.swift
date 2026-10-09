// 文件职责：在 AppKit 子面板中展示设置界面里的各类编辑器/选择面板，并维护每个窗口的展示栈。
// 分层：UI 支撑（AppKit + SwiftUI）；展示状态由各处的 binding 持有，本类型只接管 AppKit 边界。
import AppKit
import SwiftUI

/// 每个设置窗口一份栈：展示状态由各处 binding 持有，本类型只负责 AppKit 边界。
@MainActor
final class SettingsEditorPresenter: NSObject {
    /// 用于关闭当前编辑器面板的动作，可在被展示的内容中直接调用。
    struct DismissAction {
        private let action: () -> Void

        init(_ action: @escaping () -> Void = {}) {
            self.action = action
        }

        func callAsFunction() {
            action()
        }
    }

    /// 由 Bool 绑定驱动的 `.settingsEditorPanel(isPresented:)` 修饰器。
    fileprivate struct BooleanPanelModifier<PanelContent: View>: ViewModifier {
        @Environment(\.settingsEditorPresenter) private var presenter
        @Binding var isPresented: Bool
        let panelContent: () -> PanelContent
        @State private var presentationID = UUID()

        func body(content: Content) -> some View {
            content
                .onChange(of: isPresented, initial: true) { _, presented in
                    guard let presenter else { return }
                    if presented {
                        let binding = $isPresented
                        presenter.present(
                            id: presentationID,
                            onDismiss: {
                                binding.wrappedValue = false
                            }
                        ) {
                            panelContent()
                        }
                    } else {
                        presenter.dismiss(id: presentationID, notifying: false)
                    }
                }
                .onDisappear {
                    presenter?.dismiss(id: presentationID)
                }
        }
    }

    /// 由可选 item 绑定驱动的 `.settingsEditorPanel(item:)` 修饰器。
    fileprivate struct ItemPanelModifier<Item: Identifiable, PanelContent: View>: ViewModifier {
        @Environment(\.settingsEditorPresenter) private var presenter
        @Binding var item: Item?
        let panelContent: (Item) -> PanelContent
        @State private var presentationID = UUID()

        func body(content: Content) -> some View {
            content
                .onChange(of: item?.id, initial: true) { _, _ in
                    guard let presenter else { return }
                    presenter.dismiss(id: presentationID, notifying: false)
                    guard let presentedItem = item else { return }
                    let binding = $item
                    let itemID = presentedItem.id
                    presenter.present(
                        id: presentationID,
                        onDismiss: {
                            guard binding.wrappedValue?.id == itemID else { return }
                            binding.wrappedValue = nil
                        }
                    ) {
                        panelContent(presentedItem)
                    }
                }
                .onDisappear {
                    presenter?.dismiss(id: presentationID)
                }
        }
    }

    /// 尚未挂到父窗口上的待展示请求。
    private struct Pending {
        let id: UUID
        let content: AnyView
        let onDismiss: () -> Void
    }

    /// 一次已挂载的面板展示，记录涉及的面板、变暗层与关闭回调。
    private final class Presentation {
        let id: UUID
        weak var parent: NSWindow?
        let panel: Panel
        let blocker: BlockingPanel
        let onDismiss: () -> Void

        init(
            id: UUID, parent: NSWindow, panel: Panel,
            blocker: BlockingPanel, onDismiss: @escaping () -> Void
        ) {
            self.id = id
            self.parent = parent
            self.panel = panel
            self.blocker = blocker
            self.onDismiss = onDismiss
        }
    }

    /// 承载编辑器内容的无边框浮动面板。
    private final class Panel: NSPanel {
        var cancelHandler: (() -> Void)?

        init(content: NSView, cornerRadius: CGFloat) {
            super.init(
                contentRect: NSRect(origin: .zero, size: content.frame.size),
                styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
            isFloatingPanel = true
            becomesKeyOnlyIfNeeded = false
            hidesOnDeactivate = false
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            animationBehavior = .none
            isMovableByWindowBackground = false
            isReleasedWhenClosed = false
            content.wantsLayer = true
            content.layer?.cornerCurve = .continuous
            content.layer?.cornerRadius = cornerRadius
            content.layer?.masksToBounds = true
            contentView = content
        }

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        /// 子窗口单独拖动会无效，因此把拖动交给它所依附的窗口，行为与 sheet 一致。
        override func performDrag(with event: NSEvent) {
            parent?.performDrag(with: event)
        }

        /// 兜底路径：内容自身声明 `.cancelAction` 的面板会自行处理 Escape。
        override func cancelOperation(_ sender: Any?) {
            cancelHandler?()
        }

        /// 播放位移动画与淡入，完成面板入场。
        func animateEntrance(offset: CGFloat, startingOpacity: CGFloat, duration: TimeInterval) {
            guard let layer = contentView?.layer else { return }

            let movement = CABasicAnimation(keyPath: "transform.translation.y")
            movement.fromValue = -offset
            movement.toValue = 0
            movement.duration = duration

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = startingOpacity
            opacity.toValue = 1
            opacity.duration = duration

            let entrance = CAAnimationGroup()
            entrance.animations = [movement, opacity]
            entrance.duration = duration
            entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)

            layer.add(entrance, forKey: "settingsEditorEntrance")
            alphaValue = 1
        }

        /// 取得焦点，并把键盘焦点交给首个控件。
        func focusFirstControl() {
            makeKey()
            selectNextKeyView(nil)
        }
    }

    /// 铺在父窗口上的变暗/拦截层，吞掉点击以避免误操作。
    private final class BlockingPanel: NSPanel {
        private weak var target: NSWindow?

        init(target: NSWindow, cornerRadius: CGFloat) {
            self.target = target
            super.init(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            animationBehavior = .none
            isReleasedWhenClosed = false
            alphaValue = 0
            contentView = NSHostingView(
                rootView: Theme.Colors.dialogDimming
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .ignoresSafeArea())
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        override func sendEvent(_ event: NSEvent) {
            guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
                super.sendEvent(event)
                return
            }
            target?.makeKeyAndOrderFront(nil)
            // 变暗层覆盖了父窗口的标题栏，因此它必须承担父窗口的拖动。
            if event.type == .leftMouseDown { parent?.performDrag(with: event) }
        }
    }

    private unowned let core: AppCore
    private let navigation: SettingsNavigationState
    private weak var parentWindow: NSWindow?
    private var pending: [Pending] = []
    private var presentations: [Presentation] = []

    /// 绑定共享的 `AppCore` 与所属窗口的导航会话。
    init(core: AppCore, navigation: SettingsNavigationState) {
        self.core = core
        self.navigation = navigation
        super.init()
    }

    /// 绑定宿主窗口，并在其关闭或尺寸变化时同步清理与重新布局。
    func attach(to window: NSWindow?) {
        guard let window, parentWindow !== window else { return }
        if let parentWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: parentWindow)
        }
        parentWindow = window
        NotificationCenter.default.addObserver(
            self, selector: #selector(parentWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window)
        observeResize(of: window)
        flushPending()
    }

    /// 父窗口关闭时关闭所有面板并解除通知监听。
    @objc private func parentWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === parentWindow else { return }
        dismissAll()
        NotificationCenter.default.removeObserver(self, name: nil, object: parentWindow)
        parentWindow = nil
    }

    /// 请求展示一个面板；父窗口尚未就绪时先入队，稍后统一挂上。
    func present<Content: View>(
        id: UUID, onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        guard !contains(id) else { return }
        pending.append(Pending(id: id, content: AnyView(content()), onDismiss: onDismiss))
        flushPending()
    }

    /// 关闭指定面板；关闭它上层的嵌套面板时会触发这些面板的回调。
    func dismiss(id: UUID, notifying: Bool = true) {
        if let pendingIndex = pending.firstIndex(where: { $0.id == id }) {
            let request = pending.remove(at: pendingIndex)
            if notifying { request.onDismiss() }
            return
        }
        guard let index = presentations.firstIndex(where: { $0.id == id }) else { return }
        while presentations.indices.contains(index) {
            let shouldNotify = presentations.last?.id == id ? notifying : true
            dismissLast(notifying: shouldNotify)
        }
    }

    /// 关闭全部待展示与已展示的面板，并触发各自回调。
    func dismissAll() {
        let pendingRequests = pending
        pending.removeAll()
        pendingRequests.forEach { $0.onDismiss() }
        while !presentations.isEmpty { dismissLast(notifying: true) }
    }

    /// 该 id 是否已在待展示队列或已展示列表中。
    private func contains(_ id: UUID) -> Bool {
        pending.contains { $0.id == id } || presentations.contains { $0.id == id }
    }

    /// 父窗口就绪后，按顺序把待展示请求全部挂上。
    private func flushPending() {
        guard parentWindow != nil else { return }
        while !pending.isEmpty { show(pending.removeFirst()) }
    }

    /// 创建面板与变暗层、挂到父窗口上，并完成入场动画。
    private func show(_ request: Pending) {
        guard let parent = presentations.last?.panel ?? parentWindow else { return }
        let dismiss = DismissAction { [weak self] in
            self?.dismiss(id: request.id)
        }
        let root = request.content
            .settingsEnvironment(core: core, navigation: navigation, editorPresenter: self)
            .environment(\.settingsEditorDismiss, dismiss)
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.setFrameSize(NSSize(width: 1, height: 1))
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        hosting.setFrameSize(
            NSSize(width: max(1, fitting.width), height: max(1, fitting.height)))

        let panel = Panel(content: hosting, cornerRadius: Theme.Radius.panel)
        panel.cancelHandler = { [weak self] in self?.dismiss(id: request.id) }
        let blocker = BlockingPanel(
            target: panel, cornerRadius: blockerCornerRadius(for: parent))
        let presentation = Presentation(
            id: request.id, parent: parent, panel: panel, blocker: blocker,
            onDismiss: request.onDismiss)
        presentations.append(presentation)
        // 面板自身也要监听尺寸变化：内容决定面板大小，因此表单变高时必须重新居中。
        observeResize(of: panel)
        layout(presentation)
        panel.alphaValue = 0
        parent.addChildWindow(blocker, ordered: .above)
        parent.addChildWindow(panel, ordered: .above)
        blocker.fadeIn(duration: Theme.Duration.dialogEnter) { blocker.orderFront(nil) }
        panel.makeKeyAndOrderFront(nil)
        prepareEntrance(panel: panel)
    }

    /// 等布局稳定后聚焦首个控件，再播放入场动画。
    private func prepareEntrance(panel: Panel) {
        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel,
                self.presentations.contains(where: { $0.panel === panel })
            else { return }
            panel.focusFirstControl()
            await Task.yield()
            guard self.presentations.contains(where: { $0.panel === panel }) else { return }
            animateEntrance(panel: panel)
        }
    }

    private func animateEntrance(panel: Panel) {
        panel.animateEntrance(
            offset: Theme.DialogMotion.offset,
            startingOpacity: Theme.DialogMotion.initialOpacity,
            duration: Theme.Duration.dialogEnter)
        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(Theme.Duration.dialogEnter))
            guard let self, let panel,
                self.presentations.contains(where: { $0.panel === panel })
            else { return }
            panel.animationBehavior = .utilityWindow
        }
    }

    /// 监听给定窗口的尺寸变化，以便重新居中面板。
    private func observeResize(of window: NSWindow) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostDidResize(_:)),
            name: NSWindow.didResizeNotification, object: window)
    }

    /// 从最外层开始布局，这样嵌套面板是以已经稳定下来的父窗口为中心居中。
    @objc private func hostDidResize(_ notification: Notification) {
        presentations.forEach(layout)
    }

    /// 把变暗层铺满父窗口，并把面板居中到父窗口的内容区。
    private func layout(_ presentation: Presentation) {
        guard let parent = presentation.parent else { return }
        let parentContent = parent.convertToScreen(parent.contentLayoutRect)
        presentation.blocker.setFrame(parent.frame, display: false)
        let panelSize = presentation.panel.frame.size
        presentation.panel.setFrameOrigin(
            NSPoint(
                x: parentContent.midX - panelSize.width / 2,
                y: parentContent.midY - panelSize.height / 2))
    }

    /// 变暗层的圆角跟随父窗口；父窗口无圆角时回落到行圆角。
    private func blockerCornerRadius(for parent: NSWindow) -> CGFloat {
        let radius = parent.contentView?.layer?.cornerRadius ?? 0
        return radius > 0 ? radius : Theme.Radius.row
    }

    /// 弹出并关闭栈顶面板，把焦点交还给下一层或宿主窗口。
    private func dismissLast(notifying: Bool) {
        let presentation = presentations.removeLast()
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResizeNotification, object: presentation.panel)
        if let parent = presentation.parent {
            parent.removeChildWindow(presentation.panel)
            presentation.blocker.fadeOut(duration: Theme.Duration.dialogExit) {
                parent.removeChildWindow(presentation.blocker)
            }
        }
        presentation.panel.orderOut(nil)
        presentation.panel.contentView = nil
        if notifying { presentation.onDismiss() }
        if let panel = presentations.last?.panel {
            panel.makeKeyAndOrderFront(nil)
            panel.focusFirstControl()
        } else {
            parentWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

extension EnvironmentValues {
    /// 从环境读取的「关闭当前编辑器面板」动作。
    @Entry var settingsEditorDismiss = SettingsEditorPresenter.DismissAction()
    /// 环境中的编辑器展示器；仅在设置窗口的视图树内可用。
    @Entry var settingsEditorPresenter: SettingsEditorPresenter?
}

extension View {
    /// 在 GearMac 的可激活子面板中展示编辑器内容，而不是不透明的 macOS sheet。
    func settingsEditorPanel<PanelContent: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> PanelContent
    ) -> some View {
        modifier(
            SettingsEditorPresenter.BooleanPanelModifier(
                isPresented: isPresented, panelContent: content))
    }

    /// 由 item 驱动的形式，适用于打开面板时即捕获初始状态的编辑器。
    func settingsEditorPanel<Item: Identifiable, PanelContent: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> PanelContent
    ) -> some View {
        modifier(SettingsEditorPresenter.ItemPanelModifier(item: item, panelContent: content))
    }

    /// 一次性把设置界面所需的全部共享对象注入环境。
    func settingsEnvironment(
        core: AppCore, navigation: SettingsNavigationState,
        editorPresenter: SettingsEditorPresenter
    ) -> some View {
        environment(\.settingsEditorPresenter, editorPresenter)
            .environment(navigation)
            .environment(core)
            .environment(core.settings)
            .environment(core.dictationCoordinator)
            .environment(core.appIndex)
            .environment(core.hotKeys)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.fallbacks)
            .environment(core.customCommands)
            .environment(core.snippetsStore)
            .environment(core.quicklinks)
            .environment(core.windowLayouts)
            .environment(core.rooms)
            .environment(core.roomCoordinator)
            .environment(core.customWindowSizes)
            .environment(core.customWindowSizeCoordinator)
            .environment(core.calendarStore)
            .environment(core.aiSettings)
            .environment(core.mcpSettings)
            .environment(core.mcpCoordinator)
            .environment(core.quickActionSettings)
            .environment(core.customQuickActions)
            .environment(core.chatGPTSubscription)
            .environment(core.installedAI)
            .scrollContentBackground(.hidden)
    }
}
