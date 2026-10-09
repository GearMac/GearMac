// 文件职责：笔记功能的中央协调器：暴露视图所需状态、处理笔记的创建/选择/重命名/删除与窗口、切换器、标题菜单的编排。
// 分层：Coordinator；`@MainActor` 限定，作为 SwiftUI 环境对象连接 NotesStore/AppSettings 与各个窗口控制器。
import AppKit
import SwiftUI

/// 笔记功能的协调器。
@MainActor
@Observable
final class NotesCoordinator {
    /// 请求打开笔记面板时的目标形态。
    private enum Presentation {
        case editor
        case create
        case search
    }

    private let store: NotesStore
    /// 设置对象；同时经窗口控制器注入 SwiftUI 环境，供视图读取界面语言与状态。
    let settings: AppSettings
    private let appIndex: AppIndex
    private unowned let core: AppCore
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private lazy var switcherController = NoteSwitcherWindowController(
        coordinator: self)
    @ObservationIgnored private lazy var headingMenuController = NoteHeadingMenuWindowController(
        coordinator: self)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    /// 切换器当前是否处于展示状态。
    private(set) var isSwitcherPresented = false
    /// 切换器中当前选中的笔记 id。
    private(set) var switcherSelection: NoteID?
    /// 每次自增都会请求切换器重新聚焦搜索框。
    private(set) var switcherFocusRevision = 0
    /// 当前笔记的字数（UTF-16 码元数）。
    private(set) var characterCount = 0
    /// 当前选区的格式状态，供格式栏高亮。
    private(set) var formatting = NoteFormatting.plain
    /// 格式栏是否处于展开状态。
    private(set) var isFormattingBarExpanded: Bool
    /// 标题菜单是否处于展示状态。
    private(set) var isHeadingMenuPresented = false
    /// 按下会先关闭菜单、其按钮回调随后才触发，因此按钮不能再次重新打开它。
    @ObservationIgnored private var headingMenuWasOpenAtPress = false
    /// 标题按钮在面板翻转内容坐标系中的位置，由格式栏在布局时上报。
    @ObservationIgnored var headingButtonFrame: CGRect = .zero
    private var switcherRename = NoteSwitcherRenameState()
    private var presentationGeneration = 0

    @ObservationIgnored private let saveFormattingBarExpanded: @Sendable (Bool) -> Void

