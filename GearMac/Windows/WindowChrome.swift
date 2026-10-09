// 文件职责：定义窗口装饰（chrome）协议，供 `AppWindowController` 在窗口创建时安装。
// 分层：UI；@MainActor 协议，由 `AppWindowController` 持有至窗口生命周期结束。
import AppKit

/// 由 `AppWindowController` 持有至窗口生命周期结束，使 chrome 随窗口一同销毁。
@MainActor
protocol WindowChrome: AnyObject {
    /// 把装饰安装到给定窗口上。
    func install(in window: NSWindow)
}
