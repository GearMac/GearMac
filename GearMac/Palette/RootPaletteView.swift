// 文件职责：渲染 Palette 的根视图——按当前模式选择屏幕、编排头部搜索框与底部操作栏、驱动窗口内菜单及键盘处理。
// 分层：UI（SwiftUI）；仅负责呈现与交互转发，状态真值存放于 AppCore/PaletteState。
import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    /// 被观察：快照落地或授权状态变化时，卡片会重新求值。
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(FileSearchSession.self) private var fileSearch
    @Environment(DictionarySession.self) private var dictionary
    @Environment(MenuSearchSession.self) private var menuSearch
    @Environment(WindowSwitchSession.self) private var windowSwitch
    @Environment(CalendarStore.self) private var calendarStore
    /// 被观察：加入会议卡片的倒计时在整分钟边界重绘。
    @Environment(MeetingClock.self) private var meetingClock
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(SnippetsStore.self) private var snippets
    @Environment(ExtensionManager.self) private var extensions
    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics
    @Environment(\.openURL) private var openURL
    @FocusState private var searchFocused: Bool
    /// 与搜索框自身的焦点分开维护。参见 docs/features/palette.md。
    @FocusState private var argumentFocused: String?
    /// 当前打开的窗口内菜单；至多一个，避免状态自相矛盾。
    @State private var openMenu: OpenMenu?
    /// 由 `openActions` 采样一次，使仅运行中才有的行不会在菜单弹出期间出现。
    @State private var selectionIsRunning = false
    /// 当前打开菜单的高亮行；每条打开路径都会设定其起始位置。
    @State private var menuSelection = 0
    /// 右键菜单悬挂的卡片坐标；仅右键路径设置，⌘K 退回面板角落。
    @State private var actionsCardFrame: CGRect?
    /// 正在打标签的条目；二级菜单据此回写。
    @State private var tagTarget: ClipboardItem?
    /// 正在展示选项的参数字段，使 `menuContent` 能重建同一个菜单。
    @State private var argumentOptionsField: String?
    @State private var menuPanel = MenuPanelController()
    /// 面板自身的窗口，由 `WindowReader` 上报；菜单依附于它的 frame。
    @State private var hostWindow: NSWindow?
    /// 待处理的滚动请求；各模式互斥，因此一份状态即可服务全部。
    @State private var scroll = ScrollIntent(kind: .top)

    /// 紧凑还是完整；真值源在 `AppCore` 上，二者不会不一致。
    private var isCollapsed: Bool { core.paletteCoordinator.paletteIsCollapsed }

    /// 当前模式对应的屏幕：其行序即扁平选中索引所指向的可见顺序。
    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return LauncherScreen(
                appIndex: appIndex, favorites: favorites, visibility: visibility,
                currencyRates: currencyRates, core: core, vm: vm, running: selectionIsRunning,
                meeting: core.calendarCoordinator.cardedMeeting, now: meetingClock.now,
                openActions: openActions, openArgumentOptions: openArgumentOptions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, core: core, vm: vm, openActions: openActions,
                openArgumentOptions: openArgumentOptions)
        case .snippets:
            return SnippetsScreen(
                store: snippets, core: core, vm: vm, openActions: openActions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, pinned: core.pinnedEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, defaultColumns: settings.emojiGridColumns,
                openActions: openActions)
        case .fileSearch:
            return FileSearchScreen(
                session: fileSearch, core: core, vm: vm, openActions: openActions)
        case .menuSearch:
            return MenuSearchScreen(
                session: menuSearch, core: core, vm: vm, openActions: openActions)
        case .switchWindows:
            return WindowSwitchScreen(session: windowSwitch, core: core)
        case .rooms:
            return RoomsScreen(coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .roomWindows:
            return RoomPickerScreen(
                coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .schedule:
            return ScheduleScreen(
                store: calendarStore, clock: meetingClock, core: core, vm: vm,
                openActions: openActions)
        case .meetingDetails:
            return MeetingDetailsScreen(store: calendarStore, core: core)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActionsAt: openActionsAtCard,
                openTagFilterMenu: toggleTagFilterMenu, openSettingsMenu: toggleClipboardSettings,
                searchField: { AnyView(headerField) },
                onTagEntry: { item in
                    tagTarget = item
                    open(.clipboardTags, highlighting: tagCreateRowIndex)
                },
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .ai:
            return AIScreen(
                vm: vm, metrics: metrics, chat: quickAI,
                coordinator: core.quickAICoordinator, chatCoordinator: core.aiChatCoordinator,
                openAttachments: toggleAIAttachments)
        case .aiHistory:
            return ChatHistoryScreen(
                history: core.chatHistory, chat: quickAI, coordinator: core.quickAICoordinator,
                vm: vm, openActions: openActions, metrics: metrics)
        case .dictionary:
            return DictionaryScreen(session: dictionary, core: core, vm: vm)
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        case .extensionCommand:
            return ExtensionCommandScreen(
                screen: extensionScreen, extensions: extensions, vm: vm, openActions: openActions)
        }
    }

    /// 正在运行命令的已渲染屏幕（已扁平化）。首次提交落地前为 `.empty`。
    private var extensionScreen: ExtensionScreen {
        guard vm.mode == .extensionCommand, case .rendered(let tree) = extensions.state else {
            return .empty
        }
        return ExtensionScreen(tree: tree, query: vm.query)
    }

    /// ⌘↵ 提交扩展表单；正在编辑字段或输入法合成中时返回 `.ignored`。
    private func handleFormReturn(_ press: KeyPress) -> KeyPress.Result {
        guard !vm.isEditingField, !vm.isComposing else { return .ignored }
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        guard modifiers == .command else { return .ignored }
        activateSelection()
        return .handled
    }

    /// 当前是否为扩展的 Form 屏幕（其主操作由 ⌘↵ 提交）。
    private var isExtensionForm: Bool {
        vm.mode == .extensionCommand && extensionScreen.kind == .form
    }

    /// 被夹取到结果范围内的选中索引：高亮、预览与激活共用同一来源。
    private func selection(count: Int) -> Int {
        count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    /// 接收已解析的屏幕——访问 `rows` 需构建列表，因此调用方只解析一次。
    private func selection(in screen: any PaletteScreen) -> Int {
        selection(count: screen.rows.count)
    }

    private var menuOpen: Bool { openMenu != nil }

    // MARK: - Popover menu content

    /// 剪贴板类型筛选的行；激活某项是改变筛选条件的唯一途径。
    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.localizedTitle(settings.resolvedLanguage),
                    systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.clipboardFilter = filter
                }
            })
    }

    /// 最右侧的剪贴板设置菜单：开关与删除全部。
    private var clipboardSettingsContent: PopoverMenuContent {
        PopoverMenuContent(
            items: [
                PopoverMenuItem(
                    title: settings.text(ClipboardKey.settingsToggleHistory),
                    icon: settings.clipboardEnabled ? .symbol("checkmark") : .blank
                ) {
                    settings.clipboardEnabled.toggle()
                    closeMenus()
                },
                PopoverMenuItem(
                    title: settings.text(ClipboardKey.settingsToggleTextSearch),
                    icon: settings.clipboardTextSearchEnabled ? .symbol("checkmark") : .blank
                ) {
                    settings.clipboardTextSearchEnabled.toggle()
                    closeMenus()
                },
                PopoverMenuItem(
                    title: settings.text(ClipboardKey.settingsMore), systemImage: "gearshape"
                ) {
                    core.settingsCoordinator.showSettings(tab: .clipboard)
                    closeMenus()
                },
                PopoverMenuItem(
                    title: settings.text(ClipboardKey.settingsDeleteAll), systemImage: "trash",
                    startsSection: true, isDestructive: true
                ) {
                    closeMenus()
                    Task { await core.clipboardCoordinator.deleteAllClips() }
                }
            ])
    }

    /// 打标签二级菜单：名称输入、返回、已有标签、清除，底部色板即新建。
    /// 名称必须在构建时捕获：行激活前 `closeMenus` 已把菜单查询清空。
    private var tagListContent: PopoverMenuContent {
        guard let item = tagTarget else { return PopoverMenuContent(items: []) }
        let typedName = vm.menuQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: settings.text(ClipboardKey.tagBack), systemImage: "chevron.left"
            ) {
                open(.actions, highlighting: 0)
            }
        ]
        for tag in store.tags {
            items.append(
                PopoverMenuItem(
                    title: tag.name, icon: .dot(tagMenuColor(tag.colorHex)),
                    detail: item.tag == tag.name ? "✓" : nil
                ) {
                    store.setTag(tag.name, for: item)
                    closeMenus()
                })
        }
        if item.tag != nil {
            items.append(
                PopoverMenuItem(
                    title: settings.text(ClipboardKey.tagClear), systemImage: "tag.slash"
                ) {
                    store.setTag(nil, for: item)
                    closeMenus()
                })
        }
        // 底部色板：选中某个颜色即以输入的名称新建并打标；回车落在首个颜色行上。
        let firstColorIndex = items.count
        for hex in ClipTagPalette.hexes {
            items.append(
                PopoverMenuItem(
                    title: hex, icon: .dot(tagMenuColor(hex)),
                    sectionTitle: hex == ClipTagPalette.hexes.first
                        ? settings.text(ClipboardKey.tagNew) : nil,
                    startsSection: hex == ClipTagPalette.hexes.first
                ) {
                    createTag(typedName, colorHex: hex, on: item)
                })
        }
        return PopoverMenuContent(header: settings.text(ClipboardKey.tagEntry), items: items)
    }

    /// 色板首行索引：返回行 + 标签行 + 可选清除行之后；打开与输入后都落位到它，使回车即新建。
    private var tagCreateRowIndex: Int {
        1 + store.tags.count + (tagTarget?.tag != nil ? 1 : 0)
    }

    private func createTag(_ name: String, colorHex: String, on item: ClipboardItem) {
        guard !name.isEmpty else {
            core.showMessage(settings.text(ClipboardKey.tagNameMissing), tone: .danger)
            return
        }
        store.createTag(name: name, colorHex: colorHex)
        store.setTag(name, for: item)
    }

    /// 「标签」筛选菜单：选一个标签过滤卡片行。
    private var tagFilterContent: PopoverMenuContent {
        let items = store.tags.map { tag in
            PopoverMenuItem(
                title: tag.name, icon: .dot(tagMenuColor(tag.colorHex)),
                detail: vm.clipboardTagFilter == tag.name ? "✓" : nil
            ) {
                vm.clipboardTagFilter = tag.name
                closeMenus()
            }
        }
        return PopoverMenuContent(header: settings.text(ClipboardKey.tabTag), items: items)
    }

    /// 菜单里标签圆点的取色；解析失败时退回次级文字色。
    private func tagMenuColor(_ hex: String) -> Color {
        ColorValue.parse(hex).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
            ?? Theme.Colors.textSecondary
    }

    /// 文件搜索类型筛选的行，构建方式与剪贴板筛选一致。
    private var fileSearchFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: FileSearchFilter.allCases.map { filter in
                PopoverMenuItem(
                    title: filter.localizedTitle(settings.resolvedLanguage),
                    systemImage: filter.systemImage
                ) {
                    vm.fileSearchFilter = filter
                }
            })
    }

    /// All Categories 位于分隔线上方；其余行与其分区顺序一致。
    private var emojiCategoryContent: PopoverMenuContent {
        PopoverMenuContent(
            items: EmojiCategoryFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.emojiCategoryFilter = filter
                }
            })
    }

    /// 应用菜单的内容（Changelog / About / Support / Settings / Quit）。
    private var appMenuContent: PopoverMenuContent {
        let appName = Bundle.main.appDisplayName
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let title =
            version.map {
                String(format: settings.text(PaletteKey.appMenuHeaderFormat), appName, $0)
            } ?? appName
        return PopoverMenuContent(
            header: title,
            items: [
                PopoverMenuItem(
                    title: settings.text(PaletteKey.appMenuChangelog),
                    systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                ) {
                    if let url = URL(string: "https://github.com/GearMac/GearMac/releases") {
                        openURL(url)
                    }
                },
                PopoverMenuItem(
                    title: settings.text(PaletteKey.appMenuAbout), systemImage: "info.circle"
                ) {
                    core.settingsCoordinator.showAbout()
                },
                PopoverMenuItem(
                    title: settings.text(PaletteKey.appMenuSupport), systemImage: "heart"
                ) {
                    core.supportCoordinator.showSupport()
                },
                PopoverMenuItem(
                    title: settings.text(PaletteKey.appMenuSettings), systemImage: "gearshape",
                    shortcut: "⌘,"
                ) {
                    core.settingsCoordinator.showSettings()
                },
                PopoverMenuItem(
                    title: String(format: settings.text(PaletteKey.appMenuQuitFormat), appName),
                    systemImage: "rectangle.portrait.and.arrow.right",
                    startsSection: true, isDestructive: true
                ) {
                    NSApp.terminate(nil)
                }
            ])
    }

    /// 所有菜单路径寻址行的唯一来源，因此不会彼此不一致。
    private var menuContent: PaletteMenuContent? {
        switch openMenu {
        case .actions:
            let screen = screen
            return screen.menuContent(
                at: selection(in: screen), searchQuery: ActionMenuSearchQuery(vm.menuQuery),
                menuSelection: $menuSelection,
                onActivate: activateMenuItem)
        case .app:
            let filtered = appMenuContent.matching(ActionMenuSearchQuery(vm.menuQuery))
            return PaletteMenuContent(
                popover: filtered.content, selection: $menuSelection,
                search: PopoverMenu.Search(
                    placeholder: settings.text(PaletteKey.searchActionsPlaceholder),
                    placement: .bottom),
                onActivate: activateMenuItem, preferredSelection: filtered.bestMatch)
        case .clipboardFilter:
            return headerMenu(
                clipboardFilterContent, width: metrics.size.clipboardFilterMenuWidth)
        case .clipboardSettings:
            return headerMenu(
                clipboardSettingsContent, width: metrics.size.menuWidth)
        case .clipboardTags:
            // 名称输入即菜单查询：行绝不能被查询过滤，且输入后仍落位在首行色板上。
            return PaletteMenuContent(
                popover: tagListContent, selection: $menuSelection,
                search: PopoverMenu.Search(
                    placeholder: settings.text(ClipboardKey.tagNamePlaceholder),
                    placement: .top),
                onActivate: activateMenuItem, preferredSelection: tagCreateRowIndex)
        case .clipboardTagFilter:
            return headerMenu(tagFilterContent, width: metrics.size.menuWidth)
        case .fileSearchFilter:
            return headerMenu(fileSearchFilterContent, width: metrics.size.fileSearchFilterMenuWidth)
        case .emojiCategory:
            return headerMenu(emojiCategoryContent, width: metrics.size.emojiCategoryMenuWidth)
        case .aiModel:
            return headerMenu(
                AIModelMenu.models(coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .aiReasoning:
            return headerMenu(
                AIModelMenu.reasoning(
                    coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .aiAttachments:
            guard !quickAI.pendingAttachments.isEmpty else { return nil }
            return headerMenu(
                AIModelMenu.attachments(
                    coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .argumentOptions:
            guard let field = argumentOptionsField,
                let popover = headerAccessory?.optionsMenu(field)
            else { return nil }
            return headerMenu(popover, width: metrics.size.menuWidth)
        case .extensionAccessory:
            return extensionCommandScreen?.searchAccessoryMenu(
                searchQuery: ActionMenuSearchQuery(vm.menuQuery),
                menuSelection: $menuSelection, onActivate: activateMenuItem)
        case nil: return nil
        }
    }

    var body: some View {
        // 每次渲染只解析一次屏幕，使扁平索引不会与行错位。
        let screen = screen
        let count = screen.rows.count
        let sel = selection(count: count)
        // 扩展的 Form 没有可计数的行，但 ↵ 仍然有效。
        let showActionGroup =
            (count > 0 || screen.actsWithoutRows)
            && screen.hasPrimaryAction(at: sel)

        // 头部只保留一个位置，使焦点在切换后仍保留。参见 docs/features/palette.md。
        return keyHandlers(
            stateObservers(
                Group {
                    if isCollapsed {
                        Color.clear
                    } else {
                        screen.body(selection: sel, scroll: scroll)
                    }
                }
                // 剪贴板停靠条没有头部：标签行就是首行，返回箭头收进标签行首部。
                .safeAreaInset(edge: .top, spacing: 0) {
                    if vm.mode != .clipboard { header }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isCollapsed, vm.mode != .clipboard {
                        bottomBar(
                            pillLabel: screen.primaryActionTitle, showActionGroup: showActionGroup,
                            formPrimaryShortcut: isExtensionForm,
                            showActions: screen.hasActions(at: sel))
                    }
                }
                // 面板没有标题栏，这条顶部窄边是唯一可抓取拖动的位置。
                .overlay(alignment: .top) { if vm.mode != .clipboard { topDragStrip } }
                // 绝不条件挂载：卸载会让 SwiftUI 的悬停目标悬空并吞掉点击。
                .overlay {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        // 不用 tap 手势：带轻微位移的按压仍需能关闭，如同原生菜单。
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in closeMenus() })
                        .onRightClick { closeMenus() }
                        .allowsHitTesting(menuOpen)
                }
                // 菜单位于独立窗口；这里只上报它应依附的窗口。
                .background(
                    WindowReader {
                        hostWindow = $0
                        installHeaderArrowHandler(in: $0)
                    }
                )
                // 以窗口 frame 作为尺寸来源，使毛玻璃与裁剪保持一致。
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.Colors.panelScrim)
                .background(GlassEffectView())
                .overlay {
                    Theme.Colors.dialogDimming
                        .opacity(core.isDimmingPaletteForDialog ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(
                    .easeOut(
                        duration: core.isDimmingPaletteForDialog
                            ? Theme.Duration.dialogEnter : Theme.Duration.dialogExit),
                    value: core.isDimmingPaletteForDialog
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))),
            selection: sel)
    }

    /// 表情网格的观察者，单独拆出以使 `stateObservers` 仍能被类型检查器推导。
    @ViewBuilder
    private func emojiObservers(_ content: some View) -> some View {
        content
            .onChange(of: vm.emojiCategoryFilter) { land() }
            .onChange(of: core.pinnedEmoji.revision) { emojiGridChanged() }
            .onChange(of: (screen as? EmojiScreen)?.frequentlyUsed) { old, new in
                guard let old, let new else { return }
                (screen as? EmojiScreen)?.frequentlyUsedChanged(from: old, to: new)
                emojiGridChanged()
            }
            .onChange(of: vm.emojiGridColumnsOverride) { emojiGridChanged() }
            .onChange(of: settings.emojiGridColumns) { emojiGridChanged() }
            // ⌘0 / ⌘+ / ⌘- 与 ⌘. 一样以令牌形式到达。参见 `PaletteState.emojiGridZoomToken`。
            .onChange(of: vm.emojiGridZoomToken) {
                guard let zoom = vm.emojiGridZoom else { return }
                (screen as? EmojiScreen)?.zoom(zoom)
            }
    }

    /// 钉选与密度会移动选中项下方的单元格，并可能改变已打开的 Actions 菜单的行。
    private func emojiGridChanged() {
        guard vm.mode == .emoji else { return }
        scroll = ScrollIntent(kind: .follow)
        refreshActionsMenu()
    }

    /// 与 `keyHandlers` 同理从 `body` 中拆出；返回 `AnyView` 切断与外层链的泛型累积，
    /// 标准 runner 上只有拆开各自求解才能在类型检查时限内完成。
    private func stateObservers(_ content: some View) -> AnyView {
        AnyView(emojiObservers(content)
            // 每次显示都会更新 focusToken，使搜索框重新获得焦点。
            .onChange(of: vm.focusToken) {
                searchFocused = !screenHidesSearchField
            }
            // 保留的屏幕会按离开时的状态重新唤起，因此菜单必须随面板一同结束。
            .modifier(PaletteHideObserver { if menuOpen { closeMenus() } })
            .onChange(of: vm.query) {
                if vm.collapseQueryLineBreaks() { return }
                land()
                if vm.mode == .fileSearch { fileSearch.search(vm.query, filter: vm.fileSearchFilter) }
                if vm.mode == .dictionary { dictionary.lookUp(vm.query) }
                if vm.mode == .menuSearch { menuSearch.filter(vm.query) }
                if vm.mode == .switchWindows { windowSwitch.filter(vm.query) }
                // 接管搜索文本的命令会用它筛选自己的列表。
                if vm.mode == .extensionCommand, let handler = extensionScreen.searchTextHandler {
                    extensions.dispatch(handler: handler, arguments: [vm.query])
                }
            }
            // 命令仍在启动期间键入的内容不会经过其处理器。
            .onChange(of: extensionScreen.searchTextHandler) { previous, handler in
                guard previous == nil, let handler, !vm.query.isEmpty else { return }
                extensions.dispatch(handler: handler, arguments: [vm.query])
            }
            .modifier(ExtensionSelectionForwarder(screen: extensionScreen, selection: vm.selection))
            // 列表变窄后旧索引会指向不同的行，或不再指向任何行。
            .onChange(of: vm.clipboardFilter) { land() }
            .onChange(of: vm.clipboardTagFilter) { land() }
            // 筛选条件是查询的一部分，因此收窄范围会重跑查询而非仅裁剪行。
            .onChange(of: vm.fileSearchFilter) {
                land()
                fileSearch.search(vm.query, filter: vm.fileSearchFilter)
            }
            .onChange(of: vm.mode) {
                vm.clipboardFilter = .all
                vm.fileSearchFilter = .all
                vm.emojiCategoryFilter = .all
                vm.emojiGridColumnsOverride = nil
                vm.fileSearchQuickLook = false
                if menuOpen { closeMenus() }
                land()
                // 停靠与常规布局的尺寸不同，模式切换必须同步窗口框架。
                core.paletteCoordinator.syncPaletteSize()
                searchFocused = !screenHidesSearchField
                // 离开卸载屏幕的所有方式：返回箭头、裸退格、重新唤起。
                if vm.mode != .uninstall { uninstall.cancel() }
                // 无查询进入即空白屏幕自身对最近项的请求。
                if vm.mode == .fileSearch {
                    fileSearch.search(vm.query, filter: vm.fileSearchFilter)
                } else {
                    fileSearch.cancel()
                }
                if vm.mode == .dictionary {
                    dictionary.lookUp(vm.query)
                } else {
                    dictionary.reset()
                }
                if vm.mode != .menuSearch { menuSearch.reset() }
                if vm.mode != .switchWindows { windowSwitch.reset() }
                if vm.mode != .meetingDetails { calendarStore.clearDetails() }
                if vm.mode != .rooms, vm.mode != .roomWindows { core.roomCoordinator.screensDidClose() }
                // 以 Escape 之外的方式离开屏幕，同样会结束命令会话。
                if vm.mode != .extensionCommand, extensions.running != nil, !extensions.isAuthorizing {
                    Task { await extensions.stop() }
                }
            }
            // `prepare` 可能不改动其他状态，因此这里仍把列表落定为刚打开的样子。
            .onChange(of: vm.resetToken) {
                if menuOpen { closeMenus() }
                land()
            }
            // ⌘. 以令牌而非按键形式到达。参见 `PaletteState.pinChordToken`。
            .onChange(of: vm.pinChordToken) { performShortcut(.pin) }
            .onChange(of: vm.queryRewriteToken) {
                if menuOpen { closeMenus() }
                searchFocused = true
                // 延后一拍，在「重新聚焦并全选」之后，使继续输入能续写答案。
                Task { @MainActor in (hostWindow as? PalettePanel)?.moveFieldEditorCaretToEnd() }
            }
            // ⌘1…⌘0 由 AppKit keyCode 匹配后以槽位索引形式到达。
            .onChange(of: vm.favoriteSlotToken) {
                if let index = vm.favoriteSlotIndex { performShortcut(.favoriteSlot(index)) }
            }
            // 用单个可选值在结构上保证「至多一个菜单」；这里只负责呈现。
            .onChange(of: openMenu) {
                guard menuOpen else { return }
                syncMenuPanel(presenting: true)
            }
            // 承载的视图树是独立层级，因此高亮需要主动推送进去。
            .onChange(of: menuSelection) { syncMenuPanel(presenting: false) }
            .onChange(of: vm.menuQuery) { menuQueryChanged() }
            .onDisappear {
                menuPanel.hide()
                (hostWindow as? PalettePanel)?.onHeaderFieldBoundaryArrow = nil
            }
            // 首次显示在 `prepare` 之后才构建本视图，因此没有任何处理器见到那次重置。
            .onAppear {
                searchFocused = !screenHidesSearchField
                land()
            }
            .modifier(SearchFieldHiding(hidden: hidesSearchField, apply: applySearchFieldHiding))
            // 有多条路径会翻转 `paletteIsCollapsed`，因此让窗口尺寸与之同步。
            .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
                core.paletteCoordinator.syncPaletteSize()
            })
    }

    /// 从 `body` 中拆出；返回 `AnyView` 切断与外层链的泛型累积，同 `stateObservers`。
    private func keyHandlers(_ content: some View, selection sel: Int) -> AnyView {
        AnyView(content
            // 包含 repeat 阶段：与裸键一样，长按可连续移动。
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(1, modifiers: press.modifiers) { return reorder }
                // 控件自身的列表弹出时，独占所有导航键。
                if vm.isControlListOpen { return .ignored }
                if isCollapsed {
                    // 紧凑栏不显示选中项，按 Down 展开并定位到列表首行。
                    vm.selection = 0
                    core.paletteCoordinator.expandFromCompact()
                    return .handled
                }
                if menuOpen {
                    moveMenu(1)
                    return .handled
                }
                return moveVertically(1)
            }
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(-1, modifiers: press.modifiers) { return reorder }
                if vm.isControlListOpen { return .ignored }
                if isCollapsed { return .ignored }
                if menuOpen {
                    moveMenu(-1)
                    return .handled
                }
                return moveVertically(-1)
            }
            // 左右方向键用于在网格中步进；其他场景则留给光标。
            .onKeyPress(.leftArrow) {
                if vm.isControlListOpen { return .ignored }
                if menuOpen { return .handled }
                return moveHorizontally(-1) ? .handled : .ignored
            }
            .onKeyPress(.rightArrow) {
                if vm.isControlListOpen { return .ignored }
                if menuOpen { return .handled }
                return moveHorizontally(1) ? .handled : .ignored
            }
            // 裸 ↵ 执行打开菜单中的行或非表单选中项；⌘↵ 提交表单。
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
                let command = press.modifiers.contains(.command)
                let option = press.modifiers.contains(.option)
                if menuOpen, !command, !option {
                    activateMenuItem(menuSelection)
                    return .handled
                }
                if isExtensionForm { return handleFormReturn(press) }
                let screen = screen
                guard command || option else {
                    guard !vm.isComposing else { return .ignored }
                    // 搜索框被隐藏且没有聚焦控件应答时的兜底路径。
                    let answersWithoutFocus = screen.hidesSearchField && screen.rows.isEmpty
                    guard searchFocused || answersWithoutFocus else { return .ignored }
                    activateSelection()
                    return .handled
                }
                let selection = selection(in: screen)
                if command, press.modifiers.contains(.control), screen.tertiary(at: selection) {
                    return .handled
                }
                if command, press.modifiers.contains(.shift),
                    screen.perform(.copyCalculation, at: selection)
                {
                    return .handled
                }
                if command { return screen.secondary(at: selection) ? .handled : .ignored }
                return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                if menuPanel.isClosing { return .handled }
                // 打开的控件列表先于其下的面板接管 Escape。
                if vm.isControlListOpen { return .ignored }
                switch PaletteEscapeAction.resolve(
                    menuOpen: menuOpen, menuQuery: vm.menuQuery,
                    argumentFocused: argumentFocused != nil, query: vm.query, mode: vm.mode,
                    canGoBack: vm.canGoBack,
                    behavior: settings.escapeKeyBehavior)
                {
                case .clearMenuQuery, .closeMenu:
                    escapeMenu()
                case .leaveArgumentField:
                    returnFocusToSearchField()
                case .clearQuery:
                    vm.query = ""
                case .exitExtensionScreen:
                    core.extensionCoordinator.exitExtensionScreen()
                case .goBack:
                    goBack()
                case .hidePalette:
                    core.paletteCoordinator.hidePalette()
                    // 该行为承诺重新打开时回到根搜索，不受延迟设置影响。
                    if settings.escapeKeyBehavior == .closeAndPopToRoot {
                        core.paletteCoordinator.popToRootNow()
                    }
                }
                return .handled
            }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                // 打开列表中的 ⇥ 属于该列表，而不属于表单的字段顺序。
                if vm.isControlListOpen { return .handled }
                if !menuOpen { advanceTabFocus(backwards: press.modifiers.contains(.shift)) }
                return .handled
            }
            .modifier(
                ExtensionShortcutKeys(
                    screen: menuOpen ? nil : screen as? ExtensionCommandScreen, selection: sel)
            )
            // ⌘K 切换当前选中项的操作面板。
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "k")
                else { return .ignored }
                // 控件打开的列表独占屏幕，不得在其上再开第二个面板。
                guard !vm.isControlListOpen else { return .handled }
                // Actions 菜单在紧凑栏中没有锚点，故此处吞掉 ⌘K。
                guard !isCollapsed else { return .handled }
                let screen = screen
                guard !screen.rows.isEmpty || screen.actsWithoutRows else { return .handled }
                // 出错的算式卡片虽然被选中却没有可用操作——不要打开空面板。
                guard screen.hasPrimaryAction(at: selection(in: screen)) else { return .handled }
                // 底部栏未提供菜单时同理：⌘K 只打开栏中所展示的内容。
                guard screen.hasActions(at: selection(in: screen)) else { return .handled }
                toggleActions()
                return .handled
            }
            // 屏幕负责响应行的组合键；裸退格在 `sendEvent` 中拦截。
            .onKeyPress(phases: .down) { press in
                let isDeleteKey = press.key == .delete || press.key == .deleteForward
                if isDeleteKey, menuOpen { return .handled }
                guard
                    let shortcut = PaletteShortcut.resolve(
                        command: press.modifiers.contains(.command),
                        shift: press.modifiers.contains(.shift),
                        option: press.modifiers.contains(.option),
                        control: press.modifiers.contains(.control),
                        isDeleteKey: isDeleteKey,
                        matches: { ASCIIKeyboardLayout.matches(press.key, character: $0) })
                else { return .ignored }
                guard !shortcut.requiresExpanded || !isCollapsed else { return .ignored }
                let screen = screen
                guard screen.perform(shortcut, at: selection(in: screen)) else { return .ignored }
                if shortcut.closesMenu, menuOpen { closeMenus() }
                return .handled
            }
            // 绝不依赖行是否为空：筛选过窄会清空行，而这正是脱困路径。
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "p")
                else { return .ignored }
                return performFilterAction() ? .handled : .ignored
            })
    }

    /// 沿顶边的细条，用于抓取移动窗口；由外观设置决定是否启用。
    private var topDragStrip: some View {
        Color.clear
            .frame(height: metrics.size.headerPadding)
            .windowDraggable(windowDragging, onBegan: beginDrag, onEnded: endDrag)
    }

    /// 剪贴板横条固定停靠在屏幕底部，拖拽会污染常规布局的位置记忆。
    private var windowDragging: Bool {
        settings.paletteDraggable && vm.mode != .clipboard
    }

    /// 头部中无人占用的细条——可安全拖拽；搜索框自行处理其自身的拖拽。
    private func headerGutter(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .windowDraggable(windowDragging, onBegan: beginDrag, onEnded: endDrag)
    }

    private func beginDrag() { core.paletteCoordinator.beginPaletteDrag() }
    private func endDrag() { core.paletteCoordinator.endPaletteDrag() }

    /// 剪贴板是否处于任何筛选之下；头部箭头据此出现。
    private var clipboardFilterActive: Bool {
        vm.clipboardFilter != .all || vm.clipboardTagFilter != nil
    }

    /// 箭头点击：回到全部列表。
    private func clearClipboardFilters() {
        vm.clipboardFilter = .all
        vm.clipboardTagFilter = nil
    }

    /// 命令可在其列表之上推入 Form，从而在会话中途接管键盘。
    private func applySearchFieldHiding(_ hidden: Bool) {
        searchFocused = !hidden
        if hidden { vm.query = "" }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            // 与下方列表行及分区标题自身的缩进保持一致。
            headerGutter(width: metrics.spacing.md * 2)
            // 各子屏幕以相同方式退出；剪贴板无筛选时头部不显示任何图标。
            if vm.mode != .launcher {
                if vm.mode == .clipboard {
                    if clipboardFilterActive {
                        HeaderBackButton(help: backHelp, action: clearClipboardFilters)
                    }
                } else {
                    HeaderBackButton(help: backHelp, action: goBack)
                }
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(metrics.typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.size.headerIconSlot)
                    .windowDraggable(windowDragging, onBegan: beginDrag, onEnded: endDrag)
            }
            // slot + xl 等于行的 icon + lg，使查询文本与行标题对齐起始。
            headerGutter(width: metrics.spacing.xl)
            // 固定一个结构位置：放在分支内的输入框在切换分支时会丢失第一响应者。
            // 剪贴板是刻意的例外：输入框迁往底部横条的标签行，模式切换由 focusToken 重新聚焦。
            if vm.mode != .clipboard {
                headerField
            }
            if let accessory = headerAccessory {
                accessory.view
                // 最后分配空间：按默认优先级它会与输入框争抢。
                Spacer(minLength: 0).layoutPriority(-1)
            }
            if tabOpensChat {
                headerGutter(width: metrics.spacing.md)
                quickAITabHint
            }
            // 剪贴板的类型筛选由底部横条的标签行承担，头部不再重复入口。
            if !isCollapsed, vm.mode == .fileSearch {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.fileSearchFilter.localizedTitle(settings.resolvedLanguage),
                    systemImage: vm.fileSearchFilter.systemImage,
                    isOpen: openMenu == .fileSearchFilter,
                    help: settings.text(PaletteKey.helpFilterByType),
                    action: toggleFileSearchFilter)
            }
            if !isCollapsed, vm.mode == .emoji {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.emojiCategoryFilter.title,
                    systemImage: vm.emojiCategoryFilter.systemImage,
                    isOpen: openMenu == .emojiCategory,
                    help: settings.text(PaletteKey.helpFilterByCategory),
                    action: toggleEmojiCategory)
            }
            if !isCollapsed, vm.mode == .ai {
                headerGutter(width: metrics.spacing.md)
                AIModelButton(
                    title: core.aiChatCoordinator.selectedModelTitle(for: quickAI),
                    icon: core.aiChatCoordinator.selectedModelIcon(for: quickAI),
                    isOpen: openMenu == .aiModel,
                    action: toggleAIModel)
                if !core.aiChatCoordinator.reasoningEfforts(for: quickAI).isEmpty {
                    headerGutter(width: metrics.spacing.md)
                    AIReasoningButton(
                        title: core.aiChatCoordinator.selectedReasoningTitle(for: quickAI),
                        isOpen: openMenu == .aiReasoning,
                        action: toggleAIReasoning)
                }
            }
            // 紧凑模式把收藏钉在输入框旁；展开模式则将其显示为行。
            if isCollapsed, settings.showFavoritesInCompactMode,
                let launcher = screen as? LauncherScreen
            {
                let favorites = launcher.compactFavorites
                if !favorites.isEmpty {
                    headerGutter(width: metrics.spacing.md)
                    CompactFavoritesRow(
                        favorites: favorites,
                        showsOverflow: launcher.hasUnshownFavorites,
                        onLaunch: { core.launcherCoordinator.launch($0) },
                        onOverflow: { core.paletteCoordinator.expandFromCompact() }
                    )
                }
            }
            if !isCollapsed, let command = extensionCommandScreen,
                let accessory = command.searchAccessory
            {
                headerGutter(width: metrics.spacing.md)
                command.searchAccessoryButton(
                    accessory, isOpen: openMenu == .extensionAccessory,
                    action: toggleExtensionSearchAccessory)
            }
            headerGutter(width: metrics.spacing.md * 2)
        }
        // 两种状态使用相同度量，输入时搜索栏不会移动。
        .frame(height: metrics.size.headerHeight)
        .padding(.top, metrics.size.headerPadding)
        .frame(maxWidth: .infinity)
        // 在显示之后设置，使被指定的字段而非搜索框获得焦点。
        .onChange(of: vm.pendingArgumentEntryID) { focusPendingArgument() }
        .onChange(of: argumentFocused) { _, field in vm.noteEditingField(field != nil) }
        .onChange(of: quickAI.pendingAttachments.map(\.id)) { refreshAttachmentsMenu() }
    }

    /// 先按模式过滤再转型，否则每一次转型都会让其他模式付出构建列表的代价。
    private var extensionCommandScreen: ExtensionCommandScreen? {
        guard vm.mode == .extensionCommand else { return nil }
        return screen as? ExtensionCommandScreen
    }

    /// 由提供它的屏幕决定；紧凑栏没有容纳它的空间。
    private var headerAccessory: PaletteHeaderAccessory? {
        guard !isCollapsed else { return nil }
        let screen = screen
        return screen.headerAccessory(at: selection(in: screen), focus: $argumentFocused)
    }

    /// 没有其他地方提示 Tab，因此由启动器说明其去向。
    private var quickAITabHint: some View {
        BarButton(chrome: .rounded, action: cycleMode) {
            HStack(spacing: metrics.spacing.sm) {
                Text(settings.text(PaletteKey.quickAI))
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                KeyCapChip(text: "⇥", style: .outline)
            }
        }
        .help(settings.text(PaletteKey.quickAIHelp))
    }

    /// 经由 `PaletteTabAction` 解析，使提示不会指向错误的目标。
    private var tabOpensChat: Bool {
        guard !isCollapsed, headerAccessory?.fieldNames.isEmpty ?? true else { return false }
        return PaletteTabAction.resolve(
            mode: vm.mode, aiEnabled: settings.aiEnabled,
            clipboardEnabled: settings.clipboardEnabled) == .ask
    }

    /// 屏幕接管键盘时为真，此时返回箭头旁的头部为空。
    private var hidesSearchField: Bool {
        guard !isCollapsed else { return false }
        // 剪贴板把输入框迁到标签行而非隐藏；提前返回也切断 screen 与字段视图的相互构建。
        if vm.mode == .clipboard { return false }
        return screen.hidesSearchField
    }

    /// 长修饰链的闭包里直接打开 existential 求解会超出 CI 的时间预算，收敛到此处求解一次。
    private var screenHidesSearchField: Bool {
        screen.hidesSearchField
    }

    /// 输入框保持挂载并隐藏而非替换：放入分支会拆掉其编辑器。
    private var headerField: some View {
        searchField
            // 这是宽度上限而非固定尺寸，长查询时先压缩此行再溢出。
            .frame(minWidth: searchFieldFloor, maxWidth: searchFieldWidth)
            .opacity(hidesSearchField ? 0 : 1)
            .allowsHitTesting(!hidesSearchField)
            .accessibilityHidden(hidesSearchField)
            // 它上报的 frame 决定面板放置 I 形光标的位置；隐藏时则不属于任何区域。
            .onChange(of: hidesSearchField) { _, hidden in
                if hidden { vm.searchFieldFrame = .zero }
            }
    }

    /// 仅在有内容共享该行时固定宽度：附件条或屏幕自身标题。
    private var searchFieldWidth: CGFloat? {
        if hidesSearchField { return nil }
        return headerAccessory.map(searchFieldWidth)
    }

    private var searchFieldFloor: CGFloat? {
        searchFieldWidth.map { min($0, metrics.size.searchFieldMinWidth) }
    }

    /// 按字段自身文本计算宽度，设下限以容纳光标、设上限使附件条留在屏内。
    /// 为空时取占位提示的宽度——这正是让附件条紧贴其后的原因。
    private func searchFieldWidth(for accessory: PaletteHeaderAccessory) -> CGFloat {
        let font = metrics.typography.searchFieldNSFont
        let text = vm.query.isEmpty ? searchPrompt : vm.query
        let typed = (text as NSString).size(withAttributes: [.font: font]).width
        let chrome = metrics.size.headerIconSlot + metrics.spacing.md * 3 + metrics.spacing.xl
        let room = metrics.size.panelWidth - accessory.width - chrome
        // +3pt 使光标位于最后一个字形之后而非压在其上。
        return min(
            max(typed + metrics.scaled(3), metrics.scaled(18)),
            max(room, metrics.size.searchFieldMinWidth))
    }

    private var searchPrompt: String {
        // 被压缩到光标宽度时输入框放不下占位提示；与附件条并排时则保留。
        if headerAccessory?.placement == .afterQuery, vm.mode != .ai { return "" }
        // 命令运行期间搜索栏归属于该扩展。
        if vm.mode == .extensionCommand, let placeholder = extensionScreen.searchPlaceholder {
            return placeholder
        }
        return vm.mode.placeholder(settings.language)
    }

    /// 唯一的搜索框——为空时充当拖拽柄，有文本时所有按压都交给编辑。
    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(metrics.typography.searchField)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            // 填满整行高度，使其上方没有空隙与 topDragStrip 相接。
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                // 输入法的候选文字会使 `query` 为空，此时占位提示会与其重叠。
                if vm.query.isEmpty, !vm.isComposing {
                    Text(searchPrompt)
                        .font(metrics.typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        // 绝不作为点击目标：点击占位提示仍应把光标落到输入框。
                        .allowsHitTesting(false)
                }
            }
            // 以前由占位提示承担；没有它输入框将缺少无障碍标签。
            .accessibilityLabel(Text(searchPrompt))
            // 绝不以 query 分支——曾经因此在输入过程中拆掉字段编辑器。
            .overlay {
                if windowDragging {
                    EmptyFieldDragHandle(
                        // 候选文字会使 `query` 为空，且合成过程仍属于编辑。
                        isEmpty: vm.query.isEmpty && !vm.isComposing,
                        onBegan: beginDrag, onEnded: endDrag,
                        // 未发生位移的按压，其目标其实是拖拽柄所覆盖的输入框。
                        onClick: { searchFocused = true })
                }
            }
            // 面板以此作为指针判定依据，而非对输入框做命中测试。
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                // 隐藏的输入框不接收光标，也就不占用 I 形光标区域。
                vm.searchFieldFrame = hidesSearchField ? .zero : $0
            }
    }

    /// 卸载屏幕的主操作具有破坏性，因此其胶囊按钮不用白色。
    private var pillTint: Color {
        vm.mode == .uninstall ? Theme.Colors.destructive : .primary
    }

    /// 底部栏：应用菜单按钮，以及需要时显示的主操作/Actions 胶囊组。
    private func bottomBar(
        pillLabel: String, showActionGroup: Bool, formPrimaryShortcut: Bool, showActions: Bool
    ) -> some View {
        // 悬浮控件、无底栏；边缘渐隐让下方掠过的行呈现虚影。
        HStack(spacing: 0) {
            appMenuButton
                .modifier(ExtensionToastSlot(extensions: extensions, showing: vm.mode == .extensionCommand))
            if showActionGroup {
                actionGroup(
                    pillLabel: pillLabel, formPrimaryShortcut: formPrimaryShortcut,
                    showActions: showActions
                )
                .fixedSize()
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    /// 底部的圆形应用菜单按钮；已打开时再次点击则关闭。
    private var appMenuButton: some View {
        MenuCircleButton(action: toggleAppMenu)
    }

    /// 应用菜单的唯一开关；停靠横条的标签行尾部也走这里。
    private func toggleAppMenu() {
        if openMenu == .app { closeMenus() } else { open(.app, highlighting: 0) }
    }

    /// 底部控件组：主操作与 Actions 开关共用一个玻璃胶囊。
    private func actionGroup(
        pillLabel: String, formPrimaryShortcut: Bool, showActions: Bool
    ) -> some View {
        HStack(spacing: 2) {
            BarButton(action: activateSelection) {
                HStack(spacing: metrics.spacing.sm) {
                    Text(pillLabel)
                        .font(metrics.typography.bar)
                        .foregroundStyle(pillTint)
                    if formPrimaryShortcut {
                        HStack(spacing: metrics.spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "↵", style: .outline)
                        }
                    } else {
                        KeyCapChip(text: "↵", style: .outline)
                    }
                }
            }
            if showActions {
                BarButton(action: toggleActions) {
                    HStack(spacing: metrics.spacing.sm) {
                        Text(settings.text(PaletteKey.actions))
                            .font(metrics.typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: metrics.spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
            }
        }
        .padding(metrics.spacing.xs)
        .frosted(in: Capsule())
    }

    /// 打开 Actions 菜单的唯一路径，并采样其行所依赖的状态。
    private func openActions() {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
        // 键盘路径没有卡片坐标，旧坐标不得残留。
        actionsCardFrame = nil
        open(.actions, highlighting: 0)
    }

    /// 右键路径：记录卡片坐标，菜单悬挂在卡片正上方。
    private func openActionsAtCard(_ frame: CGRect) {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
        actionsCardFrame = frame
        open(.actions, highlighting: 0)
    }

    /// 「标签」筛选菜单的开关。
    private func toggleTagFilterMenu() {
        if openMenu == .clipboardTagFilter {
            closeMenus()
        } else {
            open(.clipboardTagFilter, highlighting: 0)
        }
    }

    /// 最右侧剪贴板设置菜单的开关。
    private func toggleClipboardSettings() {
        if openMenu == .clipboardSettings {
            closeMenus()
        } else {
            open(.clipboardSettings, highlighting: 0)
        }
    }

    private func toggleActions() {
        if openMenu == .actions {
            closeMenus()
        } else {
            openActions()
        }
    }

    /// 以当前生效的筛选打开，使当前值成为高亮行，如同弹出菜单。
    private func toggleClipboardFilter() {
        if openMenu == .clipboardFilter {
            closeMenus()
            return
        }
        let active = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
        open(.clipboardFilter, highlighting: active)
    }

    private func toggleFileSearchFilter() {
        if openMenu == .fileSearchFilter {
            closeMenus()
            return
        }
        let active = FileSearchFilter.allCases.firstIndex(of: vm.fileSearchFilter) ?? 0
        open(.fileSearchFilter, highlighting: active)
    }

    private func performFilterAction() -> Bool {
        switch PaletteFilterAction.resolve(
            collapsed: isCollapsed, mode: vm.mode,
            commandHasAccessory: extensionCommandScreen?.searchAccessory != nil)
        {
        case .extensionAccessory: toggleExtensionSearchAccessory()
        case .clipboardFilter: toggleClipboardFilter()
        case .fileSearchFilter: toggleFileSearchFilter()
        case .emojiCategory: toggleEmojiCategory()
        case .aiModel: toggleAIModel()
        case .ignored: return false
        }
        return true
    }

    private func toggleEmojiCategory() {
        if openMenu == .emojiCategory {
            closeMenus()
            return
        }
        let active = EmojiCategoryFilter.allCases.firstIndex(of: vm.emojiCategoryFilter) ?? 0
        open(.emojiCategory, highlighting: active)
    }

    /// 以下拉框当前选项打开，与剪贴板筛选的行为一致。
    private func toggleExtensionSearchAccessory() {
        if openMenu == .extensionAccessory {
            closeMenus()
            return
        }
        guard let accessory = extensionCommandScreen?.searchAccessory else { return }
        let value = extensions.accessorySelection(accessory)
        open(.extensionAccessory, highlighting: accessory.index(of: value))
    }

    /// 以当前选中的模型打开，与剪贴板筛选的高亮当前行行为一致。
    private func toggleAIModel() {
        if openMenu == .aiModel {
            closeMenus()
            return
        }
        let refreshTask = core.aiChatCoordinator.prepareModelSwitcher()
        open(.aiModel, highlighting: aiModelHighlight)
        Task { @MainActor in
            await refreshTask.value
            guard openMenu == .aiModel else { return }
            menuSelection = aiModelHighlight
            syncMenuPanel(presenting: false)
        }
    }

    private var quickAI: AIChatState { core.aiChats.quickAI }

    private var aiModelHighlight: Int {
        AIModelMenu.modelHighlight(coordinator: core.aiChatCoordinator, chat: quickAI)
    }

    private func toggleAIAttachments() {
        if openMenu == .aiAttachments {
            closeMenus()
            return
        }
        open(.aiAttachments, highlighting: 0)
    }

    private func toggleAIReasoning() {
        if openMenu == .aiReasoning {
            closeMenus()
            return
        }
        open(
            .aiReasoning,
            highlighting: AIModelMenu.reasoningHighlight(
                coordinator: core.aiChatCoordinator, chat: quickAI))
    }

    /// 每个头部菜单都声明自己的宽度，调整其中一个不会移动另一个。
    private func headerMenu(
        _ popover: PopoverMenuContent, width: CGFloat
    ) -> PaletteMenuContent {
        let filtered = popover.matching(ActionMenuSearchQuery(vm.menuQuery))
        return PaletteMenuContent(
            popover: filtered.content, selection: $menuSelection, width: width,
            search: PopoverMenu.Search(
                placeholder: settings.text(PaletteKey.menuSearchPlaceholder), placement: .top),
            onActivate: activateMenuItem, preferredSelection: filtered.bestMatch)
    }

    /// 所有打开路径都汇入此处，因此高亮总是被显式设定而非残留自上次。
    private func open(_ menu: OpenMenu, highlighting row: Int) {
        vm.menuQuery = ""
        menuSelection = row
        vm.noteMenuPresentation()
        openMenu = menu
        vm.menuOpen = true
    }

    /// 关闭当前菜单，并清空菜单查询与参数字段等所依赖的状态。
    private func closeMenus() {
        menuPanel.hide()
        openMenu = nil
        argumentOptionsField = nil
        vm.menuQuery = ""
        // 在此显式设置而非稍后同步：窗口委托会在本拍内读取它。
        vm.menuOpen = false
    }

    /// 菜单查询变化时重算高亮行，必要时刷新菜单窗口。
    private func menuQueryChanged() {
        guard menuOpen, let content = menuContent else { return }
        let next =
            content.preferredSelection
            ?? (0..<content.rowCount).first(where: content.isSelectable) ?? 0
        guard next == menuSelection else {
            menuSelection = next
            return
        }
        syncMenuPanel(presenting: false)
    }

    /// 依据决定菜单显示内容的两份状态来驱动菜单窗口。
    private func syncMenuPanel(presenting: Bool) {
        guard let content = menuContent, let corner = menuCorner else {
            menuPanel.hide()
            return
        }
        let view = content.view(corner)
        if presenting, let hostWindow {
            menuPanel.show(
                view, corner: corner, parent: hostWindow, core: core,
                clipPath: content.clipPath, motion: content.motion,
                onKeyDown: handleMenuPanelKey, onDismiss: closeMenus)
        } else {
            menuPanel.update(
                view, corner: corner, core: core, clipPath: content.clipPath,
                motion: content.motion)
        }
    }

    /// 处理菜单独立窗口中的按键：Escape、导航、回车与组合键。
    private func handleMenuPanelKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        let navigationModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            escapeMenu()
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where navigationModifiers.isEmpty:
            moveMenu(1)
            return true
        case .some(.upArrow) where navigationModifiers.isEmpty:
            moveMenu(-1)
            return true
        case .some(.carriageReturn), .some(.enter):
            let screen = screen
            let selection = selection(in: screen)
            if modifiers.contains([.command, .control]), screen.tertiary(at: selection) { return true }
            if modifiers.contains([.command, .shift]),
                screen.perform(.copyCalculation, at: selection)
            {
                return true
            }
            if modifiers.contains(.command) { return screen.secondary(at: selection) }
            if modifiers.contains(.option) {
                return screen.pasteKeepingWindowOpen(at: selection)
            }
            activateMenuItem(menuSelection)
            return true
        case .some(.tab), .some(.backTab):
            return true
        default:
            break
        }

        guard !modifiers.isDisjoint(with: [.command, .control]) else { return false }
        let character =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        if modifiers.contains(.control) {
            if character == "n" {
                moveMenu(1)
                return true
            }
            if character == "p" {
                moveMenu(-1)
                return true
            }
        }
        if modifiers.contains(.command), character == "k" {
            toggleActions()
            return true
        }
        if modifiers.contains(.command), character == "p", performFilterAction() { return true }
        if let shortcut = PaletteShortcut.resolve(
            command: modifiers.contains(.command), shift: modifiers.contains(.shift),
            option: modifiers.contains(.option), control: modifiers.contains(.control),
            isDeleteKey: false, matches: { character == String($0).lowercased() })
        {
            let screen = screen
            guard screen.perform(shortcut, at: selection(in: screen)) else { return false }
            if shortcut.closesMenu { closeMenus() }
            return true
        }
        if modifiers.contains(.command),
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        return false
    }

    /// Escape 的菜单行为：先清空菜单查询，查询已空则关闭菜单。
    private func escapeMenu() {
        if vm.menuQuery.isEmpty {
            closeMenus()
        } else {
            vm.menuQuery = ""
        }
    }

    /// 操作可能移除最后一个可见钉选；绝不让不可见的菜单继续占用输入。
    private func refreshActionsMenu() {
        guard openMenu == .actions else { return }
        guard menuContent != nil else {
            closeMenus()
            return
        }
        syncMenuPanel(presenting: false)
    }

    /// 行以索引寻址，因此在打开菜单下方暂存或拖入文件会重新排布行。
    private func refreshAttachmentsMenu() {
        guard openMenu == .aiAttachments else { return }
        guard let content = menuContent else {
            closeMenus()
            return
        }
        menuSelection = min(menuSelection, max(content.rowCount - 1, 0))
        syncMenuPanel(presenting: false)
    }

    /// 当前菜单应依附的角位置；无菜单时为 nil。
    private var menuCorner: MenuPanelCorner? {
        // 停靠横条贴近屏幕底边，菜单只能从面板上边缘向上悬挂。
        let docked = vm.mode == .clipboard
        switch openMenu {
        case .app: return docked ? .aboveLeading : .bottomLeading
        case .actions:
            if docked, let actionsCardFrame { return .aboveRect(actionsCardFrame) }
            return docked ? .aboveTrailing : .bottomTrailing
        case .argumentOptions: return .belowHeaderTrailing
        case .clipboardFilter: return .aboveTrailing
        case .clipboardSettings: return .aboveTrailing
        case .clipboardTags:
            // 二级菜单跟着它源出的卡片菜单。
            if let actionsCardFrame { return .aboveRect(actionsCardFrame) }
            return .aboveTrailing
        case .clipboardTagFilter: return .aboveLeading
        case .fileSearchFilter, .emojiCategory, .aiModel, .aiReasoning,
            .aiAttachments, .extensionAccessory:
            return .belowHeaderTrailing
        case nil: return nil
        }
    }

    // MARK: - Actions

    /// 所有重置都汇入此处，使同时触发的处理器无论以何种顺序执行都得到一致结果。
    private func land() {
        let landing = screen.landingSelection
        vm.selection = landing
        scroll = ScrollIntent(kind: landing == 0 ? .top : .center)
    }

    /// 在当前屏幕行范围内移动选中项 delta 行，并跟随滚动。
    private func move(_ delta: Int, in screen: any PaletteScreen) {
        let count = screen.rows.count
        guard count > 0 else { return }
        vm.selection = min(max(selection(count: count) + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    /// ↑/↓：屏幕有自己的移动逻辑时优先使用，否则在行间线性步进。
    private func moveVertically(_ delta: Int) -> KeyPress.Result {
        let screen = screen
        // 使用 ↑/↓ 编辑的控件会保留这两个键；只有 ⇥ 才能离开。
        guard !screen.ownsVerticalKeys(at: selection(in: screen)) else { return .ignored }
        // 移出命令会一并带走其参数字段，因此先把焦点交还搜索框。
        if argumentFocused != nil { returnFocusToSearchField() }
        guard let next = screen.move(delta, axis: .vertical, from: selection(in: screen)) else {
            move(delta, in: screen)
            return .handled
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return .handled
    }

    /// ←/→：仅由支持水平导航的屏幕消费，否则留给光标。
    private func moveHorizontally(_ delta: Int) -> Bool {
        let screen = screen
        guard let next = screen.move(delta, axis: .horizontal, from: selection(in: screen)) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    /// 在启动器与表情网格上被整体接管，使在端点处的按压不会落到光标上。
    private func movePinnedOrFavorite(
        _ delta: Int, modifiers: SwiftUI.EventModifiers
    ) -> KeyPress.Result? {
        guard modifiers.contains(.command), modifiers.contains(.option), !isCollapsed else {
            return nil
        }
        if let launcher = screen as? LauncherScreen {
            if launcher.moveFavorite(delta, at: selection(in: launcher)), menuOpen { closeMenus() }
            return .handled
        }
        guard let emoji = screen as? EmojiScreen else { return nil }
        emoji.movePin(delta, at: selection(in: emoji))
        return .handled
    }

    /// 将打开菜单的高亮移过不可停留的行，在两端停止（不循环）。
    private func moveMenu(_ delta: Int) {
        guard let content = menuContent else { return }
        var row = menuSelection + delta
        while (0..<content.rowCount).contains(row) {
            if content.isSelectable(row) {
                menuSelection = row
                return
            }
            row += delta
        }
    }

    /// 菜单行的唯一激活路径：执行其操作，然后关闭。
    private func activateMenuItem(_ index: Int) {
        guard let content = menuContent, (0..<content.rowCount).contains(index) else { return }
        guard content.isSelectable(index) else { return }
        // 在操作之前执行：若操作会打开窗口，它需要重新拿到面板的 key 状态，否则无法将其隐藏。
        closeMenus()
        // 鼠标点击某行会带走光标；菜单关闭后应把光标交还输入框。
        if argumentFocused == nil { searchFocused = true }
        content.activate(index)
    }

    /// 用于面板以令牌形式转交的组合键，在菜单打开时同样可用。
    private func performShortcut(_ shortcut: PaletteShortcut) {
        let screen = screen
        _ = screen.perform(shortcut, at: selection(in: screen))
    }

    /// 环上跳跃通常留下一级后退——除了回到环起点（启动器）的那一次跳跃。
    private func cycleMode() {
        switch PaletteTabAction.resolve(
            mode: vm.mode, aiEnabled: settings.aiEnabled,
            clipboardEnabled: settings.clipboardEnabled)
        {
        case .carryQuery(.launcher):
            vm.mode = .launcher
            vm.resetNavigation()
        case .carryQuery(let mode): vm.pushCarryingQuery(mode: mode)
        case .freshScreen(let mode): vm.push(mode: mode)
        case .ask: core.quickAICoordinator.ask(vm.query)
        }
    }

    /// Tab 先遍历屏幕自身的字段，再遍历行内参数，最后在模式环上循环。
    private func advanceTabFocus(backwards: Bool) {
        let screen = screen
        if screen.tab(at: selection(in: screen), backwards: backwards) { return }
        if let next = screen.tabTarget(from: selection(in: screen), backwards: backwards) {
            vm.selection = next
            scroll = ScrollIntent(kind: .follow)
            return
        }
        guard let accessory = headerAccessory, !accessory.fieldNames.isEmpty else {
            return cycleMode()
        }
        // 读取本地值：本拍内设置的 `@FocusState` 读回时仍是旧值。
        let next = accessory.field(after: argumentFocused, backwards: backwards)
        argumentFocused = next
        searchFocused = next == nil
    }

    /// 在行内字段末尾按 Right、开头按 Left，会延续与 Tab 相同的环。
    private func installHeaderArrowHandler(in window: NSWindow?) {
        guard let panel = window as? PalettePanel else { return }
        panel.onHeaderFieldBoundaryArrow = { boundary in
            guard !menuOpen, !vm.isControlListOpen, !isCollapsed,
                let accessory = headerAccessory, !accessory.fieldNames.isEmpty
            else { return false }
            switch boundary {
            case .leading:
                // 查询文本的左边缘保持正常光标行为；参数字段则后退一个焦点。
                guard argumentFocused != nil else { return false }
                advanceTabFocus(backwards: true)
            case .trailing:
                advanceTabFocus(backwards: false)
            }
            return true
        }
    }

    /// 字段编辑器重新获得焦点时 AppKit 会全选查询文本，这正是所需的重置。
    private func returnFocusToSearchField() {
        argumentFocused = nil
        searchFocused = true
    }

    /// 面板是为填写某一行的字段而打开的，因此光标起始于第一个为空的字段。
    private func focusPendingArgument() {
        guard vm.pendingArgumentEntryID != nil,
            let field = headerAccessory?.firstIncompleteField
        else { return }
        argumentFocused = field
        searchFocused = false
        vm.pendingArgumentEntryID = nil
    }

    /// `options=` 字段通过面板自身的菜单选择，从不直接键入。
    private func openArgumentOptions(_ field: String) {
        guard let accessory = headerAccessory, accessory.optionsMenu(field) != nil else { return }
        argumentFocused = field
        searchFocused = false
        argumentOptionsField = field
        open(.argumentOptions, highlighting: 0)
    }

    /// 扩展维护自己的栈，因此可能存在面板看不到的后退层级。
    private var hasBackStep: Bool {
        vm.canGoBack || (vm.mode == .extensionCommand && extensions.navigationDepth > 1)
    }

    /// 不承诺点击不会执行的返回：根屏幕是关闭而非后退。
    private var backHelp: String {
        let escape =
            hasBackStep
            ? settings.text(PaletteKey.backEscapeBack) : settings.text(PaletteKey.backEscapeClose)
        return String(format: settings.text(PaletteKey.backToRootFormat), escape)
    }

    /// 后退：扩展命令退出其屏幕，否则弹出导航栈，栈空则隐藏面板。
    private func goBack() {
        if vm.mode == .extensionCommand {
            core.extensionCoordinator.exitExtensionScreen()
            return
        }
        if !vm.pop() { core.paletteCoordinator.hidePalette() }
    }

    /// 激活当前选中项；有未填写的参数字段时，先把焦点移到该字段。
    private func activateSelection() {
        // 紧凑时没有可见的选中项，请通过 ⌘1–⌘5 或输入来启动。
        guard !isCollapsed else { return }
        // 未填写的字段会阻止启动；此时聚焦该字段，而非对填写一半的行执行操作。
        if let incomplete = headerAccessory?.firstIncompleteField {
            argumentFocused = incomplete
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

}

/// 面板的窗口内菜单。用单个可选值表达「至多一个打开」的不变量。
private enum OpenMenu {
    case actions
    case extensionAccessory
    /// `options=` 参数字段的选项，悬挂在头部中该 chip 所在位置的下方。
    case argumentOptions
    case app
    case clipboardFilter
    case clipboardSettings
    /// 打标签的二级菜单：名称输入、已有标签与底部色板。
    case clipboardTags
    /// 「标签」筛选菜单，选择按哪个标签过滤卡片行。
    case clipboardTagFilter
    case fileSearchFilter
    case emojiCategory
    case aiModel
    case aiReasoning
    case aiAttachments
}

/// 在自身 body 中读取可见性，使唤起不会重渲染面板的 body。
private struct PaletteHideObserver: ViewModifier {
    @Environment(PaletteState.self) private var vm
    let onHide: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: vm.isVisible) { _, visible in
            if !visible { onHide() }
        }
    }
}

/// 独立成修饰器：面板的 body 已达类型检查器的推导上限。
private struct SearchFieldHiding: ViewModifier {
    let hidden: Bool
    let apply: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: hidden) { _, hidden in apply(hidden) }
    }
}

/// 底部的菜单圆点；悬停状态存放在此，扫过时不会重渲染主体。
struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

/// 悬停状态存放在此，点亮箭头不会重渲染其周围的头部。
private struct HeaderBackButton: View {
    let help: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(metrics.typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: metrics.size.headerIconSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
        .help(help)
    }
}
