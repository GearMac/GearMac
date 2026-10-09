// 文件职责：定义「拒绝键盘焦点」标记协议与查询入口，让带输入框的区域不抢占键盘焦点。
// 分层：UI（AppKit 辅助）；标记挂在祖先视图上，因此需向上遍历父视图判断。
import AppKit

/// 整个子树都不接受键盘的视图：例如预览的播放控制条，键盘由输入框独占。
protocol KeyboardFocusRefusing: NSView {}

extension NSView {
    /// 用于询问某个潜在的 first responder：标记位于祖先视图上，而不在被命中的控件本身。
    var refusesKeyboardFocus: Bool {
        sequence(first: self, next: { $0.superview }).contains { $0 is KeyboardFocusRefusing }
    }
}
