// 文件职责：片段功能的协调器，统一编排关键字监听、浏览器面板、编辑器跳转、文本注入与启用状态联动。
// 分层：Coordinator；持有 SnippetsStore 等依赖，所有入口都应经过这里，以保证「先确认再启用」。
import AppKit

/// 掌管片段流程：监听、浏览、编辑器跳转、文本投递与入口存在性。
@MainActor
final class SnippetCoordinator {
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: TextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// 通过回调外抛，使 `MessageHUDController` 仍由 `AppCore` 持有。
    private let showMessage: @MainActor (String, DialogTone) -> Void
    /// 用于弹出同意对话框，以及把 `pendingSnippetEdit` 交接给设置面板。
    private unowned let core: AppCore

    init(
        store: SnippetsStore,
        listener: SnippetKeywordListener,
        injector: TextInjector,
        clipboardStore: ClipboardStore,
        appIndex: AppIndex,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        showMessage: @escaping @MainActor (String, DialogTone) -> Void,
        core: AppCore
    ) {
        self.store = store
        self.listener = listener
        self.injector = injector
        self.clipboardStore = clipboardStore
        self.appIndex = appIndex
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.showMessage = showMessage
        self.core = core
    }

    // MARK: - Feature switch

    /// 在 Finder 中打开片段文件夹。
    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    /// 把片段库指向所选文件夹本身，不会从原文件夹迁移任何文件。
    func chooseSnippetsFolder() {
        guard
            let url = FolderPicker.choose(
                message: settings.text(SnippetsKey.chooseFolderMessage),
                startingAt: store.snippetsDirectory)
        else { return }
        settings.snippetsFolder = AppPaths.contentFolderSetting(for: url, named: "Snippets")
    }

    /// 清除自定义片段文件夹，恢复为默认目录。
    func resetSnippetsFolder() {
        settings.snippetsFolder = nil
    }

