// 文件职责：应用生命周期委托，把 AppKit 生命周期事件转发给 AppCore，并托管退出流程与 Dock 重新打开行为。
// 分层：App/AppKit 边界（delegate）；自身不持有业务状态，全部委托给 AppCore，避免出现第二套启动顺序。
import AppKit

/// 应用生命周期委托；只负责把 AppKit 回调转交给 `AppCore`。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 防止重复发起退出请求：退出流程是异步的，可能被多次触发。
    private var terminationRequestInFlight = false

    /// 必须在第一个滚动视图创建之前生效，否则滚动条开关会闪现一次默认状态。
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    /// 启动完成后触发 AppCore 唯一的一次启动编排。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅把生命周期交给 AppCore，避免出现第二套启动顺序。
        AppCore.shared.start()
    }

    /// 处理通过 URL scheme 打开应用时传入的链接。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppCore.shared.handleOpenURL(url)
        }
    }

    /// 进程退出前的回调：触发 AppCore 的统一清理（包括还原会存活到进程之外的系统改动）。
    func applicationWillTerminate(_ notification: Notification) {
        // Hyper Key 的 HID 层 Caps Lock 重映射会存活到进程之外；退出前要把按键还原。
        AppCore.shared.prepareForTermination()
    }

    /// 决定如何响应退出请求；需要异步收尾时先返回 `.terminateLater`，收尾完成后回复确认。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dock 图标只代表已打开的窗口，因此从 Dock 退出只会关闭窗口，而不是结束后台 agent。
        let activation = AppCore.shared.activationPolicy
        if isQuitFromDock, activation.hasOpenWindows {
            activation.closeAll()
            return .terminateCancel
        }
        guard !terminationRequestInFlight else { return .terminateLater }
        terminationRequestInFlight = true
        Task { @MainActor [weak self] in
            await AppCore.shared.stopDictationForTermination()
            // 仍有 300 毫秒防抖的草稿需要落盘，但它不再能否决这次退出。
            await AppCore.shared.flushNotesForTermination()
            self?.terminationRequestInFlight = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// 点击 Dock 图标重新激活应用时，交由 AppCore 决定拉起哪个窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    /// 命令面板与设置各自独立关闭；后台 agent 的存活不依赖于任何窗口。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q 和菜单栏项都直接调用 `terminate`，只有 Apple Event 会带上发起者信息。
    private var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
            let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }
}
