// 文件职责：定义 GearMac 自定义窗口层级（palette、拖拽辅助、dialog）。
// 分层：Model；仅基于 AppKit 的 `NSWindow.Level` 做常量派生。
import AppKit

extension NSWindow.Level {
    /// 位于 `.modalPanel` 之上，即其他应用打开的浮动面板与作为窗口的 sheet 所在层。
    static let palette = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
    /// 比 palette 低一层，使参考线能盖过其他应用、但不会盖住正在拖拽的面板。
    static let paletteDropGuide = NSWindow.Level(rawValue: palette.rawValue - 1)
    /// 高于 palette，使确认框永远不会被触发它的面板遮挡。
    static let dialog = NSWindow.Level(rawValue: palette.rawValue + 1)
}
