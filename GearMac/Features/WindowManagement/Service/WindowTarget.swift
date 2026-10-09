// 文件职责：判定一条窗口命令要作用的目标——另一个应用的窗口，或 GearMac 自身的窗口。
// 分层：Service；@MainActor 隔离，面板不激活，因此不能简单以最前台应用作为目标。
import AppKit

/// 窗口命令要摆放的目标。参见 docs/features/window-management.md#choosing-a-target。
@MainActor
enum WindowTarget {
    case external(NSRunningApplication)
    case own(NSWindow)

    /// 我们的面板从不激活，因此最前台应用并不是用户正在看的那个。
    static func current() -> WindowTarget? {
        if let own = NSApp.keyWindow.flatMap(placeable) { return .own(own) }
        return NSWorkspace.shared.frontmostApplication.map(WindowTarget.external)
    }

    /// 面板遮住屏幕时，从它当时记录下来的信息得到相同答案。
    static func behindPalette(
        ownWindow: NSWindow?, app: NSRunningApplication?
    ) -> WindowTarget? {
        if let own = ownWindow.flatMap(placeable) { return .own(own) }
        return app.map(WindowTarget.external)
    }

    /// 取窗口本身，或它的父窗口：快速笔记切换器是它所覆盖编辑器的 key 子窗口。
    private static func placeable(_ window: NSWindow) -> NSWindow? {
        [window, window.parent].compactMap { $0 }.first(where: isPlaceable)
    }

    /// 应用里每个临时面板都拒绝 `canBecomeMain`，这就只剩下真正的窗口。
    private static func isPlaceable(_ window: NSWindow) -> Bool {
        window.isVisible && window.canBecomeMain && window.isMovable
    }
}