    /// 依赖注入的初始化器。
    init(
        store: NotesStore,
        settings: AppSettings,
        appIndex: AppIndex,
        core: AppCore,
        isFormattingBarExpanded: Bool = false,
        saveFormattingBarExpanded: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.core = core
        self.isFormattingBarExpanded = isFormattingBarExpanded
        self.saveFormattingBarExpanded = saveFormattingBarExpanded
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    /// 当前编辑器的输入快照（笔记 id、源文本与 epoch）。
    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    /// 是否存在活动笔记。
    var hasActiveNote: Bool { store.activeID != nil }
    /// UTF-16 码元数，直接来自 text storage：这是 TextKit 唯一能以 O(1) 返回的长度。
    var characterCountLabel: String {
        characterCount == 1
            ? settings.text(NotesKey.characterCountOne)
            : String(format: settings.text(NotesKey.characterCountMany), characterCount)
    }

    /// 绑定到搜索输入框的查询文本。
    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.store.searchQuery ?? "" },
            set: { [weak self] in self?.store.updateSearchQuery($0) })
    }

    /// 当前活动笔记的标题。
    var activeTitle: String { store.activeTitle }
    /// 是否开启 Markdown 渲染。
    var rendersMarkdown: Bool { settings.notesRendersMarkdown }
    /// 是否应显示格式栏（需同时开启渲染与格式栏设置）。
    var showsFormattingBar: Bool { settings.notesRendersMarkdown && settings.notesShowsFormattingBar }
    /// 是否正在搜索笔记。
    var isSearching: Bool { store.isSearching }
    /// 切换器可见的笔记列表：无查询时为全部摘要，否则为搜索结果。
    var visibleNotes: [NoteSummary] {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? store.summaries : store.searchResults.map(\.summary)
    }
    /// 当前正在重命名的笔记 id。
    var switcherEditingID: NoteID? { switcherRename.id }
    /// 切换器是否处于重命名状态。
    var isRenamingSwitcherNote: Bool { switcherRename.isActive }
    /// 绑定到重命名输入框的草稿文本。
    var switcherTitleDraftBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.switcherRename.draft ?? "" },
            set: { [weak self] in self?.switcherRename.updateDraft($0) })
    }

    /// 根据设置的开/关状态启用或停用笔记功能，并清理相关任务与界面。
    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setCommandsVisible([.showNotes, .createNote, .searchNotes], settings.notesEnabled)
        guard !settings.notesEnabled else { return }
        presentationGeneration &+= 1
        pendingPresentation = nil
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        closeHeadingMenu()
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: false)
        Task { [weak self] in
            guard let self else { return }
            _ = await store.flush()
            guard generation == enablementGeneration, !settings.notesEnabled else { return }
            store.stop()
        }
    }

    /// 退出前等待，使 300ms 的自动保存防抖不会吞掉最后一次编辑。
    func prepareForTermination() async {
        await store.flush()
    }

    /// 该命令是开关式，与其他面板一致：再次按下将收起面板。
    func toggle() {
        if windowController.isVisible {
            hide()
        } else {
            request(.editor)
        }
    }

    /// 请求创建一个新笔记并打开面板。
    func createNote() {
        request(.create)
    }

    /// 请求打开搜索/切换器。
    func searchNotes() {
        request(.search)
    }

    /// 打开笔记切换器；已打开时则仅把焦点重新拉回搜索框。
    func openSwitcher() {
        guard settings.notesEnabled, store.isLoaded else { return }
        closeHeadingMenu()
        if isSwitcherPresented {
            switcherFocusRevision &+= 1
            return
        }
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
        windowController.presentSwitcher(switcherController)
    }

    /// 关闭切换器，并可选择把焦点返回编辑器。
    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        switcherRename.cancel()
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        switcherController.hide()
        if focusEditor { windowController.focusEditor() }
    }

    /// 隐藏笔记面板，并请求保存后恢复焦点。
    func hide() {
        closeHeadingMenu()
        presentationGeneration &+= 1
        pendingPresentation = nil
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    /// 按优先级处理 Escape：先关标题菜单，其次关切换器，否则隐藏面板。
    func handleEscape() {
        if isHeadingMenuPresented {
            closeHeadingMenu()
        } else if isSwitcherPresented {
            closeSwitcher()
        } else {
            hide()
        }
    }

    /// 在可见笔记列表变化后校正切换器选中项。
    func reconcileSwitcherSelection() {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        if let switcherSelection, notes.contains(where: { $0.id == switcherSelection }) { return }
        switcherSelection = notes.first?.id
    }

    /// 在可见笔记中按偏移量循环移动切换器选中项。
    func moveSwitcherSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        guard let current = switcherSelection,
            let index = notes.firstIndex(where: { $0.id == current })
        else {
            switcherSelection = notes[offset < 0 ? notes.count - 1 : 0].id
            return
        }
        switcherSelection = notes[(index + offset + notes.count) % notes.count].id
    }

    /// 选中当前高亮的笔记。
    func selectSwitcherNote() {
        guard let switcherSelection else { return }
        select(switcherSelection)
    }

    /// 点击某行时选中对应的笔记。
    func activateSwitcherNote(_ id: NoteID) {
        switcherRename.cancel()
        select(id)
    }

    /// 重命名会修改文件名，因此输入框从文件名开始，而不用派生的标题行。
    func beginSwitcherRename(_ summary: NoteSummary) {
        switcherRename.begin(id: summary.id, title: summary.title)
    }

    /// 提交重命名并刷新搜索框焦点。
    func commitSwitcherRename() {
        guard let committed = switcherRename.commit() else { return }
        rename(committed.id, to: committed.title)
        switcherFocusRevision &+= 1
    }

    /// 取消重命名并刷新搜索框焦点。
    func cancelSwitcherRename() {
        guard switcherRename.isActive else { return }
        switcherRename.cancel()
        switcherFocusRevision &+= 1
    }

    /// 选中指定笔记（异步），成功后显示面板。
    func select(_ id: NoteID) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let selected = await store.select(id) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            guard permitsCompletion(generation) else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        }
    }

    /// 重命名指定笔记（异步），若为重命名当前笔记则刷新面板。
    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = renamedID
            if renamedID == store.activeID, permitsCompletion(generation) {
                windowController.show(focusEditor: false)
            }
        }
    }

    /// 删除切换器中当前选中的笔记。
    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    /// 处理删除快捷键；仅在切换器打开且未处于重命名时生效。
    func handleDeleteShortcut() -> Bool {
        guard isSwitcherPresented, !switcherRename.isActive else { return false }
        trashSwitcherSelection()
        return true
    }

    /// 确认后把指定笔记移到废纸篓，并调整切换器选中项。
    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.displayTitle else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await core.confirm(
                title: String(format: settings.text(NotesKey.trashConfirmTitle), title),
                message: settings.text(NotesKey.trashConfirmMessage),
                symbol: nil,
                confirmTitle: settings.text(NotesKey.trashConfirmAction))
            guard confirmed, settings.notesEnabled, !Task.isCancelled else { return }
            let switcherOrder = visibleNotes.map(\.id)
            let removed = await store.trash(id)
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            switcherSelection = NoteSwitcherSelection.replacement(
                afterRemoving: id,
                from: switcherOrder,
                fallback: store.activeID ?? store.summaries.first?.id)
            // 已无可浏览的笔记，由空状态接管窗口，而非显示空列表。
            if store.summaries.isEmpty { closeSwitcher(focusEditor: false) }
            guard permitsCompletion(generation) else { return }
            windowController.show(focusEditor: !isSwitcherPresented)
        }
    }

    /// 直接把 Notes 指向某个文件夹；不会把旧文件夹中的内容搬过去。
    func chooseNotesFolder() {
        guard
            let url = FolderPicker.choose(
                message: settings.text(NotesKey.chooseFolderMessage),
                startingAt: store.notesDirectory)
        else { return }
        settings.notesFolder = AppPaths.contentFolderSetting(for: url, named: "Notes")
    }

    /// 清除自定义笔记文件夹，恢复默认位置。
    func resetNotesFolder() {
        settings.notesFolder = nil
    }

    /// 在访达中显示当前笔记文件；无活动笔记时打开笔记文件夹。
    func openNotesFolder() {
        guard let fileURL = store.activeFileURL else {
            NSWorkspace.shared.open(store.notesDirectory)
            return
        }
        AppLauncher.showInFinder(fileURL)
    }

    /// 将窗口动画移动到屏幕右上角。
    func moveToTopRight() {
        windowController.moveToTopRight()
    }

    /// 接收编辑器的源文本变化并转发给存储层。
    func updateSource(_ source: String) {
        closeHeadingMenu()
        store.updateSource(source)
    }

    /// 更新字数统计（仅当输入与当前编辑器一致时）。
    func updateCharacterCount(_ input: NoteEditorInput, _ count: Int) {
        guard input == editorInput else { return }
        characterCount = count
    }

    /// 以 id 和 epoch 判定，而非整个输入：每次移动光标都比较长文本源并不划算。
    func updateFormatting(_ input: NoteEditorInput, _ formatting: NoteFormatting) {
        let current = editorInput
        guard input.id == current.id, input.epoch == current.epoch, formatting != self.formatting else {
            return
        }
        self.formatting = formatting
    }

    /// 对编辑器应用格式操作。
    func format(_ action: NoteEditAction) {
        windowController.format(action)
    }

    /// 收起格式栏会连带收起标题按钮，因此其菜单不能比它存活更久。
    func toggleFormattingBar() {
        guard showsFormattingBar else { return }
        closeHeadingMenu()
        // 显式使用动画，因为该快捷键会在任意视图事务之外改变状态。
        withAnimation(Self.barMotion) { isFormattingBarExpanded.toggle() }
        saveFormattingBarExpanded(isFormattingBarExpanded)
    }

    /// 格式栏展开/收起动画，遵循系统的减弱动态效果设置。
    private static var barMotion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : Theme.MenuMotion.chevronAnimation
    }

    /// 切换标题菜单的显示与隐藏。
    func toggleHeadingMenu() {
        guard !headingMenuWasOpenAtPress else {
            headingMenuWasOpenAtPress = false
            return
        }
        guard !isHeadingMenuPresented else { return closeHeadingMenu() }
        isHeadingMenuPresented = true
        windowController.presentHeadingMenu(headingMenuController)
    }

    /// 选择标题层级并应用样式。
    func chooseHeading(_ level: Int) {
        closeHeadingMenu()
        format(.setHeading(level: level))
    }

    /// 关闭标题菜单（若未打开则不做事）。
    func closeHeadingMenu() {
        guard isHeadingMenuPresented else { return }
        isHeadingMenuPresented = false
        headingMenuController.hide()
    }

    /// 窗口内鼠标按下时先关闭标题菜单并记录当时状态。
    func noteWindowMouseDown() {
        headingMenuWasOpenAtPress = isHeadingMenuPresented
        closeHeadingMenu()
    }

    /// 文本视图就绪时转交给窗口控制器。
    func editorReady(_ textView: NoteTextView) {
        windowController.editorReady(textView)
    }

    /// 请求某种展示形态：必要时先加载存储，再执行展示。
    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        closeHeadingMenu()
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            // 创建是它自己的加载：它所等待的集合就是它要写入的那个。
            let loaded = presentation == .create ? await store.create() : await store.start()
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled else { return }
            // 本任务刚创建的笔记已满足仍挂起的创建请求；绝不再创建第二个。
            if presentation == .create, pendingPresentation == .create {
                pendingPresentation = .editor
            }
            guard let next = pendingPresentation else { return }
            pendingPresentation = nil
            await present(next)
        }
    }

    /// 执行具体的展示形态（编辑器/创建/搜索）。
    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .create:
            let generation = presentationGeneration
            guard await store.create(), settings.notesEnabled, !Task.isCancelled,
                generation == presentationGeneration
            else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .search:
            // 切换器挂在笔记窗口下，因此该窗口必须先存在。
            windowController.show(focusEditor: false)
            openSwitcher()
        }
    }

    /// 更新的 show 或 hide 会剥夺旧操作把它加载的内容显示到屏幕上的权利。
    private func permitsCompletion(_ generation: Int) -> Bool {
        windowController.isVisible && generation == presentationGeneration
    }

    /// 同一时刻只允许一个集合操作：更新的请求会取消并取代进行中的请求。
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let generation = presentationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(generation)
            if self.operationID == id { self.operationTask = nil }
        }
    }

    /// 展示存储层上报的问题，上次展示完成后补展现挂起的问题。
    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await core.reportFailure(
                    title: settings.text(NotesKey.errorOpen),
                    message: failure.message(settings.language),
                    symbol: "text.page",
                    recovery: settings.text(NotesKey.errorRetry))
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await core.reportFailure(
                    title: settings.text(NotesKey.errorSave),
                    message: failure.message(settings.language),
                    symbol: "text.page",
                    recovery: settings.text(NotesKey.errorRetry))
                if retry { await store.retrySave() }
            case .operation(let failure):
                _ = await core.reportFailure(
                    title: settings.text(NotesKey.errorUpdate),
                    message: failure.message(settings.language),
                    symbol: "text.page",
                    recovery: nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }
}
