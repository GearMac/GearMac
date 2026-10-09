// 文件职责：把某个控件展开的列表放进独立子窗口（`NSPanel`），并计算它在屏幕上的落点与展开方向。
// 分层：UI；子窗口仅作为显示载体，键盘焦点始终留在调色板窗口（`canBecomeKey == false`）。
import AppKit
import SwiftUI

/// 选择器专属窗口，使它的毛玻璃效果与 ⌘K 菜单一样直接采样桌面。
final class ExtensionListPanel: NSPanel {
    weak var paletteState: PaletteState?

    /// 键盘焦点留给调色板：下方控件保持第一响应者并驱动此列表。
    override var canBecomeKey: Bool { false }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// 与 `MenuPanel` 一致：仅真实指针移动才点亮行，其下方滚动不会触发。
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        case .scrollWheel: paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        default: break
        }
        super.sendEvent(event)
    }
}

/// 一次只展示一个控件的列表，挂在调色板窗口之下。
@MainActor
final class ExtensionListPanelController {
    private var panel: ExtensionListPanel?
    private var hosting: NSHostingView<AnyView>?

    /// 在指定位置展示列表内容，并将其作为子窗口挂到 `parent` 之下。
    func present(_ content: AnyView, frame: NSRect, parent: NSWindow, palette: PaletteState) {
        let panel = ensurePanel(state: palette)
        if let hosting {
            hosting.rootView = content
        } else {
            let view = NSHostingView(rootView: content)
            // 窗口尺寸由控件位置决定，因此宿主不得自行调整窗口大小。
            view.sizingOptions = []
            panel.contentView = view
            hosting = view
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        guard panel.parent == nil else { return }
        // 用键盘打开列表时，指针所在处并未选中任何行。
        palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        parent.addChildWindow(panel, ordered: .above)
    }

    /// 关闭并拆掉子窗口，释放托管的视图树。
    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // 直接丢弃而非保留：被托管的视图树会捕获拥有此控制器的控件。
        panel.contentView = nil
        hosting = nil
        self.panel = nil
    }

    private func ensurePanel(state: PaletteState) -> ExtensionListPanel {
        if let panel {
            panel.paletteState = state
            return panel
        }
        let panel = ExtensionListPanel()
        panel.paletteState = state
        self.panel = panel
        return panel
    }
}

/// 列表在屏幕上的落点，以及它展开的方向（供指示箭头使用）。
struct ExtensionListPlacement: Equatable {
    let frame: NSRect
    let flipped: Bool

    /// 以屏幕坐标套用既有布局规则；调色板窗口框仍是列表可占用的空间。
    @MainActor
    init?(anchor: CGRect, in window: NSWindow, height: CGFloat, form: ExtensionFormMetrics) {
        guard let contentHeight = window.contentView?.bounds.height else { return nil }
        let host = window.frame
        // SwiftUI 以左上角为原点向下报告控件坐标；AppKit 则以左下角为原点向上读取窗口坐标。
        let control = window.convertToScreen(
            NSRect(
                x: anchor.minX, y: contentHeight - anchor.maxY, width: anchor.width,
                height: anchor.height))
        let placement = form.placement(
            anchor: CGRect(
                x: control.minX, y: host.maxY - control.maxY, width: control.width,
                height: control.height),
            popoverHeight: height, containerHeight: host.height)
        frame = NSRect(
            x: control.minX, y: host.maxY - placement.y - height,
            width: form.controlWidth, height: height)
        flipped = placement.flipped
    }
}

/// 报告承载某控件的窗口，而不去借用调色板自身的窗口读取器。
struct ExtensionWindowProbe: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ProbeView)?.onResolve = onResolve
    }

    private final class ProbeView: NSView {
        var onResolve: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(window)
        }
    }
}

/// 依据控件已有的状态驱动其列表面板。
private struct ExtensionListPanelModifier<List: View, Revision: Equatable>: ViewModifier {
    let open: Bool
    let height: CGFloat
    /// 绘制列表所依赖的一切内容，使改变它的按键会触发面板重绘。
    let revision: Revision
    @Binding var flipped: Bool
    let list: () -> List

    @State private var controller = ExtensionListPanelController()
    @State private var host: NSWindow?
    @State private var anchor: CGRect = .zero
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }

    /// 驱动同步的键：任一项变化都触发面板重新定位与重绘。
    private struct Key: Equatable {
        let open: Bool
        let height: CGFloat
        let anchor: CGRect
        let revision: Revision
    }

    func body(content: Content) -> some View {
        content
            .background { ExtensionWindowProbe { host = $0 } }
            // 使用全局坐标系而非表单坐标系：面板按屏幕坐标定位。
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                anchor = $0
            }
            .onChange(of: Key(open: open, height: height, anchor: anchor, revision: revision)) {
                sync()
            }
            .onAppear { sync() }
            .onDisappear { controller.hide() }
    }

    private func sync() {
        guard open, let host, anchor.width > 0,
            let placement = ExtensionListPlacement(
                anchor: anchor, in: host, height: height, form: form)
        else {
            controller.hide()
            return
        }
        if flipped != placement.flipped { flipped = placement.flipped }
        // 直接透传而非重新推导：子窗口绝不能与父窗口产生分歧。
        let root = AnyView(list().environment(palette).environment(\.metrics, metrics))
        controller.present(root, frame: placement.frame, parent: host, palette: palette)
    }
}

extension View {
    /// 在独立窗口中打开此控件的列表，方式与打开 ⌘K 菜单一致。
    func extensionListPanel<List: View, Revision: Equatable>(
        open: Bool, height: CGFloat, revision: Revision, flipped: Binding<Bool>,
        @ViewBuilder list: @escaping () -> List
    ) -> some View {
        modifier(
            ExtensionListPanelModifier(
                open: open, height: height, revision: revision, flipped: flipped, list: list))
    }
}
