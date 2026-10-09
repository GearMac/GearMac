// 文件职责：统一创建与展示应用的独立窗口，首次显示时构建、关闭时销毁，使 SwiftUI 树能顺利释放。
// 分层：Coordinator；@MainActor，窗口关闭时不经由自身退出应用。
import AppKit
import SwiftUI

/// 支持按 Esc 关闭的 `NSWindow` 子类。
private final class AppWindow: NSWindow {
    var closesOnEscape = false

    /// 响应 Esc：允许关闭时关窗，否则交回父类默认行为。
    override func cancelOperation(_ sender: Any?) {
        if closesOnEscape { close() } else { super.cancelOperation(sender) }
    }
}

/// 首次显示时才构建、关闭时即拆除，使其 SwiftUI 树能释放。永远不会退出应用。
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let title: String
    private let contentSize: CGSize
    private let minimumSize: CGSize
    private let isResizable: Bool
    private let autosaveName: String?
    private let activation: ActivationPolicy
    private let closesOnEscape: Bool
    private var window: NSWindow?
    /// 与窗口一同重建，使 chrome 的状态不会比它装饰的窗口存续更久。
    private var chrome: WindowChrome?

    /// 除另指定更小的 `minimumSize` 外，打开尺寸同时也是缩放下限。
    init(
        title: String, contentSize: CGSize, minimumSize: CGSize? = nil, resizable: Bool = false,
        autosaveName: String? = nil, activation: ActivationPolicy, closesOnEscape: Bool = false
    ) {
        self.title = title
        self.contentSize = contentSize
        self.minimumSize = minimumSize ?? contentSize
        self.isResizable = resizable
        self.autosaveName = autosaveName
        self.activation = activation
        self.closesOnEscape = closesOnEscape
    }

    /// 返回 `true` 表示新建了窗口，`false` 表示只是把已打开的窗口重新置前。
    @discardableResult
    func show<Content: View>(
        chrome: WindowChrome? = nil, @ViewBuilder content: () -> Content
    ) -> Bool {
        let root = content()
        return show(chrome: chrome) {
            let hosting = NSHostingController(rootView: root)
            // 保持窗口尺寸为准：无约束的填充会反过来驱动 frame。
            hosting.sizingOptions = []
            return hosting
        }
    }

    /// 接受预先构建好的 controller；设置页需要它来把 SwiftUI 工具栏桥接进窗口。
    @discardableResult
    func show(chrome: WindowChrome? = nil, contentViewController: () -> NSViewController) -> Bool {
        if let window {
            raise(window)
            return false
        }
        let window = makeWindow(content: contentViewController(), chrome: chrome)
        self.chrome = chrome
        self.window = window
        activation.windowDidOpen(window)
        raise(window)
        return true
    }

    /// 将已打开的窗口重新置前而不重建；没有窗口时返回 `false`。
    @discardableResult
    func focus() -> Bool {
        guard let window else { return false }
        raise(window)
        return true
    }

    /// 关闭当前窗口。
    func close() {
        window?.close()
    }

    /// 标题栏位于 frame 之内、布局区域之外，因此需要把它加回高度中。
    func fitContent(width: CGFloat, height: CGFloat) {
        guard let window else { return }
        let titlebar = window.frame.height - window.contentLayoutRect.height
        let size = CGSize(width: width, height: height + titlebar)
        guard window.contentMinSize != size else { return }
        let top = window.frame.maxY
        window.contentMinSize = size
        window.setContentSize(size)
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    /// 窗口即将关闭：清除引用并更新激活策略。
    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        self.window = nil
        self.chrome = nil
        activation.windowDidClose(window)
    }

    // MARK: - Private

    /// 根据配置创建并配置 `NSWindow`。
    private func makeWindow(content: NSViewController, chrome: WindowChrome?) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable { style.insert(.resizable) }
        let window = AppWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.closesOnEscape = closesOnEscape
        // 在透明标题栏下铺满到边，使其读起来是同一个表面。
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // 否则 AppKit 会在启动时（任何东西接好之前）就恢复该窗口。
        window.isRestorable = false
        window.contentMinSize = minimumSize
        window.delegate = self
        // 先于内容安装：桥接的 SwiftUI 工具栏会恢复它所覆盖的标题标志位。
        chrome?.install(in: window)

        window.contentViewController = content
        // `contentViewController` 会把 frame 重置为 controller 的适应尺寸。
        window.setContentSize(contentSize)

        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
            if !window.setFrameUsingName(autosaveName) { window.center() }
        } else {
            window.center()
        }
        return window
    }

    /// 最小化时先恢复，再激活应用并将窗口置前。
    private func raise(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `NSApp.activate` 是异步的，因此在下一轮再次置前——但绝不作用于其间已关闭的窗口。
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
