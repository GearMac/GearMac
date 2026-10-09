// 文件职责：AI Chat 的统一动作入口：把窗口与 Quick AI 两个入口的发送、重命名、附件、模型选择、工具与上下文统计编排到状态和设置上。
// 分层：Coordinator；@MainActor，持有 AppCore、窗口与各 Store 的引用并负责副作用编排，视图只调用它。
import AppKit
import SwiftUI

/// 两个入口共用的聊天动作，外加 AI Chat 窗口自身的动作；视图的所有状态变更都经此路由。
@MainActor
@Observable
final class AIChatCoordinator {
    let chats: AIChatSurfacesState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore
    private let window: AppWindowController
    /// 正在请求标题的聊天，避免紧接的第二次回复重复请求。
    @ObservationIgnored private var naming: [UUID: Task<Void, Never>] = [:]

    /// 组装协调器：接上各 Store 与 AppCore，并创建 AI Chat 窗口。
    init(
        chats: AIChatSurfacesState, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.chats = chats
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
        window = AppWindowController(
            title: settings.text(AIKey.windowTitle), contentSize: Theme.Size.aiChatWindow,
            minimumSize: Theme.Size.aiChatWindowMinimum, resizable: true,
            autosaveName: "AIChatWindow", activation: core.activationPolicy, closesOnEscape: true)
        chats.onReplyFinished = { [weak self] chat in self?.nameIfNeeded(chat) }
    }

    /// 取本地化文案；聊天视图通过协调器读取，避免各自注入 AppSettings。
    func text<K: LocalizableKey>(_ key: K) -> String { settings.text(key) }

    /// 当前界面语言，供无法读取环境的嵌套视图使用。
    var language: AppLanguage { settings.language }

    /// AI 开关变化时调用：更新命令可见性、取消后台标题任务，并加载或关闭历史。
    func applyEnabled() {
        appIndex.setCommandsVisible([.aiChat, .quickAI], settings.aiEnabled)
        guard settings.aiEnabled else {
            for request in naming.values { request.cancel() }
            naming = [:]
            // 在句柄关闭之前：取消进行中的回复会保存它结束的那次会话。
            chats.reset()
            window.close()
            core.applyInstalledAILifecycle()
            core.chatHistory.close()
            core.quickAICoordinator.leave()
            return
        }
        core.applyInstalledAILifecycle()
        // 与剪贴板的读取一样延后于启动路径；历史会在其后方逐步填充。
        Task {
            core.chatHistory.load()
            // 只在启用分支内执行：AI 关闭时该文件不被触碰，无论它变得多陈旧。
            applyRetention()
        }
    }

    /// 按保留策略裁剪历史记录；AI 关闭或未配置保留期时不做任何事。
    func applyRetention() {
        guard settings.aiEnabled,
            let cutoff = core.aiSettings.retention.cutoff(from: Date())
        else { return }
        core.chatHistory.prune(before: cutoff)
    }

    // MARK: - The window

    /// 重新打开时展示上次的内容：会话属于 `AppCore`，而非窗口本身。
    func showWindow() {
        guard settings.aiEnabled else { return }
        prepareForChat()
        guard !window.focus() else { return }
        // 每个窗口一个查找状态：由窗口 chrome 的搜索框写入，转录区读取。
        let find = ChatFindState()
        window.show(chrome: AIChatWindowChrome(coordinator: self, chats: chats, find: find)) {
            AIChatSplitViewController(
                sidebar: AIChatSidebarView().environment(self),
                detail: AIChatDetailView().environment(self).environment(find))
        }
    }

    /// 窗口为 key 时先关闭它，否则打开。
    func toggleWindow() {
        guard !closeWindowIfKey() else { return }
        showWindow()
    }

    /// 窗口中的视图通过协调器读取这些对象，而不会直接访问 `AppCore`。
    var history: ChatHistoryStore { core.chatHistory }
    var aiSettings: AISettingsStore { core.aiSettings }
    var dictation: DictationCoordinator { core.dictationCoordinator }

    /// 把已存在的窗口带到前台；返回是否成功聚焦。
    func focusExisting() -> Bool {
        window.focus()
    }

