// 文件职责：为设置窗口安装 NSHostingController 无法直接桥接的窗口标志（标题栏与工具栏样式）。
// 分层：UI（AppKit chrome）；工具栏与标题内容仍由 SwiftUI 负责。
import AppKit

/// `NSHostingController` 无法桥接的窗口标志；工具栏与标题内容仍由 SwiftUI 负责。
@MainActor
final class SettingsWindowChrome: WindowChrome {
    /// 把上述窗口标志应用到给定的设置窗口。
    func install(in window: NSWindow) {
        // 三者共同作用，才让标题以内联、靠左的方式呈现，而不是居中。
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` 会在内容滚动到栏下方时画一条细线，把界面割成两半。
        window.titlebarSeparatorStyle = .none
        // 设为透明会让标题栏退出系统毛玻璃带；设置窗口希望它被绘制出来。
        window.titlebarAppearsTransparent = false
        // 系统「设置」不随内容拖动——在 `Form` 上的拖动不应移动窗口。
        window.isMovableByWindowBackground = false
    }
}
