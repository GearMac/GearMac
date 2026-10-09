// 文件职责：编排调色板的召唤与隐藏、模式跳转、查询注入与拖拽起止，连接状态、各搜索会话与窗口控制器。
// 分层：Coordinator；@MainActor，只负责「什么时候显示哪个模式」，位置与尺寸交给窗口控制器。
import AppKit

/// 只负责召唤调色板，其余不管；位置与尺寸保留在控制器中。
@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let fileSearch: FileSearchSession
    private let menuSearch: MenuSearchSession
    private let windowSwitch: WindowSwitchSession
    private let windowController: PaletteWindowController
    /// 启动器行数据来自 GearMac 外部读取的那些功能，每次打开都重新读取。
    var onLauncherShown: (() -> Void)?
    /// 快照其它应用的屏幕在每次打开时都重新读取，包括恢复回来的屏幕。
    var onScreenOpening: ((PaletteMode) -> Void)?

    init(
        palette: PaletteState,
        settings: AppSettings,
        appIndex: AppIndex,
        fileSearch: FileSearchSession,
        menuSearch: MenuSearchSession,
        windowSwitch: WindowSwitchSession,
        windowController: PaletteWindowController
    ) {
        self.palette = palette
        self.settings = settings
        self.appIndex = appIndex
        self.fileSearch = fileSearch
        self.menuSearch = menuSearch
        self.windowSwitch = windowSwitch
        self.windowController = windowController
    }

    // MARK: - Palette control

    var isVisible: Bool { windowController.isVisible }

    var panelFrame: CGRect? { windowController.visibleFrame }

    /// 调色板自己的视图，供锚定在它之上的 AppKit UI 使用——例如分享选择器。
    var anchorView: NSView? { windowController.anchorView }

    /// 动作作用的目标应用：优先被遮住的那个，否则是热键发现的前台应用。
    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    /// 调色板遮住的那个自己的窗口，供它在隐藏后仍需要操作该窗口的场景使用。
    var previousOwnWindow: NSWindow? { windowController.previousOwnWindow }

    /// 已显示且指向 `mode`；这也是模式命令第二次调用时关闭的状态。
    func isShowing(_ mode: PaletteMode) -> Bool {
        windowController.isVisible && palette.mode == mode
    }

    /// 切换启动器：已显示启动器则隐藏，否则以启动器模式显示。
    func togglePalette() {
        if isShowing(.launcher) {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    /// 带查询的调用总是打开：它是新输入，而不是会触发关闭的第二次按下。
    func togglePalette(mode: PaletteMode, seeding query: String? = nil) {
        if isShowing(mode), query == nil {
            hidePalette()
        } else {
            showPalette(mode: mode, seeding: query)
        }
    }

    /// 导航时把当前屏幕压栈作为返回层；启动器是根屏幕，永远没有返回层。
    func navigate(to mode: PaletteMode) {
        if windowController.isVisible, palette.mode != mode, mode != .launcher {
            palette.push(mode: mode)
        } else {
            palette.prepare(mode: mode)
        }
    }

    /// 显示调色板，遵循 Pop to Root Search 行为。参见 docs/features/palette.md#state-flow。
    func showPalette(
        mode: PaletteMode, restoreAnyMode: Bool = false, seeding query: String? = nil
    ) {
        let preserved = windowController.consumePreservedState()
        let restoring = preserved && (restoreAnyMode || palette.mode == mode)
        // 重置已被 pop to root 重置过的屏幕，只会无意义地重渲染整个调色板。
        let alreadyFresh = windowController.isPoppedToRoot && palette.mode == mode
        // 携带查询时总是重新打开屏幕：恢复上一个会丢掉该查询。
        if query != nil || !(restoring || alreadyFresh) {
            navigate(to: mode)
        }
        if let query { palette.query = query }
        // 在显示之前：`targetApp` 必须仍指向前台应用，且不得让任何行突兀出现。
        onScreenOpening?(palette.mode)
        windowController.show()
        if palette.mode == .fileSearch { fileSearch.search(palette.query) }
        if palette.mode == .menuSearch { menuSearch.filter(palette.query) }
        if palette.mode == .switchWindows { windowSwitch.filter(palette.query) }
        // 打开时重新扫描，使上次扫描后已卸载的应用从启动器中消失。
        if palette.mode == .launcher {
            Task { await appIndex.refresh() }
            onLauncherShown?()
        }
    }

    /// 将根搜索收敛到 `entry` 单行，就像 Raycast 打开一个快捷键不便带值的命令。
    func showArguments(of entry: AppEntry, values: [String: String]) {
        showPalette(mode: .launcher, seeding: entry.name)
        // 在显示之后设置：`prepare` 在其中运行，会清空此前设置的一切。
        palette.argumentEntryID = entry.id
        for (field, value) in values {
            palette.commandArguments[PaletteState.argumentKey(entry.id, field)] = value
        }
        palette.pendingArgumentEntryID = entry.id
    }

    /// 隐藏调色板：取消各搜索会话并交由窗口控制器隐藏。
    func hidePalette(restoreFocus: Bool = true) {
        fileSearch.cancel()
        menuSearch.reset()
        windowSwitch.reset()
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// 拖出的行已落下即任务完成，调色板像粘贴后一样退场。
    func dragLanded() {
        hidePalette(restoreFocus: false)
    }

    /// 立即回到根搜索，而不等 Pop to Root Search 的延时。
    func popToRootNow() {
        windowController.popToRootNow()
    }

    /// 细窄紧凑栏为 true：紧凑模式开启、处于启动器根、查询为空、且未溢出。
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 紧凑栏的溢出：无需输入即展开为完整启动器。
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// 在打开状态下切换时，把面板调整为当前折叠状态对应的尺寸。
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    // MARK: - Dragging

    /// 括住一次拖拽手势；把手把自身从鼠标按下追踪到松开。
    func beginPaletteDrag() {
        windowController.beginDrag()
    }

    func endPaletteDrag() {
        windowController.endDrag()
    }
}
