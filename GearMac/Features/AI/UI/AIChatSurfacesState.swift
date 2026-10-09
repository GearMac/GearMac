// 文件职责：管理 AI 聊天在各入口（命令面板的 Quick AI 与 AI Chat 窗口）之间共享的会话状态，负责切换、迁移与批量删除。
// 分层：Model/UI 状态；@MainActor 且不 import AppKit/SwiftUI，持久化交给注入的 ChatHistoryStore，回复由各 AIChatState 自持。
import Foundation
import Observation

/// 每个入口当前展示哪条活跃聊天；同一条聊天只活跃于一处，切走时不会取消它。
@MainActor
@Observable
final class AIChatSurfacesState {
    /// 命令面板的会话。
    private(set) var quickAI: AIChatState
    /// AI Chat 窗口的会话。
    private(set) var window: AIChatState
    /// 在回复中途被切走的窗口会话；每条会在其回复结束时自行保存。
    private var answeringElsewhere: [UUID: AIChatState] = [:]

    private let history: ChatHistoryStore

    /// 分发给每个状态，使任何位置的聊天在首次回答结束后都能被命名。
    @ObservationIgnored var onReplyFinished: (@MainActor (AIChatState) -> Void)? {
        didSet {
            for state in [quickAI, window] + answeringElsewhere.values {
                state.onReplyFinished = onReplyFinished
            }
        }
    }

    init(history: ChatHistoryStore) {
        self.history = history
        quickAI = AIChatState(history: history)
        window = AIChatState(history: history)
    }

    /// 新建一个共用同一历史存储的状态，并接上命名回调。
    private func makeState() -> AIChatState {
        let state = AIChatState(history: history)
        state.onReplyFinished = onReplyFinished
        return state
    }

    /// 仍有回复正在到达的会话，无论它们显示在哪里。
    var answeringIDs: Set<UUID> {
        Set(live.filter(\.isStreaming).map(\.session.id))
    }

    /// 当前持有 `id` 的状态，避免第二个入口同时编辑同一份转录。
    func holder(of id: UUID) -> AIChatState? {
        live.first { $0.holds(id) }
    }

    // MARK: - The window

    /// 尽可能复用在别处的活跃状态，使仍在到达的回复继续显示在屏幕上。
    @discardableResult
    func openInWindow(id: UUID) -> Bool {
        if window.holds(id) { return true }
        let next: AIChatState
        if quickAI.holds(id) {
            next = quickAI
            quickAI = makeState()
        } else if let answering = answeringElsewhere.removeValue(forKey: id), answering.isStreaming {
            next = answering
        } else {
            let loaded = makeState()
            guard loaded.open(id: id) else { return false }
            next = loaded
        }
        show(next)
        return true
    }

    /// 空聊天本身就是新的；替换它只会丢掉其中暂存的内容。
    func newWindowChat() {
        guard !window.session.messages.isEmpty else { return }
        show(makeState())
    }

    /// Quick AI 的会话整体迁移过来，包含正在进行的回复与已暂存的文件。
    @discardableResult
    func continueQuickAIInWindow(draft: String = "") -> Bool {
        guard !quickAI.session.messages.isEmpty || !quickAI.pendingAttachments.isEmpty else {
            // 没有任何内容可迁移，因此这一行并入窗口聊天已有的草稿，而不是覆盖它。
            if !draft.isEmpty {
                window.draft = window.draft.isEmpty ? draft : window.draft + "\n" + draft
            }
            return false
        }
        let moved = quickAI
        quickAI = makeState()
        show(moved)
        if !draft.isEmpty { window.draft = draft }
        return true
    }

    /// 切换窗口展示的会话；若原会话仍在流式输出，则把它转入后台继续。
    private func show(_ next: AIChatState) {
        if window.isStreaming { answeringElsewhere[window.session.id] = window }
        window = next
        answeringElsewhere = answeringElsewhere.filter { $0.value.isStreaming }
    }

    // MARK: - Quick AI

    /// 当另一个入口持有它时拒绝打开：两个写入方会互相覆盖彼此的保存。
    @discardableResult
    func openInQuickAI(id: UUID) -> Bool {
        if quickAI.holds(id) { return true }
        guard holder(of: id) == nil else { return false }
        return quickAI.open(id: id)
    }

    // MARK: - Every surface

    func delete(id: UUID) {
        (holder(of: id) ?? window).delete(id: id)
        answeringElsewhere[id] = nil
    }

    /// 清空之前先取消所有将被删除的回复：取消动作会触发保存，否则它们又会被写回。
    func deleteAll() {
        let doomed = live.filter { history.conversation(id: $0.session.id)?.isPinned != true }
        for state in doomed { state.cancel() }
        history.clearAll()
        for state in doomed { state.startNewChat() }
        answeringElsewhere = answeringElsewhere.filter { entry in
            !doomed.contains { $0 === entry.value }
        }
    }

    /// 关闭 AI 或退出应用时调用：所有回复停止并保存，两个入口都重新开始。
    func reset() {
        for state in live { state.startNewChat() }
        answeringElsewhere = [:]
    }

    /// 已结束的挂起聊天本身已保存，因此只有仍在应答的才计入活跃集合。
    var live: [AIChatState] {
        [quickAI, window] + answeringElsewhere.values.filter(\.isStreaming)
    }
}
