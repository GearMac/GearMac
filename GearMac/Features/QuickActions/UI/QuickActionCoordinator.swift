// 文件职责：作为所有 Quick Action 的统一编排入口，集中处理开关状态、自定义动作增删、执行、进度提示与结果面板。
// 分层：UI；@MainActor 限定的 Coordinator，负责编排 Model/Service，不在此实现具体副作用。
import AppKit
import Observation

/// 所有 Quick Action 的唯一统一入口，无论其由何种方式触发。
@MainActor
@Observable
final class QuickActionCoordinator {
    /// 记录笔记编辑器中的选区信息：编辑器、文档输入、选区范围与选中文本。
    private struct NoteSelection {
        let editor: NoteTextView
        let document: NoteEditorInput
        let range: NSRange
        let text: String
    }

    /// 执行目标：外部应用，或笔记编辑器内部的选区。
    private enum Target {
        case external(NSRunningApplication?)
        case note(NoteSelection)
    }

    private let settings: AppSettings
    private let store: QuickActionSettingsStore
    private let customActions: CustomQuickActionStore
    private let injector: TextInjector
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private let panels = QuickActionPanelController()
    private unowned let core: AppCore

    private static let launcherCommands = Set(BuiltInQuickAction.allCases.filter(\.isAvailable).map(CommandID.init))

    /// 同一时刻只允许一次执行：两次运行会争抢同一份选中文本，后者会覆盖前者的结果。
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// 取消是协作式的，因此被取消的运行不得隐藏较新运行时已显示的状态胶囊。
    @ObservationIgnored private var progressOwner: Int?

