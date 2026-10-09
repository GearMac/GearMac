// 文件职责：调色板的共享可观察状态：当前模式、导航返回栈、查询/选中，以及悬停、菜单、输入法等交互标志。
// 分层：Model/State；@MainActor @Observable，面板的 SwiftUI 树与 Coordinator 读写同一实例。
import Foundation

/// 可返回的屏幕快照，携带足够状态使返回后看起来就像从未离开。
struct PaletteFrame: Equatable {
    let mode: PaletteMode
    let query: String
    let selection: Int
}

/// 在面板的 SwiftUI 树与协调器之间共享的调色板状态。
@MainActor
@Observable
final class PaletteState {
    var mode: PaletteMode = .launcher
    /// `mode` 之下的各屏幕，最内层在最后：召唤会开启新栈，导航则压入。
    private(set) var backStack: [PaletteFrame] = []
    var query: String = ""
    var selection: Int = 0
    /// 输入法持有标记文本时为 true，此时 `query` 为空。由面板发布。
    var isComposing = false
    /// 剪贴板屏幕的类型过滤器，每次召唤时随其余屏幕状态一起重置。
    var clipboardFilter: ClipboardFilter = .all
    /// 剪贴板屏幕的标签过滤器（标签名）；nil 表示不过滤，随屏幕一起重置。
    var clipboardTagFilter: String?
    /// 文件搜索屏幕的类型过滤器，与剪贴板一样每次召唤时重置。
    var fileSearchFilter: FileSearchFilter = .all
    /// 表情选择器当前可见的分类，随新打开的屏幕一起重置。
    var emojiCategoryFilter: EmojiCategoryFilter = .all
    /// nil 表示使用配置的默认值；缩放仅覆盖本次选择器会话。
    var emojiGridColumnsOverride: EmojiGridColumns?
    /// 文件搜索是否绘制 Quick Look 浮层；它跟随当前选中的行。
    var fileSearchQuickLook = false
    /// 移除窗口并不会卸载 SwiftUI 树，因此媒体预览需要此标志来停止播放。
    private(set) var isVisible = false
    /// 每次显示调色板时都改变，使搜索框可以重新获取焦点。
    var focusToken = UUID()
    /// 屏幕全新打开时递增，使其列表即使无其它变化也重新落位。
    var resetToken = UUID()
    /// 动作重排列表时递增，使高亮滚动回可见区域。
    var followToken = UUID()
    /// 动作重写查询时递增，使输入框落位时光标位于其后。
    private(set) var queryRewriteToken = UUID()
    /// AppKit 将 ⌘. 绑定到 `cancelOperation:`，因此字段编辑器会在 `onKeyPress` 前吞掉它。
    private(set) var pinChordToken = UUID()
    /// 当 AppKit 从物理数字行将 ⌘1…⌘0 解析为槽位号时递增。
    private(set) var favoriteSlotToken = UUID()
    /// `noteFavoriteSlot` 记录的最后槽位号，由 SwiftUI 层消费。
    private(set) var favoriteSlotIndex: Int?
    /// 为 ⌘0 / ⌘+ / ⌘- 递增，面板抢在字段编辑器之前认领这些键。
    private(set) var emojiGridZoomToken = UUID()
    /// `noteEmojiGridZoom` 记录的最后缩放，由 SwiftUI 层消费。
    private(set) var emojiGridZoom: EmojiGridZoom?
    /// 由紧凑栏的溢出发起，用于无查询直接展开；由 `prepare` 清除。
    var forceExpanded = false
    /// 粘贴目标，每次显示时镜像更新；`prepare` 重置屏幕而非此值。
    var pasteTarget: PasteTarget?
    /// 写入行的行内参数字段的值，以 `argumentKey` 为键。
    var commandArguments: [String: String] = [:]
    /// 调色板为填写某一行字段而打开时设置；头部会聚焦第一个空字段。
    var pendingArgumentEntryID: String?
    /// 快捷键将根搜索打开到的行，在查询为其名称时单独列出。
    var argumentEntryID: String?
    /// ⌘ 被*持续按住*后为 true，用于给收藏行编号。仅面板写入。
    private(set) var commandHeld = false
    /// 组合键是一次轻敲，因此编号会等待轻敲结束再接管尾随标签。
    @ObservationIgnored private var commandHoldTask: Task<Void, Never>?
    /// 表单字段拥有键盘时为 true，使调色板自己的文本键不介入。
    private(set) var isEditingField = false
    /// 屏幕内某个控件打开了列表时为 true，此时方向键与 ↵ 完全归它所有。
    private(set) var isControlListOpen = false
    /// 按下落在已打开控件列表之外时递增，列表由此得知该关闭。
    private(set) var controlListDismissToken = UUID()
    /// 仅当指针自主移动过后才为 true；不参与观察，因此不会触发重渲染。
    @ObservationIgnored private(set) var hoverHighlightArmed = false
    /// 高亮落下时递增，使点亮的行即使指针未离开也能清除。
    private(set) var hoverDisarmToken = UUID()
    /// 列表上次自主移动时指针的位置；移动量从此处测量。
    @ObservationIgnored private var hoverAnchor: CGPoint = .zero
    /// 用包含判定而非命中测试，因为重建中的层级结构会错过该字段。
    @ObservationIgnored var searchFieldFrame: CGRect = .zero
    /// 调色板菜单打开时为 true。参见 docs/features/palette.md#menu-open-input-freeze。
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var menuQuery = ""
    /// `menuOpen` 翻转时触发，使面板无需换焦点即可隐藏光标。
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?
    /// 全新一次展示会把长浮层重置回它打开时的行。
    private(set) var menuPresentationToken = UUID()

