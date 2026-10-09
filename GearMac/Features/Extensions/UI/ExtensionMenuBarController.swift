// 文件职责：管理单个菜单栏额外项（`NSStatusItem`）的状态项、图标与 `NSMenu`，并把 React 提交的菜单树协调（reconcile）为原生菜单。
// 分层：UI；菜单栏图像异步加载，菜单打开期间不接受快照更新（延后到关闭后再套用）。
import AppKit

/// 管理单个菜单栏额外项的状态项、图标与菜单，并把快照渲染为原生菜单。
@MainActor
final class ExtensionMenuBarController: NSObject, NSMenuDelegate {
    let entryID: String
    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((String, String, String) -> Void)?
    var onActionUnavailable: (() -> Void)?
    private let status: NSStatusItem
    let menu = NSMenu()
    private let assetsPath: String
    private let loadImage: (RenderValue?, String, CGFloat) async -> NSImage?
    private var snapshot: ExtensionMenuBarSnapshot?
    private var iconTask: Task<Void, Never>?
    private var menuImageTask: Task<Void, Never>?
    private var deferredSnapshot: ExtensionMenuBarSnapshot?
    private var hasPreparedContent = false
    /// 以图标为键而非线性查找：菜单会在每次 React 提交时重绘所有行。
    private var images: [RenderValue: NSImage] = [:]
    private var imageBindings: [(item: NSMenuItem, value: RenderValue)] = []
    private var failedIcons: Set<RenderValue> = []
    private let placeholder = NSImage(size: NSSize(width: 14, height: 14))
    private var iconFailed = false
    private var menuSession: String?
    private var pendingActions: [(identity: ItemIdentity, type: String)] = []
    private var identities: [ObjectIdentifier: ItemIdentity] = [:]

    /// 菜单项绑定的动作：所属会话与处理器名。
    private struct Action: Equatable {
        let session: String
        let handler: String
    }

    /// 菜单项的稳定标识，用于在菜单重绘后重新定位同一项。
    private struct ItemIdentity: Equatable {
        let path: [PathComponent]
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let isAlternate: Bool
    }

    /// 菜单树中的路径片段，用于区分不同层级下的同名项。
    private enum PathComponent: Equatable {
        case item(String), section(String), submenu(String)
        case primary(String, String)
    }

    /// 创建状态项并配置 autosave 名称、可见性与菜单。
    init(
        entryID: String, assetsPath: String, isVisible: Bool = true,
        loadImage: @escaping (RenderValue?, String, CGFloat) async -> NSImage? = {
            await ExtensionMenuBarImage.loadAdaptive($0, assetsPath: $1, size: $2)
        }
    ) {
        self.entryID = entryID
        self.assetsPath = assetsPath
        self.loadImage = loadImage
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.autosaveName = entryID
        status.isVisible = isVisible
        status.button?.imagePosition = .imageLeading
        menu.autoenablesItems = false
        menu.delegate = self
        // 追踪由 AppKit 负责，这也是点击其他状态项时能被交给它处理的原因。
        status.menu = menu
    }

    /// 套用新快照：仅在字段变化时更新状态项，菜单打开时延后到关闭后再套用。
    func update(_ snapshot: ExtensionMenuBarSnapshot) {
        if isOpen { deferredSnapshot = snapshot; return }
        guard self.snapshot != snapshot else { return }
        let previous = self.snapshot
        self.snapshot = snapshot
        if previous?.title != snapshot.title { status.button?.title = snapshot.title ?? "" }
        if previous?.tooltip != snapshot.tooltip { status.button?.toolTip = snapshot.tooltip }
        status.button?.setAccessibilityLabel(snapshot.tooltip ?? snapshot.title ?? "Extension menu")
        // 没有行可显示的菜单栏额外项无可展开，因此直接脱挂菜单而非展示空菜单。
        if previous?.hasMenu != snapshot.hasMenu { status.menu = snapshot.hasMenu ? menu : nil }
        let iconChanged = previous?.iconJSON != snapshot.iconJSON || previous == nil
        if iconChanged { loadIcon() }
    }

