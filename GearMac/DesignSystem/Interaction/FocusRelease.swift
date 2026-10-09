// 文件职责：点击落在正在编辑的输入框之外时，释放该窗口的键盘焦点，且仅作用于本窗口。
// 分层：UI（SwiftUI/AppKit 事件桥接）；用事件监听器而非手势，避免吞掉点击或抢走焦点。
import AppKit
import SwiftUI

/// 输入框会一直持有 first responder，直到有别的控件接管，而表单空白区域不会抢占焦点。
private struct FocusReleaseOnOutsideClick: ViewModifier {
    @State private var monitor: Any?
    // 用引用盒持有窗口，而不是把 `@State` 放在 window 上：解析窗口不应在布局中途让视图失效。
    @State private var host = HostWindowBox()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { host.window = $0 })
            .onAppear {
                guard monitor == nil else { return }
                // 用事件监听器而非手势：手势会吞掉这次点击或抢走焦点。
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    release(on: event)
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func release(on event: NSEvent) {
        // 本地监听器能看到应用内所有窗口，但只有本面板所在的窗口才是我们要处理的。
        guard let window = event.window, window === host.window,
            // 仅当确实有内容在编辑时（此时 first responder 是 field editor）才处理。
            let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        // 点击正在编辑的输入框或其他文本控件，属于那个控件自己的事。
        guard let hit, !hit.isDescendant(of: editor), !(hit is NSTextView) else { return }
        window.makeFirstResponder(nil)
    }
}

/// 弱引用持有宿主窗口，避免视图与窗口之间形成强引用环。
private final class HostWindowBox {
    weak var window: NSWindow?
}

/// 获取某个 SwiftUI 视图所落的窗口；`NSViewRepresentable` 是拿到它的唯一途径。
private struct HostWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { HostWindowReaderView(onResolve: onResolve) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 在自身加入窗口层级时，把所在窗口回调给上层。
private final class HostWindowReaderView: NSView {
    private let onResolve: (NSWindow?) -> Void

    init(onResolve: @escaping (NSWindow?) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve(window)
    }
}

extension View {
    /// 当点击落在正在编辑的输入框之外时释放键盘焦点，且只影响当前窗口。
    func releasesFocusOnOutsideClick() -> some View {
        modifier(FocusReleaseOnOutsideClick())
    }
}
