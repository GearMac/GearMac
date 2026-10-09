// 文件职责：剪贴板历史的操作协调器，统一处理粘贴、复制、揭示、固定、清空与图片文字识别等动作。
// 分层：Coordinator；@MainActor，串联 ClipboardStore、ClipboardManager、Paster 与面板 UI。
import AppKit

/// 负责剪贴板历史动作：粘贴、复制、揭示、固定，以及随之而来的选中状态。
@MainActor
final class ClipboardCoordinator {
    private let clipboardStore: ClipboardStore
    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    /// 用于此处唯一不可撤销动作的对话框。
    private unowned let core: AppCore
    /// 同一时间只允许一次「复制文本」：新的触发会取消旧触发等待中的 helper。
    private var textTask: Task<Void, Never>?
    private var pasteSequence: PasteSequence?

    init(
        clipboardStore: ClipboardStore,
        clipboardManager: ClipboardManager,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteState,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.clipboardStore = clipboardStore
        self.clipboardManager = clipboardManager
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 关闭时轮询停止、数据库关闭，且不再记录任何新内容。
    func applyEnabled() {
        appIndex.setCommandsVisible([.clipboardHistory, .pasteSequentially], settings.clipboardEnabled)
        guard settings.clipboardEnabled else {
            core.applyClipboardTextSearch()
            clipboardManager.stop()
            if palette.mode == .clipboard { palette.prepare(mode: .launcher) }
            clipboardStore.close()
            return
        }
        clipboardStore.open()
        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        clipboardManager.start()
        core.applyClipboardTextSearch()
        // 不阻塞启动路径：面板在 SQLite 读取与清理完成后再填充。
        Task { clipboardStore.load() }
    }

    /// 异步搜索结果返回后，尽量把选中项保持在原来那条条目上。
    func followSearchResults(query: String, previous: [ClipboardItem], current: [ClipboardItem]) {
        guard palette.isVisible, palette.mode == .clipboard,
            palette.query.trimmingCharacters(in: .whitespaces) == query,
            previous.indices.contains(palette.selection)
        else { return }
        let selectedID = previous[palette.selection].id
        if let index = current.firstIndex(where: { $0.id == selectedID }) {
            palette.selection = index
        }
    }

    /// 设置只声明保留时长，由存储层执行；窗口缩短时立即清理。
    func applyRetention(_ retention: ClipboardRetention) {
        clipboardStore.maxAge = retention.maxAge
        clipboardStore.enforceLimits()
    }

    /// ↵ 执行配置的默认动作，其它快捷键按其映射执行；当 `chord` 无映射时返回 false。
    @discardableResult
    func activate(_ item: ClipboardItem, chord: ClipboardChord = .return) -> Bool {
        guard let action = settings.clipboardDefaultAction.action(for: chord, on: item) else {
            return false
        }
        perform(action, on: item)
        return true
    }

    /// 按指定默认动作分派到对应的粘贴或复制实现。
    func perform(_ action: ClipboardDefaultAction, on item: ClipboardItem) {
        switch action {
        case .paste: paste(item)
        case .copy: copyToClipboard(item)
        case .pastePlainText: pasteAsPlainText(item)
        }
    }

    /// 粘贴条目并先隐藏面板，随后选中被提升的条目。
    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        // 粘贴会提升该条目，因此跟随它并保持移动后的行处于高亮。
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// 文件消失后其路径仍是有效文本，因此这里不会报告文件缺失。
    func pasteAsPlainText(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.pastePlainText(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    /// 粘贴条目但保持面板窗口打开。
    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if !windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            reportUnavailable(item)
        }
    }

    /// 每次按下都把下一条更早的条目粘贴到前台应用，且不提升该条目。
    func pasteNextInSequence() {
        let now = Date()
        // 丢弃而非排队，使长按快捷键不会连续粘贴一批条目。
        if let pasteSequence, pasteSequence.isSettling(at: now) { return }
        guard let target = paletteCoordinator.targetApp else { return }
        // 按下前刚发生的复制必须进入历史，否则遍历会晚一个条目开始。
        clipboardManager.prepareForGearMacPasteboardMutation()
        var sequence = continuingPasteSequence(at: now)
        while let item = sequence.next(in: clipboardStore.items) {
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
            // 已从磁盘消失的图片或文件不会写入任何内容，因此继续尝试下一条。
            guard Paster.pasteInPlace(item, store: clipboardStore, into: target) else { continue }
            sequence.recordPaste(changeCount: NSPasteboard.general.changeCount, at: now)
            pasteSequence = sequence
            return
        }
        core.showMessage(settings.text(ClipboardKey.hudNothingToPaste), tone: .neutral)
    }

    /// 上次按下后又有复制，或间隔过久，则从最新条目重新开始遍历。
    private func continuingPasteSequence(at now: Date) -> PasteSequence {
        let changeCount = NSPasteboard.general.changeCount
        if let pasteSequence, pasteSequence.continues(changeCount: changeCount, at: now) {
            return pasteSequence
        }
        return PasteSequence(history: clipboardStore.items, changeCount: changeCount, now: now)
    }

    /// 写入只会在文件消失时失败，而面板随即关闭无法向用户解释原因。
    private func reportUnavailable(_ item: ClipboardItem) {
        guard item.kind == .file else { return }
        core.showMessage(settings.text(ClipboardKey.fileMovedOrDeleted), tone: .danger)
    }

    /// ⌃⇧X 快捷键与菜单项都走这里，二者都无法跳过确认。
    func deleteAllClips() async {
        guard
            await core.confirm(
                title: settings.text(ClipboardKey.deleteAllEntries),
                message: settings.text(ClipboardKey.deleteAllMessage),
                symbol: PaletteMode.clipboard.systemImage,
                confirmTitle: settings.text(ClipboardKey.deleteAllConfirm))
        else { return }
        clearHistory()
    }

    /// 功能关闭时仍可调用，使此前保留的内容之后仍能被清除。
    func clearHistory() {
        clipboardStore.open()
        clipboardStore.clearAll()
        if !settings.clipboardEnabled { clipboardStore.close() }
    }

    /// 复制条目到系统粘贴板，并选中被提升的条目。
    func copyToClipboard(_ item: ClipboardItem) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// 不加标记，使转换出的颜色本身进入历史——它是你主动想保留的一项。
    func copyColor(_ color: ColorValue, as format: ColorFormat) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.string(for: color))
    }

    /// 仅在文件消失时返回 nil，此时由 HUD 报告而不是交出一个失效路径。
    func dragPayload(for item: ClipboardItem) -> ClipDragPayload? {
        let payload = item.dragPayload
        guard case .file = payload else { return payload }
        return clipURL(for: item).map(ClipDragPayload.file)
    }

    /// ⇧⌘T /「Copy Text」——在捆绑的 helper 中对图片做 OCR，并复制识别到的文本。
    func copyImageText(_ item: ClipboardItem) {
        guard let path = item.imagePath ?? item.filePath else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showProgress(settings.text(ClipboardKey.hudReadingText))
        let changeCount = NSPasteboard.general.changeCount
        textTask?.cancel()
        textTask = Task {
            do {
                // 对未挂载卷或网络卷的 stat 可能卡住，因此不放在主 actor 上。
                let exists = await Task.detached { FileManager.default.fileExists(atPath: path) }.value
                try Task.checkCancellation()
                guard exists else {
                    return item.kind == .file
                        ? reportUnavailable(item)
                        : core.showMessage(
                            settings.text(ClipboardKey.imageUnavailable), tone: .danger)
                }
                let text = try await ClipboardTextWorker.extract(item)
                guard !text.isEmpty else {
                    return core.showMessage(
                        settings.text(ClipboardKey.hudNoTextFound), tone: .neutral)
                }
                guard NSPasteboard.general.changeCount == changeCount else {
                    return core.showMessage(
                        settings.text(ClipboardKey.hudClipboardChanged), tone: .neutral)
                }
                Paster.copyPlainText(text)
                core.showMessage(settings.text(ClipboardKey.hudCopiedText))
            } catch is CancellationError {
            } catch {
                core.showMessage(settings.text(ClipboardKey.hudReadFailed), tone: .danger)
            }
        }
    }

    /// 文件消失后返回 nil，使每个动作都给出提示而不是静默无操作。
    private func clipURL(for item: ClipboardItem) -> URL? {
        let url = clipboardStore.imageURL(for: item) ?? clipboardStore.fileURL(for: item)
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            reportUnavailable(item)
            return nil
        }
        return url
    }

    /// 固定或取消固定条目；选中与滚动会跟随移动后的行。
    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    /// 按当前筛选条件选中 `item` 所在行；被移动的行不一定位于索引 0。
    private func selectClip(_ item: ClipboardItem) {
        palette.selection =
            clipboardStore.rowIndex(
                of: item, in: palette.query, filter: palette.clipboardFilter) ?? 0
    }
}
