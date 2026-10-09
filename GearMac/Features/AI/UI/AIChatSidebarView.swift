// 文件职责：AI Chat 窗口左侧的会话列表，提供搜索、置顶与日期分组、重命名、复制、导出与删除。
// 分层：UI；只通过 AIChatCoordinator 读写状态，自身不持有会话数据。
import SwiftUI

/// 所有已保存的会话，置顶在前、其余按日期排列；选中一条即在右侧打开。
struct AIChatSidebarView: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    @State private var query = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var renameFocused: Bool

    private var chats: AIChatSurfacesState { coordinator.chats }
    private var history: ChatHistoryStore { coordinator.history }

    /// 列表中一段的标题与所属会话（按标题去重标识）。
    private struct ChatSection: Identifiable {
        let title: String
        var conversations: [ChatConversation]
        var id: String { title }
    }

    /// 时间倒序本身已将同一天聚在一起，因此每个日期分组只需开启一次。
    private var sections: [ChatSection] {
        let results = history.search(query)
        var sections: [ChatSection] = []
        let pinned = results.filter(\.isPinned)
        if !pinned.isEmpty {
            sections.append(
                ChatSection(title: coordinator.text(AIKey.sidebarPinned), conversations: pinned))
        }
        for conversation in results where !conversation.isPinned {
            let title = DateBucket(for: conversation.updatedAt).title
            if sections.last?.title == title {
                sections[sections.count - 1].conversations.append(conversation)
            } else {
                sections.append(ChatSection(title: title, conversations: [conversation]))
            }
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatSearchField(
                query: $query, focused: $searchFocused, language: coordinator.language)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            list
        }
        // 搜索框位于工具栏材质之下，因此需要自己保留顶部间距。
        .padding(.top, Theme.Spacing.md)
        .onExitCommand {
            if query.isEmpty {
                _ = coordinator.closeWindowIfKey()
            } else {
                query = ""
            }
        }
    }

    /// 会话列表本体；为空时改为显示空状态。
    @ViewBuilder private var list: some View {
        let sections = sections
        let answering = chats.answeringIDs
        let openID = chats.window.session.id
        if sections.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selection) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.conversations) { conversation in
                            row(
                                conversation, isAnswering: answering.contains(conversation.id),
                                isSelected: conversation.id == openID
                            )
                            .tag(conversation.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let conversation = history.conversation(id: id) {
                    menu(for: conversation)
                }
            }
            .onDeleteCommand {
                guard let id = selection.wrappedValue, history.conversation(id: id) != nil
                else { return }
                Task { await coordinator.deleteChat(id: id) }
            }
        }
    }

    /// 历史不可用、搜索无结果或尚无聊天时各自的空状态。
    @ViewBuilder private var emptyState: some View {
        if !history.isAvailable {
            ContentUnavailableView(
                coordinator.text(AIKey.sidebarHistoryUnavailable),
                systemImage: "exclamationmark.triangle",
                description: Text(coordinator.text(AIKey.sidebarHistoryUnavailableDetail)))
        } else if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(
                coordinator.text(AIKey.sidebarNoChats),
                systemImage: "bubble.left.and.bubble.right",
                description: Text(coordinator.text(AIKey.sidebarNoChatsDetail)))
        }
    }

    /// 单行渲染：正在重命名时显示输入框，否则显示常规行。
    @ViewBuilder private func row(
        _ conversation: ChatConversation, isAnswering: Bool, isSelected: Bool
    ) -> some View {
        if renaming == conversation.id {
            TextField(
                coordinator.text(AIKey.sidebarChatName), text: $renameText,
                prompt: Text(conversation.title)
            )
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commitRename(conversation.id) }
                .onExitCommand { renaming = nil }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename(conversation.id) }
                }
        } else {
            ChatSidebarRow(
                conversation: conversation, isAnswering: isAnswering, isSelected: isSelected,
                language: coordinator.language)
        }
    }

    /// 右键菜单：置顶、重命名、复制、导出与删除。
    @ViewBuilder private func menu(for conversation: ChatConversation) -> some View {
        Button(
            coordinator.text(
                conversation.isPinned ? AIKey.sidebarUnpin : AIKey.sidebarPin),
            systemImage: conversation.isPinned ? "pin.slash" : "pin"
        ) {
            coordinator.togglePin(id: conversation.id)
        }
        Button(coordinator.text(AIKey.sidebarRename), systemImage: "pencil") {
            beginRename(conversation)
        }
        Divider()
        Button(coordinator.text(AIKey.sidebarCopy), systemImage: "doc.on.doc") {
            coordinator.copyChat(id: conversation.id)
        }
        Button(coordinator.text(AIKey.sidebarExport), systemImage: "square.and.arrow.up") {
            coordinator.exportChat(id: conversation.id)
        }
        Divider()
        Button(coordinator.text(AIKey.sidebarDelete), systemImage: "trash", role: .destructive) {
            Task { await coordinator.deleteChat(id: conversation.id) }
        }
        Button(
            coordinator.text(AIKey.sidebarDeleteAll), systemImage: "trash.slash",
            role: .destructive
        ) {
            Task { await coordinator.deleteAllChats() }
        }
    }

    /// 进入重命名编辑状态并聚焦输入框。
    private func beginRename(_ conversation: ChatConversation) {
        renameText = conversation.customTitle ?? ""
        renaming = conversation.id
        Task { @MainActor in renameFocused = true }
    }

    /// 提交重命名；未正在编辑该行时直接忽略。
    private func commitRename(_ id: UUID) {
        guard renaming == id else { return }
        renaming = nil
        coordinator.rename(id: id, to: renameText)
    }

    /// 当前打开的聊天即选中的行；新聊天在发出首条消息前还没有对应行。
    private var selection: Binding<UUID?> {
        Binding(
            get: { chats.window.session.id },
            set: { id in
                guard let id, id != chats.window.session.id else { return }
                coordinator.openChat(id: id)
            }
        )
    }

}

/// 一条聊天行：标题，以及应答中的转圈或置顶标记；悬停时用更淡的底色表示选中。
private struct ChatSidebarRow: View {
    let conversation: ChatConversation
    let isAnswering: Bool
    let isSelected: Bool
    /// 无障碍标签所用的语言。
    let language: AppLanguage
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(conversation.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isAnswering {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(L10n.string(AIKey.sidebarAnswering, language: language))
            } else if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(L10n.string(AIKey.sidebarPinned, language: language))
            }
        }
        // 覆盖整个单元格，使指针不会经过任何没有行响应的空隙。
        .frame(maxHeight: .infinity)
        .listRowInsets(EdgeInsets())
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .listRowBackground(hoverFill)
        .help(conversation.displayTitle)
    }

    /// 与系统选中态一样内缩并带圆角，使两者看起来是同一种形状。
    @ViewBuilder private var hoverFill: some View {
        if isHovered, !isSelected {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.rowHover)
                .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

/// 侧边栏的搜索框，按 Settings 的样式绘制，使两个窗口保持一致。
private struct ChatSearchField: View {
    @Binding var query: String
    @FocusState.Binding var focused: Bool
    /// 提示词与无障碍标签所用的语言。
    let language: AppLanguage

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "", text: $query,
                prompt: Text(L10n.string(AIKey.sidebarSearchPlaceholder, language: language)))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.string(AIKey.sidebarClearSearch, language: language))
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.aiChatSearchField)
        .background { Color.clear.frosted(in: Capsule()) }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .accessibilityLabel(L10n.string(AIKey.sidebarSearch, language: language))
    }
}
