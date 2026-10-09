// 文件职责：在 Cocoa 的 NSScreen 坐标与窗口管理使用的 AX 坐标空间之间做转换，并输出布局可引用的显示器清单。
// 分层：Service；坐标转换是对 maxY 的翻转（对合变换），每个命令只快照一次锚点高度，避免混用不同锚点。
import AppKit
import ColorSync

/// 唯一的 Cocoa↔AX 坐标转换器。参见 docs/features/window-management.md#coordinate-space。
struct AXGeometry {
    let anchorHeight: CGFloat

    /// 每个命令只快照一次：`NSScreen.screens` 可能变化，混用不同锚点会导致转换错误。
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    /// 通过 `maxY` 做的对合（involution）翻转，从不缩放。docs/features/window-management.md
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// 显示器集合，已转换到几何层所使用的 AX 坐标空间。
@MainActor
enum AXScreens {
    /// 所有 Cocoa 屏幕统一用同一个快照锚点翻转，绝不各用各的。
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        screens.enumerated().map { index, screen in
            // 没有编号的显示器在这次调用中仍需要一个稳定、不冲突的 id。
            return WindowPlacementEngine.Screen(
                id: displayID(screen).map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(screen.visibleFrame))
        }
    }

    /// 布局可命名的所有已连接显示器，从左到右排列，并带有其持久身份标识。
    static func layoutScreens(geometry: AXGeometry) -> [WindowLayoutScreen] {
        let screens = NSScreen.screens
        let converted = converted(screens, geometry: geometry)
        let ordered = WindowPlacementEngine.ordered(converted)
        return ordered.compactMap { screen in
            guard let index = converted.firstIndex(where: { $0.id == screen.id }),
                let uuid = uuid(of: screens[index])
            else { return nil }
            return WindowLayoutScreen(
                display: WindowLayoutDisplay(uuid: uuid, name: screens[index].localizedName),
                screen: screen)
        }
    }

    /// 转成小写，保证存储的身份与当前的身份不会因大小写而互相错过。
    static func uuid(of screen: NSScreen) -> String? {
        guard let id = displayID(screen),
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.lowercased()
    }

    /// 读取屏幕对应的 CGDirectDisplayID（取自 deviceDescription）。
    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
