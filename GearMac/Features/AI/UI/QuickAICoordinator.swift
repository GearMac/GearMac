// 文件职责：管理 palette 中的 Quick AI 界面：唤出与打开策略、发送/新建/历史等动作，以及把对话移交给独立聊天窗口。
// 分层：Coordinator；@MainActor 下编排 PaletteState、AIChatSurfacesState 与各 Coordinator，不直接持有 UI。
import Foundation

/// palette 的 AI 界面：唤出、打开策略，以及把对话移交给聊天窗口。
@MainActor
final class QuickAICoordinator {
    private let chats: AIChatSurfacesState
    private let settings: AppSettings
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    /// 注入所需的共享状态与协调器。
    init(
        chats: AIChatSurfacesState, settings: AppSettings, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.chats = chats
        self.settings = settings
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private var chat: AIChatState { chats.quickAI }
    private var chatCoordinator: AIChatCoordinator { core.aiChatCoordinator }

    /// 唤出 Quick AI 界面；已显示则关闭，否则按打开策略决定是否恢复对话后显示。
    func show() {
        guard settings.aiEnabled else { return }
        // 不用 `togglePalette`：打开策略只在进入时决定一次是否恢复对话。
        guard !paletteCoordinator.isShowing(.ai) else {
            paletteCoordinator.hidePalette()
            return
        }
        applyOpenPolicy()
        paletteCoordinator.showPalette(mode: .ai)
    }

    /// ⇥ 与 AI 兜底入口：新建一个已携带并发出该问题的对话。
    func ask(_ prompt: String) {
        guard settings.aiEnabled else { return }
        // 没有问题也不应跳过打开策略：这是一次唤出，而非提问。
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show()
            return
        }
        chat.startNewChat()
        paletteCoordinator.showPalette(mode: .ai)
        send(prompt)
    }

    /// 关闭 AI 时同时离开该界面，避免 palette 展示已停用的功能。
    func leave() {
        if palette.mode == .ai || palette.mode == .aiHistory { palette.prepare(mode: .launcher) }
    }

    /// 在启动器中粘贴的文件应进入 Quick AI，而不是变成对其文件名的搜索。
    func attachPastedFileFromLauncher(files: [URL]) -> Bool {
        guard settings.aiEnabled, !files.isEmpty else { return false }
        show()
        return attachPastedFile(files: files)
    }

    /// 把粘贴的文件附加到当前对话；返回是否附加成功。
    func attachPastedFile(files: [URL]) -> Bool {
        chatCoordinator.attachPastedFile(files: files, to: chat)
    }

    /// 唯一决定唤出时是否恢复对话的地方；Pop to Root 只清空当前界面，不改变该决策。
    private func applyOpenPolicy() {
        // 仍在接收中的回复是用户主动发起的，重置会丢弃这条回答。
        guard !chat.isStreaming else { return }
        let recent = core.chatHistory.conversations.first
        let hasTranscript = !chat.session.messages.isEmpty
        // 已暂存的文件是尚未发送的内容：两次普通唤出都不应丢弃它们。
        let hasStaging = !chat.pendingAttachments.isEmpty
        // 无驻留对话时取历史记录，使重启后该判断依然成立。
        let lastActiveAt = hasTranscript ? chat.session.updatedAt : recent?.updatedAt
        let decision = AIConversationOpenPolicy.decide(
            opensTo: core.aiSettings.opensTo, newAfter: core.aiSettings.newChatAfter,
            lastActiveAt: lastActiveAt, now: Date())
        switch decision {
        case .resume:
            guard !hasTranscript, !hasStaging, let recent else { return }
            // 该对话可能已在窗口中打开，此时本次唤出改为新建。
            chats.openInQuickAI(id: recent.id)
        case .startNew:
            // 空对话本就是新的，重置只会丢弃其中已暂存的内容。
            guard hasTranscript else { return }
            chat.startNewChat()
        }
    }

    /// 向当前对话发送输入；返回是否已发送。
    @discardableResult
    func send(_ input: String) -> Bool {
        chatCoordinator.send(input, in: chat)
    }

    /// 新建对话并把 palette 切到 AI 界面。
    func startNewChat() {
        chat.startNewChat()
        // 是新建对话而非重置根界面：已打开的对话仍然留在其后方。
        palette.replace(mode: .ai)
    }

    /// 打开聊天历史界面。
    func showHistory() {
        palette.push(mode: .aiHistory)
    }

    /// 若该对话已由窗口持有则在窗口中打开，否则两个写入方会互相覆盖保存。
    func openChat(id: UUID) {
        guard chats.openInQuickAI(id: id) else {
            continueInChat(id: id)
            return
        }
        // 历史记录被丢弃而非压入栈底，因此一次返回即可彻底离开聊天。
        _ = palette.pop()
        palette.replace(mode: .ai)
    }

    /// 聊天历史的 ⌘J：已保存的对话在窗口中打开；若它正在 Quick AI 中则一并接管。
    func continueInChat(id: UUID) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        chatCoordinator.openChat(id: id)
        chatCoordinator.showWindow()
    }

    /// 删除指定对话。
    func deleteChat(id: UUID) {
        chats.delete(id: id)
    }

    /// 异步删除全部对话。
    func deleteAllChats() async {
        await chatCoordinator.deleteAllChats()
    }

    /// 由窗口接管该对话；palette 随之关闭，与设置界面的行为一致。
    func continueInChat() {
        let draft = palette.query
        palette.query = ""
        paletteCoordinator.hidePalette(restoreFocus: false)
        chatCoordinator.continueInWindow(draft: draft)
    }

    /// 停止当前正在进行的回复。
    func stopResponse() {
        chatCoordinator.stopResponse(in: chat)
    }

    /// 重新生成最后一条回复。
    func regenerate() {
        chatCoordinator.regenerate(in: chat)
    }

    /// 复制最后一条回复的内容。
    func copyLastResponse() {
        chatCoordinator.copyLastResponse(in: chat)
    }

    /// 输入框为空时按退格会先移除最后一个已暂存图片，然后才退出聊天。
    func removeLastAttachment() -> Bool {
        chat.removeLastAttachment()
    }

    /// 清空当前对话中已暂存的附件。
    func clearAttachments() {
        chat.clearAttachments()
    }

    /// 移除指定附件。
    func removeAttachment(_ id: UUID) {
        chat.removeAttachment(id)
    }
}
