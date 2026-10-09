// 文件职责：构建聊天顶部栏的模型、推理强度与已暂存文件三类菜单的内容与高亮行。
// 分层：UI（SwiftUI/菜单内容模型）；仅把 AIChatCoordinator 的数据转换成 PopoverMenuContent，不直接改动可变状态。
import SwiftUI

/// 聊天顶部栏的模型、推理强度与已暂存文件菜单，以及每个菜单打开时应选中的行。
@MainActor
enum AIModelMenu {
    /// 所有已为聊天配置的模型；选中某个会同时切换当前会话与默认模型。
    static func models(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        let groups = coordinator.modelGroups
        let loading = coordinator.isModelCatalogLoading
        var items = groups.flatMap { group in
            group.options.enumerated().map { index, option in
                PopoverMenuItem(
                    title: option.title, icon: option.menuIcon,
                    sectionTitle: index == 0 ? group.title : nil
                ) {
                    coordinator.selectModel(option, in: chat)
                }
            }
        }
        if loading {
            items.insert(
                PopoverMenuItem(title: "Loading models…", icon: .blank, isLoading: true) {}, at: 0)
        }
        guard !items.isEmpty else {
            return PopoverMenuContent(items: [
                PopoverMenuItem(title: "Configure AI", systemImage: "slider.horizontal.3") {
                    coordinator.showSettings()
                }
            ])
        }
        return PopoverMenuContent(items: items)
    }

    /// 推理强度菜单：列出当前模型可选的 effort，并在已选项上打勾。
    static func reasoning(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        let selected = coordinator.model(for: chat)?.effort
        return PopoverMenuContent(
            items: coordinator.reasoningEfforts(for: chat).map { effort in
                PopoverMenuItem(
                    title: effort.title, icon: .blank,
                    detail: effort.id == selected ? "✓" : nil
                ) {
                    coordinator.selectReasoningEffort(effort, in: chat)
                }
            })
    }

    /// 每个已暂存文件一行，名字旁带有 ✕：点中某行只移除那一个文件。
    static func attachments(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        var items = chat.pendingAttachments.map { attachment in
            PopoverMenuItem(
                title: attachment.name, icon: attachment.menuIcon, detail: "✕"
            ) {
                coordinator.removeAttachment(attachment.id, in: chat)
            }
        }
        if items.count > 1 {
            items.append(
                PopoverMenuItem(
                    title: "Remove All", systemImage: "xmark.circle", startsSection: true
                ) {
                    coordinator.clearAttachments(in: chat)
                })
        }
        return PopoverMenuContent(header: "Attached", items: items)
    }

    /// 模型菜单打开时应高亮的下标行（已被加载行偏移修正）。
    static func modelHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int {
        let options = coordinator.modelOptions
        // 还没有可选项时，加载行是菜单里唯一的行。
        guard !options.isEmpty else { return 0 }
        let offset = coordinator.isModelCatalogLoading ? 1 : 0
        let selectedIndex =
            coordinator.model(for: chat).flatMap { selected in
                options.firstIndex(where: { $0.matches(selected) })
            } ?? 0
        return offset + selectedIndex
    }

    /// 推理强度菜单打开时应高亮的下标行。
    static func reasoningHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int {
        let selected = coordinator.model(for: chat)?.effort
        return coordinator.reasoningEfforts(for: chat).firstIndex { $0.id == selected } ?? 0
    }
}