    /// 异步加载菜单栏图标；失败时回退到 SF Symbol 或隐藏图标。
    private func loadIcon() {
        iconTask?.cancel()
        guard let snapshot else { return }
        let assetsPath = self.assetsPath
        let loadImage = self.loadImage
        iconTask = Task { [weak self] in
            let image = await loadImage(snapshot.icon, assetsPath, 18)
            guard !Task.isCancelled, let self else { return }
            self.iconTask = nil
            self.iconFailed = snapshot.icon != nil && image == nil
            self.status.button?.image =
                image
                ?? ((snapshot.title ?? "").isEmpty
                    ? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil) : nil)
        }
    }

    /// 用新的菜单树渲染菜单；会话切换时清空旧动作与图标缓存。
    func showMenu(_ root: RenderNode, session: String) {
        if menuSession != session {
            clearActions(in: menu)
            menuSession = session
            menuImageTask?.cancel()
            menuImageTask = nil
            failedIcons.removeAll()
            if iconFailed, iconTask == nil { loadIcon() }
        }
        if root.bool("isLoading") != true || !hasPreparedContent { apply(root.children, session: session) }
        if root.bool("isLoading") != true { dispatchPendingActions() }
        loadMenuImages()
    }

    /// 下一个尚未加载或已加载失败的图标值。
    private var nextIcon: RenderValue? {
        imageBindings.first { !failedIcons.contains($0.value) && images[$0.value] == nil }?.value
    }

    /// 逐个异步加载菜单项图标，并回填到所有引用同一图标的菜单项。
    private func loadMenuImages() {
        guard menuImageTask == nil, nextIcon != nil else { return }
        let assetsPath = self.assetsPath
        let loadImage = self.loadImage
        menuImageTask = Task { [weak self] in
            while let value = self?.nextIcon {
                let image = await loadImage(value, assetsPath, 14)
                guard !Task.isCancelled, let self else { return }
                guard let image else { self.failedIcons.insert(value); continue }
                guard self.imageBindings.contains(where: { $0.value == value }) else { continue }
                self.images[value] = image
                for binding in self.imageBindings where binding.value == value {
                    if binding.item.image !== image { binding.item.image = image }
                }
            }
            self?.menuImageTask = nil
        }
    }

    /// 以给定节点重建菜单内容，并清理不再使用的图标缓存。
    private func apply(_ nodes: [RenderNode], session: String?) {
        if isOpen, menu.size.width > menu.minimumWidth { menu.minimumWidth = menu.size.width }
        imageBindings.removeAll(keepingCapacity: true)
        identities.removeAll(keepingCapacity: true)
        reconcile(nodes, in: menu, session: session, path: [])
        let live = Set(imageBindings.map(\.value))
        images = images.filter { live.contains($0.key) }
        hasPreparedContent = !nodes.isEmpty
    }

    /// 在尚无内容时用一条不可用的提示项展示错误。
    func showError(_ message: String) {
        pendingActions.removeAll()
        status.button?.toolTip = message
        guard !hasPreparedContent else { return }
        menuImageTask?.cancel()
        menuImageTask = nil
        apply(
            [
                RenderNode(
                    id: -1, type: "MenuBarExtra.Item",
                    props: [
                        "title": .string("Could not refresh"), "tooltip": .string(message)
                    ])
            ], session: nil)
    }

    /// 把渲染节点按结构协调为菜单项，复用已有项以避免重绘抖动。
    private func reconcile(_ nodes: [RenderNode], in menu: NSMenu, session: String?, path: [PathComponent]) {
        var entries: [(node: RenderNode, role: String, parent: RenderNode?, path: [PathComponent])] = []
        func flatten(_ nodes: [RenderNode], path: [PathComponent]) {
            for node in nodes {
                switch node.type {
                case "MenuBarExtra.Section":
                    if !entries.isEmpty, entries.last?.role != "separator" {
                        entries.append((node, "separator", nil, path))
                    }
                    if let title = node.string("title"), !title.isEmpty {
                        entries.append((node, "header", nil, path))
                    }
                    flatten(node.children, path: path + [.section(node.string("title") ?? "")])
                case "MenuBarExtra.Separator": entries.append((node, "separator", nil, path))
                case "MenuBarExtra.Item", "MenuBarExtra.Submenu":
                    entries.append((node, "item", nil, path))
                    if let alternate = node.node("alternate") {
                        let primary = PathComponent.primary(
                            node.string("title") ?? "", node.string("subtitle") ?? "")
                        entries.append((alternate, "item", node, path + [primary]))
                    }
                default: break
                }
            }
        }
        flatten(nodes, path: path)
        for (index, entry) in entries.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier("\(entry.node.id)-\(entry.role)")
            let item =
                menu.items.first { $0.identifier == identifier }
                ?? {
                    switch entry.role {
                    case "separator": return NSMenuItem.separator()
                    case "header": return NSMenuItem.sectionHeader(title: entry.node.string("title") ?? "")
                    default: return NSMenuItem(title: "", action: nil, keyEquivalent: "")
                    }
                }()
            if item.identifier != identifier { item.identifier = identifier }
            if entry.role != "separator" {
                update(item, from: entry.node, session: session, parent: entry.parent, path: entry.path)
            }
            if menu.index(of: item) != index {
                if item.menu === menu { menu.removeItem(item) }
                menu.insertItem(item, at: index)
            }
        }
        while menu.numberOfItems > entries.count { menu.removeItem(at: menu.numberOfItems - 1) }
    }

    /// 把一个渲染节点的标题、图标、快捷键、启停与动作写入 `NSMenuItem`。
    private func update(
        _ item: NSMenuItem, from node: RenderNode, session: String?, parent: RenderNode?,
        path: [PathComponent]
    ) {
        let title = node.string("title") ?? ""
        if item.isSectionHeader {
            if item.title != title { item.title = title }
        } else {
            let attributed = NSMutableAttributedString(
                string: title, attributes: [.foregroundColor: NSColor.labelColor])
            if let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                attributed.append(
                    NSAttributedString(
                        string: " " + subtitle,
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            if item.attributedTitle != attributed { item.attributedTitle = attributed }
        }
        if item.toolTip != node.string("tooltip") { item.toolTip = node.string("tooltip") }
        let handler = node.handler("onAction")
        if item.target !== self { item.target = self }
        let selector = handler == nil ? nil : #selector(performAction(_:))
        if item.action != selector { item.action = selector }
        let action = session.flatMap { session in handler.map { Action(session: session, handler: $0) } }
        if item.representedObject as? Action != action { item.representedObject = action }
        let image = node.props["icon"].map { icon in
            imageBindings.append((item, icon))
            return images[icon] ?? placeholder
        }
        if item.image !== image { item.image = image }
        var enabled = handler != nil
        if node.type == "MenuBarExtra.Submenu", !node.children.isEmpty {
            let submenu = item.submenu ?? NSMenu()
            submenu.autoenablesItems = false
            reconcile(node.children, in: submenu, session: session, path: path + [.submenu(item.title)])
            if item.submenu !== submenu { item.submenu = submenu }
            enabled = !submenu.items.isEmpty
        } else if item.submenu != nil {
            item.submenu = nil
        }
        if item.isEnabled != enabled { item.isEnabled = enabled }
        let rawShortcut = (parent ?? node).object("shortcut") ?? [:]
        let shortcut = rawShortcut["macOS"]?.objectValue ?? rawShortcut
        let rawKey = shortcut["key"]?.stringValue ?? ""
        let key = Self.namedKeys[rawKey] ?? rawKey.lowercased()
        if item.keyEquivalent != key { item.keyEquivalent = key }
        var modifiers = (shortcut["modifiers"]?.arrayValue ?? []).reduce(into: NSEvent.ModifierFlags()) {
            flags, value in
            switch value.stringValue {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "alt", "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        if parent != nil {
            modifiers.insert(.option)
        } else if node.node("alternate") != nil {
            modifiers.remove(.option)
        }
        if item.keyEquivalentModifierMask != modifiers { item.keyEquivalentModifierMask = modifiers }
        if item.isAlternate != (parent != nil) { item.isAlternate = parent != nil }
        if handler != nil {
            identities[ObjectIdentifier(item)] = ItemIdentity(
                path: path + [.item(item.title)], key: key,
                modifiers: modifiers, isAlternate: parent != nil)
        }
    }

    /// Raycast 的具名按键；其余则为其字面对应字符。
    private static let namedKeys = [
        "return": "\r", "enter": "\u{3}", "tab": "\t", "space": " ", "escape": "\u{1b}",
        "backspace": "\u{8}", "delete": "\u{7f}", "deleteForward": "\u{f728}",
        "home": "\u{f729}", "end": "\u{f72b}", "pageUp": "\u{f72c}", "pageDown": "\u{f72d}",
        "arrowUp": "\u{f700}", "arrowDown": "\u{f701}", "arrowLeft": "\u{f702}",
        "arrowRight": "\u{f703}"
    ]

    /// 处理菜单项点击：已知动作直接派发，未知动作转交 `onOpen` 并在下次快照后派发。
    @objc private func performAction(_ item: NSMenuItem) {
        let event = NSApp.currentEvent
        let type =
            event?.type == .rightMouseUp || event?.type == .rightMouseDown ? "right-click" : "left-click"
        if let action = item.representedObject as? Action {
            onAction?(action.session, action.handler, type)
        } else {
            guard let identity = identities[ObjectIdentifier(item)],
                actionItems(in: menu).filter({ identities[ObjectIdentifier($0)] == identity }).count == 1
            else {
                onActionUnavailable?()
                return
            }
            pendingActions.append((identity, type))
            onOpen?()
        }
    }

    /// 递归收集菜单（含子菜单）中绑定可派发动作的所有项。
    private func actionItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            if let submenu = item.submenu { return actionItems(in: submenu) }
            return item.action == #selector(performAction(_:)) ? [item] : []
        }
    }

    /// 在新快照到达后，按标识匹配并派发先前挂起的点击。
    private func dispatchPendingActions() {
        guard !pendingActions.isEmpty else { return }
        let pending = pendingActions
        pendingActions.removeAll()
        let items = actionItems(in: menu)
        var unavailable = false
        for request in pending {
            let matches = items.filter { identities[ObjectIdentifier($0)] == request.identity }
            if matches.count == 1, let action = matches.first?.representedObject as? Action {
                onAction?(action.session, action.handler, request.type)
            } else {
                unavailable = true
            }
        }
        if unavailable { onActionUnavailable?() }
    }

    /// 菜单为空时先放入一条禁用的「Loading…」占位项。
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.items.isEmpty {
            let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }
    }

    /// 菜单打开时标记为已展开并通知回调。
    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        onOpen?()
    }

    /// 菜单关闭时复位宽度、套用延后的快照并通知回调。
    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        menu.minimumWidth = 0
        if let deferredSnapshot {
            self.deferredSnapshot = nil
            update(deferredSnapshot)
        }
        onClose?()
    }

    /// 清空会话与挂起动作，并剥离菜单项上的动作绑定。
    func clearMenu() {
        menuSession = nil
        pendingActions.removeAll()
        clearActions(in: menu)
    }

    /// 递归清除菜单及子菜单项上的 `representedObject` 动作。
    private func clearActions(in menu: NSMenu) {
        for item in menu.items {
            item.representedObject = nil
            if let submenu = item.submenu { clearActions(in: submenu) }
        }
    }

    /// 解除回调、取消异步任务并移除状态项。
    func remove() {
        onOpen = nil
        onClose = nil
        onAction = nil
        onActionUnavailable = nil
        pendingActions.removeAll()
        menu.cancelTracking()
        menu.delegate = nil
        iconTask?.cancel()
        menuImageTask?.cancel()
        NSStatusBar.system.removeStatusItem(status)
    }
}
