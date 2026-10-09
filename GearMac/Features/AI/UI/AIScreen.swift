// 文件职责：Quick AI 面板界面，搜索框即输入框，并渲染会话相关内容与附件、@ 服务器胶囊等。
// 分层：UI（SwiftUI/PaletteScreen）；通过 QuickAICoordinator 与 AIChatCoordinator 驱动动作，不自持业务状态。
import SwiftUI

/// Quick AI：一个面板界面，其搜索框本身就是输入框。
struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let chat: AIChatState
    let coordinator: QuickAICoordinator
    let chatCoordinator: AIChatCoordinator
    /// 已暂存文件的菜单由面板负责弹出，与其他所有头部菜单一致。
    let openAttachments: () -> Void

    /// 面板唯一的行，仅用于给当前选中项提供一个标识。
    struct Row: Identifiable {
        let id = "ai-chat"
    }

    let rows = [Row()]

    /// 底部按钮同时承担回车的两种职责：发送；响应流式输出中则显示为停止。
    var primaryActionTitle: String { chat.isStreaming ? "Stop" : "Send" }

    /// 面板 ⌘K 动作菜单的内容（停止、继续/打开 AI 聊天、新建、重新生成等）。
    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        if chat.isStreaming {
            items.append(
                PopoverMenuItem(title: "Stop Response", systemImage: "stop.fill", shortcut: "⌘.") {
                    coordinator.stopResponse()
                })
        }
        items.append(
            PopoverMenuItem(
                title: chat.session.messages.isEmpty ? "Open AI Chat" : "Continue in AI Chat",
                systemImage: "bubble.left.and.bubble.right", shortcut: "⌘J"
            ) {
                coordinator.continueInChat()
            })
        items.append(
            PopoverMenuItem(title: "New Chat", systemImage: "plus.bubble", shortcut: "⌘N") {
                coordinator.startNewChat()
            })
        if canRegenerate {
            items.append(
                PopoverMenuItem(
                    title: "Regenerate Response", systemImage: "arrow.clockwise", shortcut: "⌘R"
                ) {
                    coordinator.regenerate()
                })
        }
        if chat.lastAssistantText != nil {
            items.append(
                PopoverMenuItem(
                    title: "Copy Last Response", systemImage: "doc.on.doc", startsSection: true,
                    shortcut: "⇧⌘C"
                ) {
                    coordinator.copyLastResponse()
                })
        }
        if !chat.pendingAttachments.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: "Remove Attachments", systemImage: "paperclip",
                    startsSection: chat.lastAssistantText == nil
                ) {
                    coordinator.clearAttachments()
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Chat History", systemImage: "clock.arrow.circlepath", startsSection: true,
                shortcut: "⌘Y"
            ) {
                coordinator.showHistory()
            })
        items.append(
            PopoverMenuItem(
                title: "AI Settings", systemImage: "slider.horizontal.3", shortcut: "⌥⌘,"
            ) {
                chatCoordinator.showSettings()
            })
        return PopoverMenuContent(header: chatCoordinator.title(of: chat), items: items)
    }

    /// 回车与底部按钮是同一动作；输入框为空时不会发送任何内容。
    func activate(at selection: Int) {
        if chat.isStreaming {
            coordinator.stopResponse()
        } else if coordinator.send(vm.query) {
            vm.query = ""
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    /// Raycast 有对应快捷键时就沿用；⌘Y 打开历史（同 Safari），⌘. 停止。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .continueInChat: coordinator.continueInChat()
        case .newItem: coordinator.startNewChat()
        case .restart where canRegenerate: coordinator.regenerate()
        case .copyFile where chat.lastAssistantText != nil: coordinator.copyLastResponse()
        case .quickLook: coordinator.showHistory()
        case .pin where chat.isStreaming: coordinator.stopResponse()
        case .settings: chatCoordinator.showSettings()
        default: return false
        }
        return true
    }

    private var canRegenerate: Bool {
        !chat.isStreaming && chat.session.messages.last?.role == .assistant
    }

    /// 搜索框右侧的头部附加视图：@ 服务器胶囊与附件胶囊；二者都没有时返回 nil。
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        let attachments = chat.pendingAttachments
        let addressed = chatCoordinator.addressedServer(in: vm.query)
        guard !attachments.isEmpty || addressed != nil else { return nil }
        let width =
            (attachments.isEmpty ? 0 : AttachmentsPill.width(for: attachments, metrics))
            + (addressed == nil ? 0 : ComposerChip.width(metrics))
            + (attachments.isEmpty || addressed == nil ? 0 : metrics.spacing.sm)
        return PaletteHeaderAccessory(
            width: width + metrics.spacing.md,
            fieldNames: [], firstIncompleteField: nil,
            view: AnyView(
                HStack(spacing: metrics.spacing.sm) {
                    if let addressed {
                        ComposerChip(symbol: "wrench.and.screwdriver", label: "@\(addressed.slug)")
                    }
                    // 没有时不占位而非空视图：空 HStack 仍会在 @ 胶囊后留出一个间隙。
                    if !attachments.isEmpty {
                        AttachmentsPill(attachments: attachments, onOpen: openAttachments)
                    }
                }
                // 与光标保持距离，避免胶囊看起来叠在最后一个词上。
                .padding(.leading, metrics.spacing.md)))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            AIChatView(
                chat: chat,
                availability: { chatCoordinator.availability(for: chat) },
                onConfigure: chatCoordinator.showSettings,
                onAppear: chatCoordinator.prepareForChat,
                onChoose: { coordinator.send($0) }))
    }
}

