// 文件职责：为 `NSScreen` 补充“鼠标所在显示器”与“主显示器”两个查询。
// 分层：Service；仅依赖 AppKit，不持有状态。
import AppKit

extension NSScreen {
    /// 当前实际使用的显示器；`NSScreen.main` 是键窗口所在的那块，而我们很少拥有键窗口。
    static var underCursor: NSScreen? {
        let mouse = NSEvent.mouseLocation
        // 用 NSMouseInRect 而非 `contains`：否则最上面一行会被判定为上一块显示器。
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// 菜单栏所在的主显示器：位于全局原点的那个，而 `NSScreen.main` 并非如此。
    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }
}
