// 文件职责：通过辅助功能（AX）API 读取指定进程当前聚焦元素中的选中文本，兼顾浏览器标记范围选区。
// 分层：Service；所有查询都针对具名进程而非系统级焦点，并设置消息超时以免卡住调用方。
import AppKit
// `@preconcurrency` 下调 AX 相关诊断：这些属性键是常量 C 全局变量。
@preconcurrency import ApplicationServices

/// 始终针对具名进程查询：系统级焦点会返回我们自己的进程。
enum AccessibilityText {
    /// 对响应正常的应用足够宽松，又足够短，避免卡死的应用阻塞 main actor。
    private static let timeout: Float = 1

    /// 这两种情况的修复方式不同：合并会让提示变成“选中你已选中的内容”。
    enum Selection: Equatable {
        case text(String)
        case noFocusedElement
        case empty
    }

    /// 返回该进程当前聚焦的 UI 元素，取不到时返回 nil。
    static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // 超时按元素设置且不会被继承，因此面对挂起的应用，聚焦元素需要自己再设一次。
        AXUIElementSetMessagingTimeout(application, timeout)
        activateManualAccessibility(of: application)
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    /// 读取聚焦元素中选中的文本，并区分“无聚焦元素”与“选区为空”。
    static func read(in app: NSRunningApplication) -> Selection {
        guard let element = focusedElement(in: app) else { return .noFocusedElement }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value)
        if status == .success, let text = value as? String, !text.isEmpty { return .text(text) }
        guard let web = webSelection(in: element), !web.isEmpty else { return .empty }
        return .text(web)
    }

    /// 更窄的接口，面向只需要拿到文本、不关心为何没有文本的调用方。
    static func selection(in app: NSRunningApplication) -> String? {
        guard case .text(let text) = read(in: app) else { return nil }
        return text
    }

    /// Chromium 只在被请求时才构建辅助功能树，所以 Chrome 与 Electron 在此调用前不会有任何应答。
    private static func activateManualAccessibility(of application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// 浏览器没有 `AXSelectedText`：网页选区只以不透明的标记范围形式存在。
    private static func webSelection(in element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &range) == .success,
            let range,
            CFGetTypeID(range) == AXTextMarkerRangeGetTypeID()
        else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
                range,
                &value) == .success
        else { return nil }
        return value as? String
    }
}
