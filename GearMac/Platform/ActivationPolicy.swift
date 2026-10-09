// 文件职责：根据是否还有打开的窗口，在 regular / accessory 两种激活策略之间切换，从而控制 Dock 图标的显示。
// 分层：Service；以窗口标识集合为唯一依据，重复开/关窗口不会让 Dock 图标滞留。
import AppKit

/// 以窗口身份（而非计数）为键：重复的打开或关闭不会让 Dock 图标滞留。
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// 每次关闭都会回调 `windowDidClose`，最后一个窗口关闭后才移除 Dock 图标。
    func closeAll() {
        for window in NSApp.windows where openWindows.contains(ObjectIdentifier(window)) {
            window.close()
        }
    }
}