    /// 注入设置、各类存储、文本注入器、应用索引与面板控制器等依赖。
    init(
        settings: AppSettings, store: QuickActionSettingsStore,
        customActions: CustomQuickActionStore, injector: TextInjector,
        appIndex: AppIndex, hotKeys: HotKeyManager, favorites: FavoritesStore,
        visibility: VisibilityStore, ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.customActions = customActions
        self.injector = injector
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 启动器条目随开关显隐；Carbon 快捷键绑定始终保持注册。
    func applyEnabled() {
        appIndex.setCommandsVisible(Self.launcherCommands, settings.quickActionsEnabled)
        applyCustomQuickActionsPresence()
        guard settings.quickActionsEnabled else {
            cancel()
            core.applyInstalledAILifecycle()
            return
        }
        core.applyInstalledAILifecycle()
        store.resolveModel(
            appleIntelligenceAvailable: core.aiSettings.isAppleIntelligenceAvailable(),
            fallback: core.aiSettings.defaultModel)
        loadLanguages()
    }

    /// 启用即视为授权：读取选中文本与覆写它都需要辅助功能权限。
    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.quickActionsEnabled else { return }
        guard enabled else {
            settings.quickActionsEnabled = false
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: settings.text(QuickActionsKey.enableTitle),
                    message: settings.text(QuickActionsKey.enableMessage),
                    symbol: "wand.and.sparkles",
                    confirmTitle: settings.text(QuickActionsKey.enableContinue), tone: .neutral,
                    confirmRole: .standard)
            else { return }
            settings.quickActionsEnabled = true
            // 本功能唯一的权限提示，由发起该操作的手势处触发。
            Permissions.ensureAccessibility()
        }
    }

    /// 按 Quick Actions 是否启用，更新启动器索引里的自定义动作集合。
    func applyCustomQuickActionsPresence() {
        appIndex.setCustomQuickActions(
            settings.quickActionsEnabled ? customActions.actions : [])
    }

    // MARK: - The reader's own actions

    /// 只有在记录已落盘后才保存路由，因此保存被拒绝时两者都不会残留。
    func addCustomQuickAction(
        _ draft: CustomQuickAction, model: AIModelSelection?
    ) throws(CustomQuickActionError) {
        let action = try customActions.add(draft)
        store.setModelOverride(model, for: .custom(action))
    }

    /// 更新已有自定义动作，并同步其模型覆盖设置。
    func updateCustomQuickAction(
        _ draft: CustomQuickAction, model: AIModelSelection?
    ) throws(CustomQuickActionError) {
        try customActions.update(draft)
        store.setModelOverride(model, for: .custom(draft))
    }

    /// 设置指定自定义动作是否先预览结果再替换。
    func setPreviewsResult(_ previews: Bool, id: UUID) {
        do {
            try customActions.setPreviewsResult(previews, id: id)
        } catch {
            report(error)
        }
    }

    /// 经用户确认后删除自定义动作，并清理其关联引用。
    func deleteCustomQuickAction(id: UUID) async {
        guard let action = customActions.action(id: id) else { return }
        guard
            await core.confirm(
                title: String(
                    format: settings.text(QuickActionsKey.deleteTitle), action.name),
                message: settings.text(QuickActionsKey.deleteMessage),
                symbol: action.symbol,
                confirmTitle: settings.text(QuickActionsKey.deleteAction))
        else { return }
        // 仅在条目已移除后才解绑，因此保留下来的记录不会丢失其快捷键。
        do {
            guard let removed = try customActions.remove(id: id) else { return }
            removeCustomQuickActionReferences(removed)
        } catch {
            report(error)
        }
    }

    /// 以危险提示向用户报告自定义动作保存失败。
    private func report(_ error: CustomQuickActionError) {
        Task {
            await core.showNotice(
                title: settings.text(QuickActionsKey.errorSaveChange),
                message: error.message(settings.language),
                symbol: CustomQuickAction.sfSymbol, tone: .danger)
        }
    }

    /// 清理已删除动作关联的快捷键、模型覆盖、收藏、可见性、别名与排序记录。
    private func removeCustomQuickActionReferences(_ action: CustomQuickAction) {
        let hotKeyAction = HotKeyAction.quickAction(id: action.id)
        if hotKeys.recordingAction == hotKeyAction { hotKeys.recordingAction = nil }
        hotKeys.setBinding(nil, for: hotKeyAction)
        store.setModelOverride(nil, for: .custom(action))
        favorites.remove(keys: [action.entryID])
        visibility.removeItemKeys([action.entryID])
        aliases.removeKeys([action.entryID])
        ranking.reset(itemKey: action.entryID)
    }

    /// 按 id 运行指定的自定义动作。
    func run(id: UUID) {
        guard let action = customActions.action(id: id) else { return }
        run(.custom(action))
    }

    /// 解析注入目标并启动一次 Quick Action 执行。
    func run(_ action: QuickAction) {
        guard settings.quickActionsEnabled, running == nil else { return }
        let source =
            paletteCoordinator.isVisible
            ? InjectionTarget.behindPalette(
                ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
            : InjectionTarget.current()
        let target: Target
        if let editor = source?.ownEditor as? NoteTextView {
            target = .note(
                NoteSelection(
                    editor: editor, document: core.notesCoordinator.editorInput,
                    range: editor.selectedRange(), text: editor.injectableSelection))
        } else {
            target = .external(paletteCoordinator.targetApp)
        }
        if paletteCoordinator.isVisible {
            paletteCoordinator.hidePalette(restoreFocus: source?.ownEditor is NoteTextView)
        }
        start { [weak self] in await self?.begin(action, target: target) }
    }

    /// 取消当前执行、隐藏进度并关闭结果面板。
    func cancel() {
        generation += 1
        running?.cancel()
        running = nil
        hideProgress(ownedBy: progressOwner)
        panels.dismiss()
    }

    /// 通过代次计数，避免已被取代的任务在结束时清空更新的句柄。
    private func start(_ work: @escaping @MainActor () async -> Void) {
        generation += 1
        let mine = generation
        running?.cancel()
        running = Task { [weak self] in
            await work()
            guard let self, mine == self.generation else { return }
            self.running = nil
        }
    }

    /// 读取选中文本并构造面板状态，随后按配置决定是否预览及执行。
    private func begin(_ action: QuickAction, target: Target) async {
        let selection: String
        do {
            switch target {
            case .external(let app):
                selection = try await QuickActionRunner.selection(in: app, using: injector)
            case .note(let note):
                selection = try QuickActionRunner.accepted(note.text)
            }
        } catch let failure as QuickActionFailure {
            reportRefusal(failure)
            return
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        let state = QuickActionPanelState(
            action: action, original: selection, targetLanguage: targetLanguage)
        let previews = store.settings.previewsResult(action)
        if previews { present(state, target: target) }
        await perform(state, target: target, previewing: previews)
    }

    /// 缺失的权限无法从转瞬即逝的状态胶囊中修复，因此改为弹出对话框。
    private func reportRefusal(_ failure: QuickActionFailure) {
        guard failure.opensAccessibilitySettings else {
            core.showMessage(failure.message(settings.language), tone: .danger)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.reportFailure(
                    title: settings.text(QuickActionsKey.refusalTitle),
                    message: settings.text(QuickActionsKey.refusalMessage),
                    symbol: "wand.and.sparkles",
                    recovery: settings.text(QuickActionsKey.refusalOpenSystemSettings))
            else { return }
            Permissions.openAccessibilitySettings()
        }
    }

    /// 生成结果并交付：预览模式下只更新面板，否则写回目标选区。
    private func perform(
        _ state: QuickActionPanelState, target: Target, previewing: Bool
    ) async {
        if state.action == .builtIn(.decide) {
            await performDecisions(state)
            return
        }
        do {
            let text = try await produce(state, previewing: previewing)
            guard !Task.isCancelled else { return }
            state.finish(text)
            if previewing { return }
            deliver(text, to: target, action: state.action)
        } catch is CancellationError {
            return
        } catch let error as TextTranslator.Failure where error.needsDownload {
            // HUD 无法说明下载入口在哪里，因此这里必须改为面板。
            if !previewing { present(state, target: target) }
            state.requireLanguageDownload()
        } catch {
            report(error, state: state, previewing: previewing)
        }
    }

    /// 没有面板时屏幕上没有任何元素表明模型正在工作，因此由状态胶囊来提示。
    private func produce(
        _ state: QuickActionPanelState, previewing: Bool
    ) async throws -> String {
        guard !previewing else { return try await generate(state, streaming: true) }
        let mine = generation
        progressOwner = mine
        core.showProgress(
            state.action.localizedProgressTitle(settings.language),
            onCancel: { [weak self] in self?.cancel() })
        defer { hideProgress(ownedBy: mine) }
        return try await generate(state, streaming: false)
    }

    /// 仅当进度由当前代次持有时才隐藏进度提示。
    private func hideProgress(ownedBy owner: Int?) {
        guard let owner, progressOwner == owner else { return }
        progressOwner = nil
        core.hideProgress()
    }

    /// 调用翻译框架或 AI provider 生成结果；流式模式下逐段追加到面板状态。
    private func generate(
        _ state: QuickActionPanelState, streaming: Bool
    ) async throws -> String {
        if state.action.usesTranslationFramework {
            return try await TextTranslator.translate(state.original, to: state.targetLanguage)
        }
        let provider = try core.quickActionProvider(for: state.action)
        return try await QuickActionRunner.run(
            state.action, selection: state.original, using: provider,
            instructionOverride: store.settings.instructionOverride(for: state.action),
            onDelta: { delta in
                guard streaming else { return }
                state.append(delta)
            })
    }

    /// Decide 的专用路径：不经 AIProvider，直接把选中文本交给 Decisions 网关。
    /// 面板在 begin 里已随 alwaysPreviews 先行呈现，这里只需把答案落进面板状态。
    private func performDecisions(_ state: QuickActionPanelState) async {
        do {
            let questions = core.aiSettings.decisionsQuestions
            try questions.validated()
            let response = try await core.decisionsClient().decide(
                state.original, questions: questions)
            guard !Task.isCancelled else { return }
            state.finishDecisions(response.answers, usage: response.usage)
        } catch is CancellationError {
            return
        } catch {
            state.fail(decisionsMessage(error))
        }
    }

    /// Decide 失败文案：问题集与客户端错误按界面语言取，其余保留原文。
    private func decisionsMessage(_ error: Error) -> String {
        if let questionError = error as? DecisionsQuestionError {
            return questionError.message(settings.language)
        }
        if let clientError = error as? DecisionsClient.ClientError {
            return clientError.message(settings.language)
        }
        return error.localizedDescription
    }

    /// 若替换始终无法落地，回复就会丢失，因此用剪贴板将其保留。
    private func deliver(_ text: String, to target: Target, action: QuickAction) {
        let onDelivered: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.core.showMessage(
                String(
                    format: self.settings.text(QuickActionsKey.messageApplied),
                    action.localizedTitle(self.settings.language)))
        }
        let onFailed: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Paster.copyPlainText(text)
            self.core.showMessage(
                String(
                    format: self.settings.text(QuickActionsKey.messageCopiedInstead),
                    action.localizedTitle(self.settings.language)),
                tone: .danger)
        }
        switch target {
        case .external(let app):
            injector.replaceSelection(
                with: text, in: app, onDelivered: onDelivered, onFailed: onFailed)
        case .note(let note):
            guard core.notesCoordinator.editorInput == note.document,
                note.editor.window?.isVisible == true,
                note.editor.replaceUnchangedSelection(
                    with: text, source: note.document.source, range: note.range)
            else { onFailed(); return }
            onDelivered()
        }
    }

    /// 用户看不到的失败，等同于一个静默失效的快捷键。
    private func report(_ error: Error, state: QuickActionPanelState, previewing: Bool) {
        let message =
            (error as? TextTranslator.Failure)?.message(settings.language)
            ?? error.localizedDescription
        guard previewing else {
            core.showMessage(message, tone: .danger)
            return
        }
        state.fail(message)
    }

    /// 通过面板控制器展示结果面板，并接入重新翻译与替换回调。
    private func present(_ state: QuickActionPanelState, target: Target) {
        panels.present(
            state,
            settings: settings,
            metrics: settings.interfaceSize.metrics,
            languages: offeredLanguages,
            onRetranslate: { [weak self] language in
                state.targetLanguage = language
                self?.rerun(state, target: target)
            },
            onReplace: { [weak self] text in
                self?.deliver(text, to: target, action: state.action)
            })
    }

    /// 重置面板状态并以预览模式重新执行。
    private func rerun(_ state: QuickActionPanelState, target: Target) {
        state.restart()
        start { [weak self] in await self?.perform(state, target: target, previewing: true) }
    }

    /// 目标语言：优先取设置中的语言，为空时回退到系统当前语言。
    private var targetLanguage: Locale.Language {
        let stored = store.settings.targetLanguage
        guard !stored.isEmpty else { return Locale.current.language }
        return Locale.Language(identifier: stored)
    }

    /// 被观察而非忽略：它在面板绘制完成后才到达，选择器必须能感知到变化。
    private(set) var offeredLanguages: [Locale.Language] = []
    /// 正在进行的受支持语言加载任务。
    @ObservationIgnored private var languageLoad: Task<Void, Never>?

    /// 加载翻译框架的受支持语言列表，仅执行一次。
    func loadLanguages() {
        guard offeredLanguages.isEmpty, languageLoad == nil else { return }
        languageLoad = Task { [weak self] in
            let languages = await TextTranslator.supportedLanguages()
            self?.offeredLanguages = languages
        }
    }
}

/// 补充 `TextTranslator.Failure` 在 Quick Action 场景下需要的判断。
extension TextTranslator.Failure {
    /// 该失败是否因语言包未安装而需要下载。
    var needsDownload: Bool {
        if case .notInstalled = self { return true }
        return false
    }
}
