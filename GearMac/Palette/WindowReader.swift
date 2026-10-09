// 文件职责：用一个隐藏的 NSView 上报承载 SwiftUI 视图树的 NSWindow，供需要依附窗口 frame 的 AppKit 表面使用。
// 分层：UI（SwiftUI/AppKit 桥接）；只上报宿主窗口，不参与布局与业务逻辑。
import AppKit
import SwiftUI

/// 上报承载 SwiftUI 视图树的 `NSWindow`，供依附其 frame 的 AppKit 表面使用。
struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // 视图进入层级前 window 为 nil；面板不会在窗口之间移动，因此只需上报一次。
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    /// 视图更新时无需同步任何内容，故为空实现。
    func updateNSView(_ view: NSView, context: Context) {}
}