/// 面板内的聊天内容视图：无消息时展示空态，否则展示对话记录。
private struct AIChatView: View {
    let chat: AIChatState
    let availability: () -> String?
    let onConfigure: () -> Void
    let onAppear: () -> Void
    let onChoose: (String) -> Void

    var body: some View {
        Group {
            if chat.session.messages.isEmpty {
                // 在 body 中读取，这样 CLI 登录或开启某个提供方后能立即反映。
                let unavailability = availability()
                AIEmptyState(
                    message: chat.notice ?? unavailability,
                    canConfigure: chat.notice != nil || unavailability != nil,
                    onConfigure: onConfigure)
            } else {
                ChatTranscriptView(
                    messages: chat.session.messages,
                    status: chat.liveStatus,
                    usage: chat.usage,
                    surface: .palette,
                    onChoose: chat.isStreaming ? nil : onChoose)
            }
        }
        .onAppear(perform: onAppear)
    }
}

/// 把所有已暂存文件收进一个胶囊：最新文件的图标、其余文件的数量，悬停时显示全部名称。
private struct AttachmentsPill: View {
    @Environment(\.metrics) private var metrics
    let attachments: [ChatAttachment]
    let onOpen: () -> Void

    private static func others(_ attachments: [ChatAttachment]) -> String? {
        attachments.count > 1 ? "+\(attachments.count - 1)" : nil
    }

    /// 关键逻辑：该宽度是 `searchFieldWidth(for:)` 从输入框宽度中扣除的条带宽度的一部分。
    static func width(for attachments: [ChatAttachment], _ metrics: InterfaceMetrics) -> CGFloat {
        let pill = metrics.size.chatAttachmentInset * 2 + metrics.size.chatAttachmentThumb
        guard let others = others(attachments) else { return pill }
        let text = (others as NSString).size(
            withAttributes: [.font: metrics.typography.chipNSFont]
        ).width
        return pill + metrics.spacing.xs + text + metrics.spacing.xs
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: metrics.spacing.xs) {
                if let newest = attachments.last { AttachmentGlyph(attachment: newest) }
                if let others = Self.others(attachments) {
                    Text(others)
                        .font(metrics.typography.chip)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.trailing, metrics.spacing.xs)
                }
            }
            .padding(metrics.size.chatAttachmentInset)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.attachmentChip, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(attachments.map(\.name).joined(separator: "\n"), edge: .bottom)
        .accessibilityLabel(
            attachments.count == 1
                ? "Attached \(attachments[0].name)" : "\(attachments.count) files attached")
    }
}

/// The newest file's kind as a glyph; its picture waits in the menu, where a row has the room.
/// 用图标表示最新文件的类型；它的缩略图留到菜单里显示，因为那里的一行有足够空间。
private struct AttachmentGlyph: View {
    @Environment(\.metrics) private var metrics
    let attachment: ChatAttachment

    var body: some View {
        Image(systemName: attachment.glyph)
            .font(metrics.typography.chip)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: metrics.size.chatAttachmentThumb, height: metrics.size.chatAttachmentThumb)
    }
}

extension ChatAttachment {
    /// 每种类型对应一个图标：用于胶囊，也用于没有可展示图片时的菜单行。
    var glyph: String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.plaintext"
        }
    }

    var menuIcon: PopoverMenuIcon {
        guard case .image = kind, let preview else { return .symbol(glyph) }
        return .thumbnail(id: id, data: preview)
    }
}

/// 聊天顶部栏的模型控件，复用剪贴板过滤器的菜单按钮外观。
struct AIModelButton: View {
    let title: String
    let icon: PopoverMenuIcon
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: title,
            icon: icon,
            isOpen: isOpen,
            help: "Switch AI model  ⌘P",
            action: action
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 聊天顶部栏的推理强度控件（“brain”图标）。
struct AIReasoningButton: View {
    let title: String
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: title,
            systemImage: "brain",
            symbolSize: Theme.Size.barBrandIcon,
            isOpen: isOpen,
            help: "Change reasoning effort",
            action: action
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}
