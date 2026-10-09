// 文件职责：「搜索文件」面板主体：维护行数据与选中，实现复制/粘贴/Quick Look/移入废纸篓等快捷键动作，并组装列表加预览的布局与右键菜单。
// 分层：UI；实现 PaletteScreen 协议，动作转发给 FileSearchCoordinator。
import SwiftUI

/// 「搜索文件」面板的屏幕实现。
struct FileSearchScreen: PaletteScreen {
    let session: FileSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [FileSearchResult] { session.results }

    private var isShowingRecents: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryActionTitle: String {
        guard let result = result(at: vm.selection) else {
            return core.settings.text(FileSearchKey.primaryOpenFile)
        }
        return core.settings.text(
            result.isDirectory ? FileSearchKey.primaryOpenFolder : FileSearchKey.primaryOpenFile)
    }

    private func result(at selection: Int) -> FileSearchResult? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 返回指定选中项的右键菜单内容。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let result = result(at: selection) else { return nil }
        return FileSearchActionsMenu.content(
            result: result, core: core, vm: vm, target: vm.pasteTarget)
    }

    /// 回车激活：打开选中的文件或文件夹。
    func activate(at selection: Int) {
        guard let result = result(at: selection) else { return }
        core.fileSearchCoordinator.open(result)
    }

    /// ⇧回车：在 Finder 中显示选中项。
    func secondary(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        core.fileSearchCoordinator.showInFinder(result)
        return true
    }

    /// 处理与「搜索文件」相关的面板快捷键，未处理则返回 false。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .copyFile: return run(.copyFile, at: selection)
        case .copyName: return run(.copyName, at: selection)
        case .copyPath: return run(.copyPath, at: selection)
        case .pasteFile: return run(.pasteFile, at: selection)
        case .quickLook: return toggleQuickLook(at: selection)
        // 这里没有 ⌃⇧X：不存在「全部」可移入废纸篓，只有当前选中行。
        case .delete: return trash(at: selection)
        default: return false
        }
    }

    /// ⌃X — 与「Actions」菜单项一致，就像剪贴板的删除那样；移入废纸篓不会先询问。
    private func trash(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        core.fileSearchCoordinator.trash(result)
        return true
    }

    /// ⌘Y — 浮层跟随选中项，因此只需切换开关状态即可。
    private func toggleQuickLook(at selection: Int) -> Bool {
        guard result(at: selection) != nil else { return false }
        vm.fileSearchQuickLook.toggle()
        return true
    }

    /// ⇧⌘C / ⌥⌘C / ⌃⌘C / ⇧⌘V — 剪贴板相关操作，作用于菜单会作用的同一选中项。
    private func run(_ action: FileSearchPasteboardAction, at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        let coordinator = core.fileSearchCoordinator
        switch action {
        case .copyFile: coordinator.copyFile(result)
        case .copyName: coordinator.copyName(result)
        case .copyPath: coordinator.copyPath(result)
        case .pasteFile: coordinator.pasteFile(result)
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 面板主体内容：失败、空态与列表加预览三种情况之一。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if session.state == .failed {
            EmptyResults(text: core.settings.text(FileSearchKey.unavailable))
        } else if rows.isEmpty {
            emptyState
        } else {
            let selected = result(at: selection)
            HStack(spacing: 0) {
                FileSearchList(
                    title: core.settings.text(
                        isShowingRecents ? FileSearchKey.listRecentlyUsed : FileSearchKey.listResults),
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { result in vm.selection = rows.firstIndex(of: result) ?? 0 },
                    onActivate: { core.fileSearchCoordinator.open($0) },
                    onActions: { result in
                        if let index = rows.firstIndex(of: result) { vm.selection = index }
                        openActions()
                    },
                    onDropped: { core.paletteCoordinator.dragLanded() }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                FileSearchPreview(result: selected)
            }
            .overlay {
                if vm.fileSearchQuickLook, let selected {
                    FileSearchQuickLook(result: selected) { vm.fileSearchQuickLook = false }
                }
            }
        }
    }

    /// 查询进行中不显示任何提示：它将要替换的旧行只会让提示一闪而过。
    @ViewBuilder
    private var emptyState: some View {
        if session.state != .ready {
            Color.clear
        } else if isShowingRecents {
            EmptyResults(text: core.settings.text(FileSearchKey.emptyPrompt))
        } else {
            EmptyResults(
                text: vm.fileSearchFilter.localizedEmptyMessage(core.settings.resolvedLanguage))
        }
    }
}

/// 可由快捷键触发的剪贴板操作。
enum FileSearchPasteboardAction {
    case copyFile
    case copyName
    case copyPath
    case pasteFile
}

/// 构建文件结果的右键菜单内容。
@MainActor
enum FileSearchActionsMenu {
    /// 生成选中结果对应的菜单项列表。
    static func content(
        result: FileSearchResult, core: AppCore, vm: PaletteState, target: PasteTarget?
    ) -> PopoverMenuContent {
        let coordinator = core.fileSearchCoordinator
        return PopoverMenuContent(
            header: result.name,
            items: [
                PopoverMenuItem(
                    title: core.settings.text(
                        result.isDirectory
                            ? FileSearchKey.menuOpenFolder : FileSearchKey.menuOpenFile),
                    systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
                ) { coordinator.open(result) },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuShowInFinder), systemImage: "folder",
                    shortcut: "⌘↵"
                ) { coordinator.showInFinder(result) },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuQuickLook), systemImage: "eye",
                    shortcut: "⌘Y"
                ) {
                    vm.fileSearchQuickLook = true
                },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuShare),
                    systemImage: "square.and.arrow.up"
                ) {
                    coordinator.share(result)
                },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuCopyFile),
                    systemImage: "doc.on.clipboard", startsSection: true,
                    shortcut: "⇧⌘C"
                ) { coordinator.copyFile(result) },
                PopoverMenuItem(
                    title: target.map {
                        String(format: core.settings.text(FileSearchKey.menuPasteFileTo), $0.name)
                    } ?? core.settings.text(FileSearchKey.menuPasteFile),
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "⇧⌘V"
                ) { coordinator.pasteFile(result) },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuCopyName),
                    systemImage: "doc.on.clipboard", shortcut: "⌥⌘C"
                ) { coordinator.copyName(result) },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuCopyPath),
                    systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
                ) { coordinator.copyPath(result) },
                PopoverMenuItem(
                    title: core.settings.text(FileSearchKey.menuMoveToTrash), systemImage: "trash",
                    startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) { coordinator.trash(result) }
            ])
    }
}