    /// 窗口为 key 时 ⌘Q 的接管目标；返回 false 表示把该快捷键交还给 Settings。
    func closeWindowIfKey() -> Bool {
        guard NSApp.keyWindow?.identifier == AIChatWindowChrome.windowIdentifier else {
            return false
        }
        window.close()
        return true
    }

    /// 在窗口中开始一条新聊天。
    func newChat() {
        chats.newWindowChat()
    }

    /// 在窗口中打开指定聊天；无法打开时向用户提示。
    func openChat(id: UUID) {
        guard chats.openInWindow(id: id) else {
            core.showMessage(settings.text(AIKey.chatOpenFailed), tone: .danger)
            return
        }
    }

    /// Quick AI 的 ⌘J：会话、已暂存文件与输入到一半的内容一并迁移过来。
    func continueInWindow(draft: String) {
        chats.continueQuickAIInWindow(draft: draft)
        showWindow()
    }

    /// 尚无消息的聊天还未保存，因此没有可置顶、复制或删除的内容。
    func isSaved(_ chat: AIChatState) -> Bool {
        core.chatHistory.conversation(id: chat.session.id) != nil
    }

    /// 该聊天是否已置顶。
    func isPinned(_ chat: AIChatState) -> Bool {
        core.chatHistory.conversation(id: chat.session.id)?.isPinned == true
    }

    /// 切换指定聊天的置顶状态。
    func togglePin(id: UUID) {
        guard let conversation = core.chatHistory.conversation(id: id) else { return }
        core.chatHistory.setPinned(!conversation.isPinned, id: id)
    }

    /// 以给定标题重命名指定聊天。
    func rename(id: UUID, to title: String) {
        core.chatHistory.rename(id: id, to: title)
    }

    /// 窗口与侧边栏显示的标题，包含重命名后的结果。
    func title(of chat: AIChatState) -> String {
        core.chatHistory.conversation(id: chat.session.id)?.displayTitle ?? chat.session.title
    }

    /// 把指定聊天的 Markdown 转录复制到剪贴板。
    func copyChat(id: UUID) {
        guard let markdown = markdownTranscript(of: id) else { return }
        Paster.copyPlainText(markdown.text)
        core.showMessage(settings.text(AIKey.chatCopied))
    }

