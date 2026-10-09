// 文件职责：窗口命令的统一执行入口，把调色板行、全局热键与自定义尺寸请求分派给窗口搬运器或空间切换器。
// 分层：Coordinator；@MainActor，所有入口均受 windowManagementEnabled 开关门禁。
import AppKit

/// 从调色板行或全局热键到窗口搬运器的唯一入口。
@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover
    private let spaceSwitcher: SpaceSwitcher
    private let customSizes: CustomWindowSizeStore

    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover,
        spaceSwitcher: SpaceSwitcher, customSizes: CustomWindowSizeStore
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
        self.spaceSwitcher = spaceSwitcher
        self.customSizes = customSizes
    }

    /// 调色板与热键共用的唯一入口。参见 docs/features/window-management.md#wiring。
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        if let direction = SpaceDirection(id) {
            // 恢复焦点会重新激活另一个 Space 中的 App，从而把它的 Space 拉到前面。
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            spaceSwitcher.perform(direction)
            return
        }
        windowMover.perform(
            id, target: handOffTarget(), gap: CGFloat(settings.windowGap),
            cycle: settings.windowCycle)
    }

    /// 自定义尺寸走同一入口，使其受功能开关的控制方式完全一致。
    func runCustomWindowSize(id: UUID) {
        guard settings.windowManagementEnabled, let size = customSizes.size(id: id) else { return }
        windowMover.perform(size, target: handOffTarget(), gap: CGFloat(settings.windowGap))
    }

    /// 要放置的窗口；在调色板隐藏并将焦点交还之前读取。
    private func handOffTarget() -> WindowTarget? {
        guard paletteCoordinator.isVisible else { return WindowTarget.current() }
        let target = WindowTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
        paletteCoordinator.hidePalette(restoreFocus: true)
        return target
    }
}
