// 文件职责：本地会话历史面板：搜索会话摘要、预览并显式在 Quick AI 中打开或删除。
// 分层：UI（SwiftUI/PaletteScreen）；读写通过 ChatHistoryStore 与 QuickAICoordinator，不直接操作存储。
import SwiftUI

/// 本地会话列表：搜索摘要、预览其中一条，然后显式在 Quick AI 中打开它。
struct ChatHistoryScreen: PaletteScreen {
    let history: ChatHistoryStore
    let chat: AIChatState
    let coordinator: QuickAICoordinator
    let vm: PaletteState
    let openActions: () -> Void
    let metrics: InterfaceMetrics

    var rows: [ChatConversation] { history.search(vm.query) }
    let primaryActionTitle = "Open Chat"

    /// 按下标安全地取出会话；越界时返回 nil。
    private func conversation(at selection: Int) -> ChatConversation? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 选中会话的 ⌘K 动作菜单内容；未选中任何项时返回 nil。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let conversation = conversation(at: selection) else { return nil }
        return ChatHistoryActionsMenu.content(
            conversation: conversation, coordinator: coordinator)
    }

    /// 回车打开选中的会话。
    func activate(at selection: Int) {
        guard let conversation = conversation(at: selection) else { return }
        coordinator.openChat(id: conversation.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    /// 处理 ⌘⌫/⌫/⌃X 等快捷键：删除单条、全部删除与继续会话。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            delete(at: selection)
            return true
        case .deleteAll:
            deleteAll()
            return true
        case .continueInChat:
            guard let conversation = conversation(at: selection) else { return false }
            coordinator.continueInChat(id: conversation.id)
            return true
        default: return false
        }
    }

    private func delete(at selection: Int) {
        guard let conversation = conversation(at: selection) else { return }
        coordinator.deleteChat(id: conversation.id)
    }

    private func deleteAll() {
        Task { await coordinator.deleteAllChats() }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 面板主体：无结果时展示空态，否则展示会话列表与右侧预览。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: history.isAvailable
                    ? history.conversations.isEmpty ? "No chats yet" : "No matching chats"
                    : "Chat history is unavailable")
        } else {
            let selected = conversation(at: selection)
            HStack(spacing: 0) {
                ChatHistoryList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { conversation in
                        vm.selection = rows.firstIndex(of: conversation) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { conversation in
                        if let index = rows.firstIndex(of: conversation) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ChatHistoryPreview(history: history, chat: chat, conversationID: selected?.id)
            }
        }
    }
}

/// 会话行的动作菜单：打开、在 AI Chat 中继续、删除单条或全部会话。
@MainActor
enum ChatHistoryActionsMenu {
    static func content(
        conversation: ChatConversation, coordinator: QuickAICoordinator
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: conversation.displayTitle,
            items: [
                PopoverMenuItem(
                    title: "Open Chat", systemImage: "sparkles", shortcut: "↵"
                ) {
                    coordinator.openChat(id: conversation.id)
                },
                PopoverMenuItem(
                    title: "Continue in AI Chat", systemImage: "bubble.left.and.bubble.right",
                    shortcut: "⌘J"
                ) {
                    coordinator.continueInChat(id: conversation.id)
                },
                PopoverMenuItem(
                    title: "Delete Chat", systemImage: "trash", startsSection: true, shortcut: "⌃X",
                    isDestructive: true
                ) {
                    coordinator.deleteChat(id: conversation.id)
                },
                PopoverMenuItem(
                    title: "Delete All Chats", systemImage: "trash", shortcut: "⌃⇧X",
                    isDestructive: true
                ) {
                    Task { await coordinator.deleteAllChats() }
                }
            ])
    }
}