    /// 与 Copy Chat 相同的 Markdown 内容，写入用户选择的位置。
    func exportChat(id: UUID) {
        guard let markdown = markdownTranscript(of: id) else { return }
        let panel = NSSavePanel()
        // 标题可能包含斜杠或冒号，而文件名不能包含它们。
        panel.nameFieldStringValue = markdown.title.replacing(/[\/:]/, with: "-") + ".md"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(markdown.text.utf8).write(to: url, options: .atomic)
        } catch {
            core.showMessage(settings.text(AIKey.chatExportFailed), tone: .danger)
        }
    }

    /// 只要任一入口持有该聊天即取其实时状态，因此仍在到达的回答也会包含在内。
    private func markdownTranscript(of id: UUID) -> (title: String, text: String)? {
        guard let session = chats.holder(of: id)?.session ?? core.chatHistory.session(id: id)
        else { return nil }
        let title = core.chatHistory.conversation(id: id)?.displayTitle ?? session.title
        return (title, session.markdownTranscript(title: title))
    }

    /// 二次确认后删除指定聊天。
    func deleteChat(id: UUID) async {
        let title = core.chatHistory.conversation(id: id)?.displayTitle ?? settings.text(AIKey.thisChat)
        guard
            await core.confirm(
                title: settings.text(AIKey.deleteChatTitle),
                message: String(
                    format: settings.text(AIKey.deleteChatMessage), title),
                symbol: "trash", confirmTitle: settings.text(AIKey.deleteConfirm))
        else { return }
        core.chatGPTSubscription.turns.discardConversation(id: id)
        chats.delete(id: id)
    }

    /// 二次确认后删除所有未置顶的聊天。
    func deleteAllChats() async {
        guard
            await core.confirm(
                title: settings.text(AIKey.deleteAllTitle),
                message: settings.text(AIKey.deleteAllMessage),
                symbol: "trash", confirmTitle: settings.text(AIKey.deleteAll))
        else { return }
        for conversation in core.chatHistory.conversations where !conversation.isPinned {
            core.chatGPTSubscription.turns.discardConversation(id: conversation.id)
        }
        chats.deleteAll()
    }

    // MARK: - Titles

    /// 首次发送时请求标题，若失败则在回答结束后重试，且绝不覆盖用户的重命名。
    private func nameIfNeeded(_ chat: AIChatState) {
        let session = chat.session
        guard let conversation = core.chatHistory.conversation(id: session.id),
            conversation.customTitle == nil, conversation.generatedTitle == nil,
            let description = ChatTitle.description(of: session),
            naming[session.id] == nil
        else { return }
        let selection = model(for: chat)
        let servers = titleServers(for: chat, on: selection)
        naming[session.id] = Task {
            let title = await self.title(
                describing: description, with: selection, servers: servers)
            // 取消者已经清掉了该条目，而它现在可能属于更新的请求。
            guard !Task.isCancelled else { return }
            naming[session.id] = nil
            if let title { core.chatHistory.setGeneratedTitle(title, id: session.id) }
        }
    }

    /// Codex 的模型列表在启动时固定，因此标题请求借用回复所用的服务器，也可能一个都不调用。
    private func titleServers(
        for chat: AIChatState, on selection: AIModelSelection?
    ) -> AIToolServerSession? {
        guard case .codex? = selection else { return nil }
        let scope = chat.session.messages.first { $0.role == .user }?.toolScope
        return toolServers(for: chat, scopedTo: scope).map { borrowed in
            AIToolServerSession(rounds: 1, servers: borrowed.servers) { _ in false }
        }
    }

    /// Claude 的 CLI 会自行命名会话；其他路由则通过一次旁路请求来获取标题。
    private func title(
        describing description: String, with selection: AIModelSelection?,
        servers: AIToolServerSession?
    ) async -> String? {
        // Decisions 路由只会把描述当作判定输入，拿不到标题；留给首问兑底。
        if let selection, selection.isDecisionsModel { return nil }
        if case .claude? = selection, let title = await core.installedAI.claudeTitle(for: description) {
            return title
        }
        guard let selection,
            let provider = try? AIProviderFactory.make(
                selection: selection, settings: core.aiSettings,
                subscription: core.chatGPTSubscription, installedAI: core.installedAI,
                toolServers: servers)
        else { return nil }
        let request = AIRequest(
            instructions: ChatTitle.instructions,
            messages: [AIMessage(role: .user, text: description)])
        var text = ""
        do {
            for try await event in provider.stream(request) {
                if case .text(let delta) = event { text += delta }
                if case .finished = event { break }
            }
        } catch {
            return nil
        }
        return ChatTitle.sanitize(text)
    }

    // MARK: - Either surface

    /// 发送一条用户消息；AI 关闭、路由不可用或无可发送内容时返回 false。
    @discardableResult
    func send(_ input: String, in chat: AIChatState) -> Bool {
        guard settings.aiEnabled else { return false }
        do {
            let address = MCPComposerAddress.parse(input, slugs: core.mcpCoordinator.slugs)
            let sent = chat.send(
                address.rest, using: try provider(for: chat, scopedTo: address.slug),
                model: model(for: chat), webSearch: webSearch(for: chat),
                instructions: instructions, contextBudget: contextBudget(for: chat),
                toolScope: address.slug)
            // 在回答流式输出期间就发起命名，使侧边栏在回复结束前已有标题。
            if sent { nameIfNeeded(chat) }
            return sent
        } catch {
            chat.report(error.localizedDescription)
            return false
        }
    }

    /// 用当前选中的模型、向问题指定的服务器重新提问。
    func regenerate(in chat: AIChatState) {
        guard settings.aiEnabled else { return }
        let scope = chat.session.messages.last { $0.role == .user }?.toolScope
        do {
            chat.regenerate(
                using: try provider(for: chat, scopedTo: scope),
                model: model(for: chat), webSearch: webSearch(for: chat),
                instructions: instructions, contextBudget: contextBudget(for: chat))
        } catch {
            chat.report(error.localizedDescription)
        }
    }

    private func webSearch(for chat: AIChatState) -> Bool {
        core.aiSettings.webSearchEnabled && capabilities(for: chat).webSearch
    }

    private var instructions: String? {
        AIInstructions.compose(
            userPrompt: core.aiSettings.systemPrompt,
            isEnabled: core.aiSettings.systemPromptEnabled)
    }

    /// 本轮请求的路由与工具：自带客户端的 CLI 直接拿到服务器，其余走工具循环。
    private func provider(for chat: AIChatState, scopedTo slug: String?) throws -> any AIProvider {
        guard model(for: chat)?.runsItsOwnTools == true else {
            return toolAware(try provider(for: chat), scopedTo: slug, in: chat)
        }
        return try provider(for: chat, toolServers: toolServers(for: chat, scopedTo: slug))
    }

    /// 与 `tools(for:scopedTo:)` 相同的收窄逻辑，面向自行启动服务器的客户端。
    private func toolServers(for chat: AIChatState, scopedTo slug: String?) -> AIToolServerSession? {
        guard capabilities(for: chat).tools, chat.toolScope.isEnabled else { return nil }
        let excluded = chat.toolScope.excluded
        let chatID = chat.session.id
        let mcp = core.mcpCoordinator
        return AIToolServerSession(rounds: core.aiSettings.toolRounds.limit) {
            await mcp.toolServers(scopedTo: slug).filter { !excluded.contains($0.handle) }
        } consent: { call in
            await mcp.permit(call, in: chatID)
        }
    }

    /// 只有聊天会把路由包进工具循环；文本改写没有任何工具可调用。
    private func toolAware(
        _ provider: any AIProvider, scopedTo slug: String?, in chat: AIChatState
    ) -> any AIProvider {
        let tools = tools(for: chat, scopedTo: slug)
        guard capabilities(for: chat).tools, !tools.isEmpty else { return provider }
        let chatID = chat.session.id
        return AIToolLoopProvider(
            base: provider, tools: tools, maxRounds: core.aiSettings.toolRounds.limit
        ) { [mcp = core.mcpCoordinator] call in
            await mcp.invoke(call, in: chatID)
        }
    }

    /// `@server` 会进一步收窄本轮范围，但绝不会超出聊天工具菜单已关闭的部分。
    private func tools(for chat: AIChatState, scopedTo slug: String?) -> [AITool] {
        guard chat.toolScope.isEnabled else { return [] }
        let excluded = chat.toolScope.excluded
        return core.mcpCoordinator.tools(scopedTo: slug).filter { tool in
            guard let route = MCPToolName.parse(tool.name) else { return true }
            return !excluded.contains(route.slug)
        }
    }

    /// 聊天工具菜单可选的服务器；MCP 关闭或未配置任何服务器时为空。
    var mcpServers: [MCPServer] { core.mcpCoordinator.servers }

    /// 打开或关闭本聊天的工具使用。
    func setToolsEnabled(_ enabled: Bool, in chat: AIChatState) {
        chat.toolScope.isEnabled = enabled
    }

    /// 切换本聊天中某个 MCP 服务器的启用状态。
    func toggleToolServer(_ slug: String, in chat: AIChatState) {
        chat.toolScope.toggle(slug)
    }

    func showMCPSettings() {
        settingsCoordinator.showSettings(tab: .ai)
    }

    func showDictationSettings() {
        settingsCoordinator.showSettings(tab: .dictation)
    }

    /// 草稿所指向的服务器，使输入框能在输入过程中以 chip 形式展示。
    func addressedServer(in draft: String) -> MCPServer? {
        MCPComposerAddress.parse(draft, slugs: core.mcpCoordinator.slugs).slug
            .flatMap { core.mcpCoordinator.server(slug: $0) }
    }

    /// 停止当前回复。
    func stopResponse(in chat: AIChatState) {
        chat.cancel()
    }

    /// 复制最后一条助手回复的纯文本。
    func copyLastResponse(in chat: AIChatState) {
        guard let text = chat.lastAssistantText else { return }
        Paster.copyPlainText(text)
    }

    /// 本聊天所用模型支持的能力；输入框只提供适用的项。
    func capabilities(for chat: AIChatState) -> AIModelCapabilities {
        switch model(for: chat) {
        case .appleIntelligence?: return .appleIntelligence
        case .codex?: return .codex
        case .claude?: return .claudeCommand
        case .grok?, .openCode?, .cursor?:
            return AIModelCapabilities(
                images: false, documents: false, webSearch: false, tools: false)
        case .api(let connection, let model, _)?:
            return core.aiSettings.connection(id: connection)?.capabilities(for: model)
                ?? AIModelCapabilities.none
        case nil: return AIModelCapabilities.none
        }
    }

    /// 该聊天路由可容纳的历史量；端上模型的窗口要小得多。
    func contextBudget(for chat: AIChatState) -> Int {
        model(for: chat)?.isOnDevice == true
            ? AppleIntelligence.contextBudget : ChatSession.defaultTextBudget
    }

    /// 上下文卡片所需的数据；仪表每次刷新都会重绘，因此可跳过卡片里的模型标题。
    func contextReport(for chat: AIChatState, detailed: Bool = true) -> ChatContextReport {
        let session = chat.session
        let budget = contextBudget(for: chat)
        let can = capabilities(for: chat)
        let scope = chat.toolScope
        return ChatContextReport(
            modelTitle: detailed ? selectedModelTitle(for: chat) : "",
            historyBytes: session.historyBytes, budget: budget,
            sentMessages: session.sentMessageCount(textBudget: budget),
            totalMessages: session.historyMessages.count,
            stagedFiles: chat.pendingAttachments.count,
            stagedBytes: chat.pendingAttachments.reduce(0) { $0 + $1.payload.byteCount },
            usage: chat.usage,
            systemPrompt: core.aiSettings.systemPromptEnabled,
            webSearch: core.aiSettings.webSearchEnabled && can.webSearch,
            toolServers: can.tools && scope.isEnabled
                ? mcpServers.count { scope.allows($0.slug) } : 0)
    }

    // MARK: - Attachments

    /// ⌘V 暂存一个文件并在主线程之外读取；返回 false 表示把该快捷键交还给输入框编辑器。
    func attachPastedFile(files: [URL], to chat: AIChatState) -> Bool {
        let pasteboard = NSPasteboard.general
        // 复制的文本常常同时带有 TIFF；只有不含字符串的剪贴板才视为图片。
        let pasted =
            files.isEmpty && pasteboard.string(forType: .string) == nil
            ? pasteboard.availableType(from: [.png, .tiff]).flatMap { pasteboard.data(forType: $0) }
            : nil
        guard !files.isEmpty || pasted != nil else { return false }
        if let refusal = unattachable(files, in: chat) {
            core.showMessage(refusal.message, tone: .neutral)
            return true
        }
        if pasted != nil, !capabilities(for: chat).images {
            core.showMessage(ChatAttachmentRefusal.imagesUnsupported.message, tone: .neutral)
            return true
        }
        stage(files: files, pasted: pasted, into: chat)
        return true
    }

    /// 拖放或回形针按钮：拒绝理由与粘贴一致，因为起决定作用的是路由。
    func attach(files: [URL], to chat: AIChatState) {
        let files = files.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if let refusal = unattachable(files, in: chat) {
            core.showMessage(refusal.message, tone: .neutral)
            return
        }
        stage(files: files, pasted: nil, into: chat)
    }

    /// 附属型应用必须先激活，否则面板会开在最前台应用之后。
    func chooseFiles(for chat: AIChatState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = settings.text(AIKey.attachPrompt)
        panel.message = settings.text(AIKey.attachHint)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        attach(files: panel.urls, to: chat)
    }

    /// 清空本聊天的全部暂存附件。
    func clearAttachments(in chat: AIChatState) {
        chat.clearAttachments()
    }

    /// 移除指定暂存附件。
    func removeAttachment(_ id: UUID, in chat: AIChatState) {
        chat.removeAttachment(id)
    }

    /// 当前路由触发的第一个拒绝原因，使粘贴能被解释而不是被静默丢弃。
    private func unattachable(_ files: [URL], in chat: AIChatState) -> ChatAttachmentRefusal? {
        let can = capabilities(for: chat)
        for file in files {
            guard let kind = AIAttachmentPolicy.kind(forFileName: file.lastPathComponent) else {
                return .unsupported(file.pathExtension.lowercased())
            }
            switch kind {
            case .image where !can.images: return .imagesUnsupported
            case .pdf where !can.documents: return .documentsUnsupported
            default: continue
            }
        }
        return nil
    }

    /// 优先文件、原始字节作为回退；该快捷键被消费，绝不会粘贴出路径文本。
    private func stage(files: [URL], pasted: Data?, into chat: AIChatState) {
        let generation = chat.stagingGeneration
        Task { [weak self, weak chat] in
            let read = await Task.detached(priority: .userInitiated) {
                () -> [ChatAttachmentReader.Outcome] in
                if !files.isEmpty { return files.map(ChatAttachmentReader.read) }
                return pasted.map { [ChatAttachmentReader.image($0)] } ?? []
            }.value
            guard let self, let chat else { return }
            guard generation == chat.stagingGeneration else {
                core.showMessage(
                    settings.text(AIKey.fileStillLoading),
                    tone: .neutral)
                return
            }
            // 遇到第一个拒绝即停止，使混合粘贴能说明是哪个文件无法接收。
            for outcome in read {
                switch outcome {
                case .failed(let refusal):
                    core.showMessage(refusal.message, tone: .neutral)
                    return
                case .staged(let item):
                    let attachment = ChatAttachment(
                        payload: item.payload, name: item.name, preview: item.preview)
                    if let refusal = chat.attach(attachment) {
                        core.showMessage(refusal.message, tone: .neutral)
                        return
                    }
                }
            }
        }
    }

    // MARK: - Models

    /// 所有可选模型选项的扁平列表。
    var modelOptions: [AIModelOption] {
        modelGroups.flatMap(\.options)
    }

    /// 是否有已启用的提供方仍在探测中（订阅启动或 CLI 检查）。
    var isModelCatalogLoading: Bool {
        core.aiSettings.enabledInstalledProviders.contains { kind in
            switch kind {
            case .codex: core.chatGPTSubscription.phase == .starting
            case .claude, .grok, .openCode, .cursor:
                core.installedAI.status(for: kind).phase == .checking
            }
        }
    }

    /// 按运行位置分组的可选模型。
    var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI)
    }

    /// 只要仍然可用就用该聊天自身的模型；否则回退到新聊天采用的默认值。
    func model(for chat: AIChatState) -> AIModelSelection? {
        if let own = chat.session.model, isReachable(own) { return own }
        return core.aiSettings.defaultModel
    }

    /// 在 Settings 中被移除的路由会回退到默认值，而不是让聊天报错。
    private func isReachable(_ selection: AIModelSelection) -> Bool {
        switch selection {
        case .appleIntelligence:
            return true
        case .api(let connection, let model, _):
            return core.aiSettings.connection(id: connection)?.models.contains(model) == true
        case .codex, .claude, .grok, .openCode, .cursor:
            return selection.source.installedKind.map {
                core.aiSettings.enabledInstalledProviders.contains($0)
            } ?? false
        }
    }

    private func provider(
        for chat: AIChatState, toolServers: AIToolServerSession? = nil
    ) throws -> any AIProvider {
        guard let selection = model(for: chat) else {
            throw AIProviderError.unavailable(settings.text(AIKey.chooseModelHint))
        }
        return try AIProviderFactory.make(
            selection: selection, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI,
            toolServers: toolServers)
    }

    /// 只有当某个活跃聊天的路由无法自行调用工具时，GearMac 才自己运行本地服务器。
    var everyChatRunsItsOwnTools: Bool {
        chats.live.allSatisfy { model(for: $0)?.runsItsOwnTools == true }
    }

    /// 当前聊天所选模型的显示名。
    func selectedModelTitle(for chat: AIChatState) -> String {
        modelTitle(of: model(for: chat), among: modelOptions)
    }

    /// 在此处截断而非交给布局：可伸缩的标签会从搜索框那里抢走整行宽度。
    func modelTitle(of selected: AIModelSelection?, among options: [AIModelOption]) -> String {
        guard let selected else { return settings.text(AIKey.chooseModel) }
        let title = options.first { $0.matches(selected) }?.title ?? selected.model
        guard title.count > Self.maxModelTitleLength else { return title }
        let keep = Self.maxModelTitleLength / 2
        return "\(title.prefix(keep))…\(title.suffix(keep))"
    }

    private static let maxModelTitleLength = 26

    /// 当前聊天所选模型的品牌图标。
    func selectedModelIcon(for chat: AIChatState) -> PopoverMenuIcon {
        modelIcon(of: model(for: chat))
    }

    /// 图标取自选中项而非已加载列表：列表在选择器首次绘制之后才到达。
    func modelIcon(of selected: AIModelSelection?) -> PopoverMenuIcon {
        switch selected {
        case .appleIntelligence?: return AIModelOption.appleIntelligenceIcon
        case .codex?: return .asset(AIBrand.openAI.assetName)
        case .claude?: return .asset(AIBrand.claude.assetName)
        case .grok?: return .asset(AIBrand.grok.assetName)
        case .cursor?: return AIModelOption.cursorIcon
        case .openCode(let model, _)?: return AIModelOption.icon(AIBrand.resolve(model: model))
        case .api(let connection, let model, _)?:
            return AIModelOption.icon(
                core.aiSettings.connection(id: connection).flatMap {
                    AIBrand.resolve(provider: $0.provider, model: model)
                })
        case nil: return AIModelOption.icon(nil)
        }
    }

    /// 进入聊天的一次性准备成本：解析模型列表并连接服务器。
    func prepareForChat() {
        warmUpModelList()
        core.mcpCoordinator.warmUp()
    }

    /// 拉取模型列表，使标题显示为名称，并让默认值无需打开 Settings 即可解析。
    func warmUpModelList() {
        guard let stored = core.aiSettings.defaultModel else {
            prepareModelSwitcher()
            core.aiSettings.resolveDefaultModel()
            return
        }
        // 只有已安装的路由需要检查；其余选项已在磁盘上确定。
        if stored.source.installedKind != nil { prepareModelSwitcher() }
    }

    /// 该聊天保留这次选择，默认值也随之更新，使下一条新聊天从同一模型开始。
    /// 为聊天选定模型，并同步更新全局默认值。
    func selectModel(_ option: AIModelOption, in chat: AIChatState) {
        let selection = AIModelOption.withDefaultEffort(
            option.selection, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI)
        chat.setModel(selection)
        core.aiSettings.select(selection)
    }

    /// 当前模型可选的推理档位；不支持时为空。
    func reasoningEfforts(for chat: AIChatState) -> [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: model(for: chat), settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI)
    }

    /// 已选推理档位的显示名；未选时为 "Reasoning"。
    func selectedReasoningTitle(for chat: AIChatState) -> String {
        guard let selected = model(for: chat)?.effort,
            let effort = reasoningEfforts(for: chat).first(where: { $0.id == selected })
        else { return "Reasoning" }
        return effort.title
    }

    /// 设定聊天的推理档位并同步全局默认值。
    func selectReasoningEffort(_ effort: ChatGPTSubscription.Effort, in chat: AIChatState) {
        guard let selection = model(for: chat)?.withEffort(effort.id) else { return }
        chat.setModel(selection)
        core.aiSettings.select(selection)
    }

    /// 触发已安装 AI 的生命周期刷新；调用方可等待该任务完成。
    @discardableResult
    func prepareModelSwitcher() -> Task<Void, Never> {
        core.applyInstalledAILifecycle()
    }

    /// 隐藏命令面板并打开 Settings 的 AI 标签页。
    func showSettings() {
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        settingsCoordinator.showSettings(tab: .ai)
    }

    /// 探测当前路由是否可用；不可用时返回给用户看的说明。
    func availability(for chat: AIChatState) -> String? {
        do {
            _ = try provider(for: chat)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// 上下文卡片呈现的数据；历史按字节计数，这也是预算的计量单位。
struct ChatContextReport: Equatable {
    let modelTitle: String
    let historyBytes: Int
    let budget: Int
    let sentMessages: Int
    let totalMessages: Int
    let stagedFiles: Int
    let stagedBytes: Int
    let usage: AIUsage?
    let systemPrompt: Bool
    let webSearch: Bool
    let toolServers: Int

    /// 路由报告了自身窗口时用该窗口，否则用 GearMac 的历史预算。
    var fill: Double {
        if let tokens = usage?.contextTokens, let window = usage?.contextWindow, window > 0 {
            return Double(tokens) / Double(window)
        }
        return Double(historyBytes) / Double(max(budget, 1))
    }

    /// 供 VoiceOver 朗读的上下文占用摘要。
    func accessibilitySummary(_ language: AppLanguage) -> String {
        let percent = fill.formatted(.percent.precision(.fractionLength(0)))
        return String(
            format: L10n.string(AIKey.contextSummary, language: language), percent, sentMessages,
            totalMessages)
    }
}
