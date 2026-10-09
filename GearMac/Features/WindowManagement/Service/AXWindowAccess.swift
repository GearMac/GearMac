// 文件职责：集中封装本功能所有对 AXUIElement 的调用（查找窗口、聚焦/置前、读写窗口位置与尺寸）。
// 分层：Service；@MainActor 隔离，AX 句柄不跨 actor，默认消息超时限制为 1 秒以免卡住主线程。
// Portions adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
// `@preconcurrency` 用于降级 AX 相关诊断：`kAX…` 是可变 C 全局量，但实际为常量。
@preconcurrency import ApplicationServices

/// 本功能中所有 `AXUIElement` 调用集中于此。共享实现，保证 mover 与 layout runner 对“窗口是什么、如何写入”不会产生分歧。
@MainActor
enum AXWindowAccess {
    /// 挂起的进程不能因为 AX 默认超时而拖住主线程。按元素设置，绝不继承。
    static let messagingTimeout: Float = 1
    /// 检查应用是否遵守了我们请求的尺寸时所用的容差。
    static let clampTolerance: CGFloat = 2

    static let fullScreenAttribute = "AXFullScreen" as CFString
    static let fullScreenButtonAttribute = "AXFullScreenButton" as CFString

    // MARK: - Finding windows

    /// 按 pid 创建应用级 AXUIElement，并设置消息超时。
    static func application(for pid: pid_t, timeout: Float = messagingTimeout) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    /// 命令作用的窗口：优先聚焦窗口，其次是主窗口，最后是第一个符合条件的窗口。
    static func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(application, attribute), isEligible(window) { return window }
        }
        return windows(in: application).first(where: isEligible)
    }

    /// 应用上报的所有窗口，未过滤，保持其自身顺序。
    static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    /// 真实、可恢复的窗口：不是 sheet、popover 或最小化的窗口，且能上报几何信息。
    static func isEligible(_ window: AXUIElement) -> Bool {
        guard string(window, kAXRoleAttribute) == (kAXWindowRole as String) else { return false }
        if bool(window, kAXMinimizedAttribute) == true { return false }
        return frame(of: window) != nil
    }

    /// 窗口是否处于原生全屏。
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    // MARK: - Bringing one forward

    /// 取消窗口最小化；返回是否设置成功。
    static func unminimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            == .success
    }

    /// 先在应用内提升该窗口，再把应用本身置前。
    static func focus(
        _ window: AXUIElement, in application: AXUIElement, of app: NSRunningApplication
    ) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // 与 `activate()` 双保险：agent 策略的应用可能忽略请求。
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// 跨应用把窗口置前：仅靠 raise 只会改变它在其所属应用内的顺序。
    static func raise(_ window: AXUIElement, in application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// 对拒绝 `NSRunningApplication.hide()` 或 `unhide()` 的应用的兜底方案。
    static func setHidden(_ hidden: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXHiddenAttribute as CFString, hidden ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// 基于 Web 的应用在开启此项前不会列出任何窗口，而开启期间又会绘制聚焦环。
    static func setManualAccessibility(_ enabled: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString,
            enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    // MARK: - Window identity

    /// 窗口服务器分配的编号，比任何 `AXUIElement` 存活得更久。参见 window-rooms.md。
    static func windowID(of window: AXUIElement) -> UInt32? {
        guard let copyWindowID else { return nil }
        var id: CGWindowID = 0
        return copyWindowID(window, &id) == .success && id != 0 ? id : nil
    }

    private typealias CopyWindowID =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// 私有符号，因此在运行时解析：缺少它的 macOS 会退化为使用标题，而不会崩溃。
    private static let copyWindowID: CopyWindowID? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: CopyWindowID.self)
    }()

    // MARK: - Writing a frame

    /// 唯一的写入序列，使顽固的应用从任何调用方写入都能落到相同结果。
    /// 参见 docs/features/window-management.md#applying-a-placement。
    static func write(
        _ target: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement,
        current: CGRect, canResize: Bool, canvas: CGRect?
    ) -> CGRect? {
        guard canResize else {
            // 它拒绝缩放，因此把它当前的尺寸放进槽位后即停止。
            var slot = anchor.place(current.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            guard setPosition(WindowPlacementEngine.rounded(slot).origin, on: window) else {
                return nil
            }
            return frame(of: window) ?? current
        }

        // size → position → size。参见 docs/features/window-management.md#applying-a-placement。
        _ = setSize(target.size, on: window)
        guard setPosition(target.origin, on: window) else {
            _ = setSize(current.size, on: window)  // 回滚这次缩小；肉眼看不到窗口移动过。
            return nil
        }
        _ = setSize(target.size, on: window)

        guard var actual = frame(of: window) else { return target }

        // 第二次缩放可能移动原点：有些应用以不同的角作为锚点。
        if abs(actual.minX - target.minX) > clampTolerance
            || abs(actual.minY - target.minY) > clampTolerance
        {
            _ = setPosition(target.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        // 应用强加的最小尺寸：按锚点重新放置一次。不做循环，否则会抖动。
        if actual.width > target.width + clampTolerance
            || actual.height > target.height + clampTolerance
        {
            var slot = anchor.place(actual.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            _ = setPosition(WindowPlacementEngine.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }

    /// 仅在写入期间清除，VoiceOver 运行时绝不清除。参见 docs/features/window-management.md。
    static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
            (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    // MARK: - Primitives

    /// 读取窗口当前的 frame，缺少位置或尺寸时返回 nil。
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
            let size = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func axValue(
        _ element: AXUIElement, _ attribute: String, type: AXValueType
    ) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // 上面已用 CFGetTypeID 做过类型检查；对 CF 类型使用 `as?` 是编译错误。

        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // 上面已用 CFGetTypeID 做过类型检查；对 CF 类型使用 `as?` 是编译错误。

        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    /// 指定属性是否可在该元素上写入。
    static func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