    /// 开关统一走这里，因此启用（同时代表同意）会先弹确认。
    func setSnippetsEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            settings.snippetsEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: settings.text(SnippetsKey.enableConfirmTitle),
                    message: settings.text(SnippetsKey.enableConfirmMessage),
                    symbol: "curlybraces",
                    confirmTitle: settings.text(SnippetsKey.enableConfirmAction), tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.snippetsEnabled = true
            // 该功能唯一的一次权限弹窗，由触发它的这次操作发起。
            Permissions.ensureAccessibility()
        }
    }

    // MARK: - Feature presence

    /// 任一开关关闭，功能就完全不进入启动器——包括结果行与命令。
    func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        let commands: Set<CommandID> = [.searchSnippets, .createSnippet]
        appIndex.setCommandsVisible(commands, settings.snippetsEnabled)
        appIndex.setCommandsListed(commands, settings.snippetsShowInLauncher)
        appIndex.updateSnippets(visible ? store.snippets : [])
    }

    /// 按开关状态收敛它负责的一切；关闭时按依赖顺序拆除。
    func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await store.start() }
            // 片段库未变化时不会发布快照，因此这里按 store 当前内容重新投影。
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        listener.stop()
        injector.cancelAutomaticExpansion()
        store.stop()
        applySnippetsLauncherPresence()
    }

    // MARK: - Browsing and editing

    /// 由开关控制是否打开浏览器，与 Search Files 打开前复查自身状态的做法一致。
    func showSnippets() {
        guard settings.snippetsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .snippets)
    }

    /// 打开 Snippets 设置页并让编辑器展示 `record`；nil 表示新建片段。
    func editSnippet(_ record: StoredSnippet?) {
        core.pendingSnippetEdit = SnippetEditRequest(record: record)
        settingsCoordinator.showSettings(tab: .snippets)
    }

    func showSnippetInFinder(_ record: StoredSnippet) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(record.fileURL)
    }

    // MARK: - Expansion

    /// `{clipboard offset=N}` 能回溯多深；更深的历史不符合片段使用习惯。
    private static let clipboardHistoryDepth = 20

    /// 启动关键字监听，匹配时尝试自动展开。
    func startSnippetKeywordListener() {
        // 闸门在 `beginAutomaticExpansion`，因此该回调内不再重复检查。
        listener.start(
            onUserActivity: { [weak self] in self?.injector.cancelAutomaticExpansion() },
            onMatch: { [weak self] id, keyword, keywordLength, target in
                guard let self,
                    let generation = self.injector.beginAutomaticExpansion(target: target)
                else { return }
                self.expandSnippet(
                    id: id,
                    target: target,
                    expectedKeyword: keyword,
                    keywordLength: keywordLength,
                    automaticGeneration: generation)
            })
    }

    /// 最近的复制内容，最新在前；实时剪贴板排在首位，轮询结果可能滞后。
    func clipboardHistoryForExpansion() -> [String] {
        var history = clipboardStore.items
            .filter { $0.kind == .text }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.clipboardHistoryDepth)
            .compactMap(\.text)
        if let current = NSPasteboard.general.string(forType: .string), current != history.first {
            history.insert(current, at: 0)
        }
        return history
    }

    /// 浏览器中的 ↵。必须在面板隐藏前读取目标窗口，与启动器内行为一致。
    func expandSnippetFromPalette(id: StoredSnippet.ID) {
        let target = windowController.previousTarget
        // 只有面板把焦点交还后，我们自己的编辑器才能重新被定位到。
        paletteCoordinator.hidePalette(restoreFocus: target?.ownEditor != nil)
        expandSnippet(id: id, target: target)
    }

    /// 快捷键作用在光标所在处；面板打开时，即面板所覆盖的那个目标。
    func expandSnippetFromHotKey(id: StoredSnippet.ID) {
        guard settings.snippetsEnabled, store.record(id: id)?.snippet.isEnabled == true else {
            return
        }
        if windowController.isVisible {
            expandSnippetFromPalette(id: id)
            return
        }
        // 我们自己的非编辑器窗口（如 Settings）没有可输入的光标位置。
        guard let target = InjectionTarget.current() else {
            showMessage(settings.text(SnippetsKey.clickTextField), .neutral)
            return
        }
        expandSnippet(id: id, target: target)
    }

    /// 展开指定片段；若缺少参数则先弹参数对话框，然后再投递文本。
    func expandSnippet(
        id: StoredSnippet.ID,
        target: InjectionTarget?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }
        // 仅交互路径需要这一步：必须在弹参数框之前失败，而不是之后。
        if automaticGeneration == nil {
            guard injector.prepareInteractiveExpansion(target: target) else { return }
        }
        let confirmation =
            record.snippet.showsConfirmation
            ? String(format: settings.text(SnippetsKey.inserted), record.snippet.name) : nil
        let context = injector.captureExpansionContext(
            target: target,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context)
        if !result.missingArguments.isEmpty {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation)
            return
        }
        completeSnippetExpansion(
            result,
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func promptSnippetArguments(
        record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        missingArgs: [SnippetTemplateEngine.MissingArgument],
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        // 已有对话框打开时该提示会被拒绝，且其结束不能清除这里的标志位。
        guard !core.isShowingDialog else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }
        listener.isPromptingForArguments = true
        Task {
            let arguments = await core.fillSnippetArguments(
                snippetName: record.snippet.name,
                arguments: missingArgs)
            listener.isPromptingForArguments = false
            guard let arguments else {
                injector.cancelArgumentPrompt(
                    automaticGeneration: automaticGeneration,
                    target: target)
                return
            }

            let result = SnippetTemplateEngine.expand(
                record,
                snippets: records,
                context: context,
                userArguments: arguments)
            completeSnippetExpansion(
                result,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation)
        }
    }

    private func completeSnippetExpansion(
        _ result: SnippetTemplateEngine.ExpansionResult,
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        injector.deliver(
            InjectedText(result.text, cursorOffsetFromEnd: result.cursorOffsetFromEnd),
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            onDelivered: { [weak self] in
                guard let self, let confirmation else { return }
                self.showMessage(confirmation, .success)
            })
    }
}
