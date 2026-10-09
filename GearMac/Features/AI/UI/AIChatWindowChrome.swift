// 文件职责：AI 聊天窗口的工具栏、标题与键盘快捷键（⌘K 动作菜单、查找、新建会话等），其生命周期与窗口完全一致。
// 分层：UI（AppKit/NSWindow 层）；依赖 AIChatCoordinator 与 AIChatSurfacesState 编排动作，仅弱引用窗口，不直接读写持久化状态。
import AppKit

/// AI 聊天窗口的工具栏、标题与快捷键；它与窗口同生共死（窗口存续期间一直存在）。
@MainActor
final class AIChatWindowChrome: NSObject, WindowChrome, NSToolbarDelegate, NSSearchFieldDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("AIChatWindow")
    private static let sidebar = NSToolbarItem.Identifier("AIChatToggleSidebar")
    private static let newChat = NSToolbarItem.Identifier("AIChatNewChat")
    private static let search = NSToolbarItem.Identifier("AIChatSearch")
    private static let actions = NSToolbarItem.Identifier("AIChatActions")

    private let coordinator: AIChatCoordinator
    private let chats: AIChatSurfacesState
    private let find: ChatFindState
    private weak var window: NSWindow?
    private var keyMonitor: Any?
    private let searchItem: NSSearchToolbarItem
    private let actionsButton: NSButton

    private var chat: AIChatState { chats.window }

    init(coordinator: AIChatCoordinator, chats: AIChatSurfacesState, find: ChatFindState) {
        self.coordinator = coordinator
        self.chats = chats
        self.find = find
        searchItem = NSSearchToolbarItem(itemIdentifier: Self.search)
        actionsButton = NSButton(
            image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Actions")
                ?? NSImage(),
            target: nil, action: nil)
        super.init()
        searchItem.searchField.placeholderString = "Find in Chat"
        searchItem.searchField.delegate = self
        searchItem.toolTip = "Find in Chat  ⌘F"
        searchItem.resignsFirstResponderWithCancel = true
        actionsButton.bezelStyle = .toolbar
        actionsButton.toolTip = "Actions  ⌘K"
        actionsButton.target = self
        actionsButton.action = #selector(showActions)
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - WindowChrome

    /// 把工具栏、标题样式与快捷键监视器安装到给定窗口中。
    func install(in window: NSWindow) {
        self.window = window
        window.identifier = Self.windowIdentifier
        // 与设置窗口一致，标题内联且靠左，使标题读起来就是当前打开会话的名字。
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // 保留系统自带的工具栏条带，如同所有文档窗口：内容在其下方滚动。
        window.titlebarAppearsTransparent = false
        // 在对话记录上拖拽应当选中文本，绝不能因此移动窗口。
        window.isMovableByWindowBackground = false

        let toolbar = NSToolbar(identifier: "AIChatToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar

        installKeyMonitor()
        observeTitle()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace, Self.sidebar, .space, Self.newChat, .sidebarTrackingSeparator,
            .flexibleSpace, Self.search, Self.actions
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.sidebar:
            return button(
                identifier, symbol: "sidebar.left", label: "Sidebar", toolTip: "Show or Hide Sidebar",
                action: #selector(toggleSidebar))
        case Self.newChat:
            return button(
                identifier, symbol: "square.and.pencil", label: "New Chat", toolTip: "New Chat  ⌘N",
                action: #selector(newChatAction))
        case Self.search:
            return searchItem
        case Self.actions:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = actionsButton
            item.label = "Actions"
            return item
        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, symbol: String, label: String, toolTip: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.label = label
        item.toolTip = toolTip
        item.target = self
        item.action = action
        return item
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        find.query = searchItem.searchField.stringValue
    }

    /// 回车逐个跳到下一个匹配，⇧↩ 回到上一个，与 Mac 上所有应用的“查找”行为一致。
    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        find.step(backwards ? -1 : 1, in: chat.session.messages)
        return true
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        find.query = ""
    }

    // MARK: - Actions

    @objc private func newChatAction() { coordinator.newChat() }

    @objc private func toggleSidebar() {
        (window?.contentViewController as? NSSplitViewController)?.toggleSidebar(nil)
    }

    @objc private func showActions() {
        let menu = AIChatActionsMenu.build(
            chat: chat, coordinator: coordinator,
            findInChat: { [weak self] in self?.searchItem.beginSearchInteraction() })
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: actionsButton.bounds.maxY + Theme.Spacing.xs),
            in: actionsButton)
    }

    // MARK: - Private

    /// 每次读取后重新注册观察；多跳一次是因为 `onChange` 会在写入生效之前就触发。
    private func observeTitle() {
        withObservationTracking {
            window?.title = coordinator.title(of: chat)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// Actions 菜单的快捷键在菜单关闭时也要生效，因此窗口需要抢在 AppKit 之前拦截这些按键。
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                !event.isARepeat
            else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?
            .lowercased()
        switch (modifiers, key) {
        case ([.command], "f"):
            searchItem.beginSearchInteraction()
        case ([.command], "g"), ([.command, .shift], "g"):
            find.step(modifiers.contains(.shift) ? -1 : 1, in: chat.session.messages)
        case ([.command], "k"):
            showActions()
        case ([.command], "n"):
            coordinator.newChat()
        case ([.command], "r") where AIChatActionsMenu.canRegenerate(chat):
            coordinator.regenerate(in: chat)
        case ([.command, .shift], "c") where chat.lastAssistantText != nil:
            coordinator.copyLastResponse(in: chat)
        case ([.command], ".") where chat.isStreaming:
            coordinator.stopResponse(in: chat)
        case ([.command, .option], ","):
            coordinator.showSettings()
        case ([.command], "v"):
            // 搜索框与重命名框应把粘贴一律当作文本处理，无论剪贴板里放的是什么。
            guard (window.firstResponder as? NSTextView)?.isFieldEditor != true else { return false }
            return coordinator.attachPastedFile(
                files: PasteboardFiles.urls(on: .general), to: chat)
        default:
            return false
        }
        return true
    }
}

/// 窗口的 ⌘K 菜单：包含 Quick AI 的动作，以及只有窗口里已保存的会话才能执行的操作。
@MainActor
enum AIChatActionsMenu {
    static func canRegenerate(_ chat: AIChatState) -> Bool {
        !chat.isStreaming && chat.session.messages.last?.role == .assistant
    }

    static func build(
        chat: AIChatState, coordinator: AIChatCoordinator, findInChat: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        let saved = coordinator.isSaved(chat)
        if chat.isStreaming {
            menu.addItem(
                ClosureMenuItem("Stop Response", symbol: "stop.fill", key: ".") {
                    coordinator.stopResponse(in: chat)
                })
        }
        menu.addItem(
            ClosureMenuItem("New Chat", symbol: "square.and.pencil", key: "n") {
                coordinator.newChat()
            })
        if canRegenerate(chat) {
            menu.addItem(
                ClosureMenuItem("Regenerate Response", symbol: "arrow.clockwise", key: "r") {
                    coordinator.regenerate(in: chat)
                })
        }
        menu.addItem(.separator())
        if chat.lastAssistantText != nil {
            menu.addItem(
                ClosureMenuItem(
                    "Copy Last Response", symbol: "doc.on.doc", key: "c", modifiers: [.command, .shift]
                ) {
                    coordinator.copyLastResponse(in: chat)
                })
        }
        if saved {
            menu.addItem(
                ClosureMenuItem("Copy Chat", symbol: "text.bubble") {
                    coordinator.copyChat(id: chat.session.id)
                })
        }
        if !chat.pendingAttachments.isEmpty {
            menu.addItem(
                ClosureMenuItem("Remove Attachments", symbol: "paperclip") {
                    coordinator.clearAttachments(in: chat)
                })
        }
        if saved {
            menu.addItem(.separator())
            let pinned = coordinator.isPinned(chat)
            menu.addItem(
                ClosureMenuItem(pinned ? "Unpin Chat" : "Pin Chat", symbol: "pin") {
                    coordinator.togglePin(id: chat.session.id)
                })
            menu.addItem(
                ClosureMenuItem("Delete Chat…", symbol: "trash") {
                    Task { await coordinator.deleteChat(id: chat.session.id) }
                })
        }
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem("Find in Chat", symbol: "magnifyingglass", key: "f", findInChat))
        menu.addItem(
            ClosureMenuItem(
                "AI Settings", symbol: "slider.horizontal.3", key: ",", modifiers: [.command, .option]
            ) {
                coordinator.showSettings()
            })
        return menu
    }
}

/// 一个执行闭包的 `NSMenuItem`，因此每次打开时临时构建的菜单无需为每行单独定义 selector。
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(
        _ title: String, symbol: String, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, _ run: @escaping () -> Void
    ) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func runAction() { run() }
}