    /// 由窗口控制器通知可见性变化；不可见时关闭文件搜索的 Quick Look。
    func noteVisible(_ visible: Bool) {
        isVisible = visible
        // 移除窗口并不会卸载视图树，而预览不应比窗口活得更久。
        if !visible { fileSearchQuickLook = false }
    }

    /// 返回栈非空时为 true，表示可后退。
    var canGoBack: Bool { !backStack.isEmpty }

    /// 将 `mode` 作为根打开：全新屏幕，身后没有可返回的层级。
    func prepare(mode: PaletteMode) {
        backStack.removeAll()
        replace(mode: mode)
    }

    /// 就地替换屏幕，原有被它打开覆盖的屏幕仍保留在其后。
    func replace(mode: PaletteMode) {
        openScreen(mode)
        resetToken = UUID()
    }

    /// 在当前屏幕之上打开 `mode`，返回时会回到当前屏幕。
    func push(mode: PaletteMode) {
        backStack.append(PaletteFrame(mode: self.mode, query: query, selection: selection))
        replace(mode: mode)
    }

    /// 恢复下方屏幕；当前已是根屏幕时返回 false。
    func pop() -> Bool {
        guard let frame = backStack.popLast() else { return false }
        openScreen(frame.mode)
        query = frame.query
        selection = frame.selection
        // 不用 `resetToken`：再次让列表落位会丢弃此处恢复的选中项。
        followToken = UUID()
        return true
    }

    /// Tab 向环内更深一步：跨离的屏幕连同查询成为返回的一步。
    func pushCarryingQuery(mode: PaletteMode) {
        backStack.append(PaletteFrame(mode: self.mode, query: query, selection: selection))
        self.mode = mode
    }

    /// 搜索框只有一行，因此粘贴的多行换行符变成空格；重写过时返回 true。
    func collapseQueryLineBreaks() -> Bool {
        guard query.contains(where: \.isNewline) else { return false }
        query = query.split(whereSeparator: \.isNewline).joined(separator: " ")
        return true
    }

    /// Tab 在启动器上闭合环：它是根，身后不留下任何东西。
    func resetNavigation() {
        backStack.removeAll()
    }

    private func openScreen(_ mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        isComposing = false
        isEditingField = false
        isControlListOpen = false
        commandArguments = [:]
        pendingArgumentEntryID = nil
        argumentEntryID = nil
        clipboardFilter = .all
        clipboardTagFilter = nil
        fileSearchFilter = .all
        emojiCategoryFilter = .all
        emojiGridColumnsOverride = nil
        fileSearchQuickLook = false
        forceExpanded = false
        dropHoverHighlight()
        menuOpen = false
        menuQuery = ""
        focusToken = UUID()
    }

    /// 足够长，使 ⌘↵ 或 ⌘K 不会闪现编号；又足够短，感觉像一次揭示。
    private static let commandHoldDelay = Duration.milliseconds(400)

    /// U+0001 不会出现在条目 id 或参数名中，因此两半拼接后不歧义。
    nonisolated static func argumentKey(_ entryID: String, _ name: String) -> String {
        entryID + "\u{1}" + name
    }

    /// 记录一次 ⌘. 组合键，递增 token 供面板消费。
    func notePinChord() {
        pinChordToken = UUID()
    }

    /// 记录一次新的浮层展示，递增 token 使长浮层回到打开时的行。
    func noteMenuPresentation() {
        menuPresentationToken = UUID()
    }

    /// 重写查询文本，并递增 token 使输入框落位时光标位于其后。
    func rewriteQuery(_ text: String) {
        query = text
        queryRewriteToken = UUID()
    }

    /// 记录 ⌘1…⌘0 解析出的收藏槽位号。
    func noteFavoriteSlot(_ index: Int) {
        favoriteSlotIndex = index
        favoriteSlotToken = UUID()
    }

    /// 记录 ⌘0 / ⌘+ / ⌘- 解析出的网格缩放。
    func noteEmojiGridZoom(_ zoom: EmojiGridZoom) {
        emojiGridZoom = zoom
        emojiGridZoomToken = UUID()
    }

    /// 处理 ⌘ 按下/松开：按住超过延时后才把 `commandHeld` 置为 true。
    func noteCommandHeld(_ held: Bool) {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        guard held else {
            commandHeld = false
            return
        }
        guard !commandHeld else { return }
        commandHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commandHoldDelay)
            guard !Task.isCancelled else { return }
            self?.commandHeld = true
        }
    }

    /// 由将键盘交给自身控件的屏幕设置。
    func noteEditingField(_ editing: Bool) {
        guard editing != isEditingField else { return }
        isEditingField = editing
    }

    /// 由已打开自身列表的控件设置；调色板把所有导航键都留给它。
    func noteControlListOpen(_ open: Bool) {
        guard open != isControlListOpen else { return }
        isControlListOpen = open
    }

    /// 请求关闭已打开的控件列表（递增 dismiss token）。
    func dismissControlList() {
        guard isControlListOpen else { return }
        controlListDismissToken = UUID()
    }

    /// 指针发生移动；清空武装容差后重新点亮高亮。
    func notePointerMoved(to location: CGPoint) {
        guard !hoverHighlightArmed, HoverArming.isDeliberate(location, from: hoverAnchor) else {
            return
        }
        hoverHighlightArmed = true
    }

    /// 移动量从指针当前位置起算：漂移不算一次新选择。
    func disarmHoverHighlight(pointerAt location: CGPoint) {
        hoverAnchor = location
        dropHoverHighlight()
    }

    private func dropHoverHighlight() {
        guard hoverHighlightArmed else { return }
        hoverHighlightArmed = false
        hoverDisarmToken = UUID()
    }
}
