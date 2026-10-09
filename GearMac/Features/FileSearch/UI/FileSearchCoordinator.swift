// 文件职责：把「搜索文件」与各子系统（设置、搜索会话、面板、窗口、剪贴板/分享）编排起来，提供打开、定位、复制、粘贴、分享、移入废纸篓等操作。
// 分层：Coordinator；@MainActor，持有 AppCore 与各协作对象。
import AppKit

/// 「搜索文件」功能的动作编排器。
@MainActor
final class FileSearchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: FileSearchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let windowController: PaletteWindowController
    private var sharePicker: NSSharingServicePicker?
    private unowned let core: AppCore

    init(
        settings: AppSettings, appIndex: AppIndex, session: FileSearchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        windowController: PaletteWindowController, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.windowController = windowController
        self.core = core
    }

    /// 根据开关状态同步命令可见性，关闭时取消会话并退出文件搜索模式。
    func applyEnabled() {
        appIndex.setCommandsVisible([.searchFiles], settings.fileSearchEnabled)
        guard !settings.fileSearchEnabled else { return }
        session.cancel()
        if palette.mode == .fileSearch { palette.prepare(mode: .launcher) }
    }

    /// 把最新设置中的搜索范围与忽略模式应用到会话。
    func applyPolicy() {
        session.apply(
            scopes: settings.fileSearchScopes, ignorePatterns: settings.fileSearchIgnorePatterns)
    }

    /// `query` 来自兜底行：界面打开时已经按输入内容做了过滤。
    func show(query: String = "") {
        guard settings.fileSearchEnabled else { return }
        paletteCoordinator.togglePalette(mode: .fileSearch, seeding: query.isEmpty ? nil : query)
    }

    /// 用系统默认应用打开该结果，失败时弹出通知。
    func open(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    result.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: String(
                        format: settings.text(FileSearchKey.noticeOpenFailed), result.name),
                    message: error.localizedDescription,
                    symbol: result.isDirectory ? "folder" : "doc", tone: .danger)
            }
        }
    }

    /// 在 Finder 中显示该结果。
    func showInFinder(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(result.url)
    }

    /// macOS 自带的分享面板，锚定在面板右缘，使目标行保持在它旁边。
    func share(_ result: FileSearchResult) {
        guard let provider = NSItemProvider(contentsOf: result.url),
            let anchor = paletteCoordinator.anchorView
        else { return }
        let picker = NSSharingServicePicker(items: [provider])
        sharePicker = picker
        picker.show(
            relativeTo: CGRect(
                x: anchor.bounds.maxX, y: anchor.bounds.midY, width: 0, height: 0),
            of: anchor, preferredEdge: .maxX)
    }

    /// 复制结果的路径到剪贴板。
    func copyPath(_ result: FileSearchResult) {
        Paster.copyPlainText(result.id)
        core.showMessage(settings.text(FileSearchKey.messageCopiedPath))
    }

    /// 复制结果的文件名到剪贴板。
    func copyName(_ result: FileSearchResult) {
        Paster.copyPlainText(result.name)
        core.showMessage(settings.text(FileSearchKey.messageCopiedName))
    }

    /// 复制文件本身而非路径，因此 Finder 和 Mail 粘贴出来的是文件副本。
    func copyFile(_ result: FileSearchResult) {
        PasteboardFiles.write(result.url, to: .general)
        core.showMessage(settings.text(FileSearchKey.messageCopiedFile))
    }

    /// 粘贴到呼出面板时所处的前台应用，也就是该行标题所标明的目标。
    func pasteFile(_ result: FileSearchResult) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteFile(result.url, previousApp: previous)
    }

    /// 把结果移入废纸篓，成功后从会话结果中移除，失败则弹出通知。
    func trash(_ result: FileSearchResult) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: result.url, resultingItemURL: nil)
                }.value
                session.remove(result)
                core.showMessage(settings.text(FileSearchKey.messageMovedToTrash))
            } catch {
                await core.showNotice(
                    title: String(
                        format: settings.text(FileSearchKey.noticeTrashFailed), result.name),
                    message: error.localizedDescription,
                    symbol: "trash", tone: .danger)
            }
        }
    }
}
