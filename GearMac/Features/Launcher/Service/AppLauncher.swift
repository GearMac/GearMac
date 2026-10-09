// 文件职责：封装对 NSWorkspace / Finder 的启动、打开、显示、切换、退出与重启等应用级操作。
// 分层：Service（AppKit 副作用层）；除 AppleScript 与等待退出的辅助方法外均限定在 @MainActor。
import AppKit

/// 应用启动与生命周期操作的统一入口，全部通过 NSWorkspace 执行。
enum AppLauncher {

    /// 以系统默认配置打开指定 URL 指向的应用。
    @MainActor
    static func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 把 URL 交给系统为其 scheme 注册的处理程序——网页则交给默认浏览器。
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 在文件管理器中选中并显示该文件，必要时把文件查看器提到前台。
    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        bringFileViewerForwardIfRefused()
    }

    /// 当自身处于 `.regular` 且未激活时，协作式激活会拒绝文件查看器自己的激活请求。
    @MainActor
    private static func bringFileViewerForwardIfRefused() {
        guard NSApp.activationPolicy() == .regular, !NSApp.isActive,
            let viewer = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: fileViewerBundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: viewer, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 全局 `NSFileViewer` 默认值就是替代性文件查看器接管「在访达中显示」的方式。
    private static var fileViewerBundleID: String {
        UserDefaults.standard.string(forKey: "NSFileViewer") ?? "com.apple.finder"
    }

    /// AppKit 没有「显示简介」的接口，因此通过 Apple 事件驱动 Finder——冷启动时需数秒。
    static func showInfoInFinder(_ url: URL) async -> Bool {
        let source = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(url.path)" as alias)
            end tell
            """
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return false }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            return errorInfo == nil
        }.value
    }

    /// 打开系统设置中由给定扩展 bundle ID 对应的面板。
    @MainActor
    static func openSettingsPane(bundleID: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + bundleID) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 应用未在最前时激活；已在前台时隐藏；未运行时启动。
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first
        if let running, running.isActive {
            running.hide()
            return
        }
        if let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            // 采用点击 Dock 图标的语义；单独调用 `activate()` 无法可靠实现这些行为。
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let running {
            // 已运行但无法解析其 bundle URL 的应用（启动后被移动或删除）。
            running.unhide()
            running.activate()
        }
    }

    /// 退出所有实例；只有非强制退出才允许未保存的工作弹出保存面板。
    @MainActor
    @discardableResult
    static func quit(bundleID: String, force: Bool = false) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        return !running.isEmpty
    }

    /// 长到足以让任何应用退出，短到不会在用户面前重新启动。
    private static let exitGrace = Duration.seconds(5)

    /// 退出被拒绝时（保存面板仍停留）不重新启动任何实例。
    @MainActor
    static func restart(bundleID: String, url: URL) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty, await quitAwaitingExit(running) else { return }
        launch(url)
    }

    /// 先注册观察再发起终止，使立即退出的实例也不会漏过等待。
    @MainActor
    private static func quitAwaitingExit(_ apps: [NSRunningApplication]) async -> Bool {
        let center = NSWorkspace.shared.notificationCenter
        let (exits, continuation) = AsyncStream.makeStream(of: pid_t.self)
        // 用 forName 老 API 而非 26 的 addObserver(of:for:)：应用退出通知在两个系统上语义一致；
        // queue: .main 保证回调在主线程。
        let observer = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            // Notification 的 userInfo 非 Sendable，先在非隔离层提取 pid（Sendable）
            // 再进入主隔离域，避免跨隔离边界捕获。
            let pid = (notification.userInfo?["NSWorkspaceApplicationPIDKey"] as? Int).map(pid_t.init)
            MainActor.assumeIsolated {
                guard let pid else { return }
                continuation.yield(pid)
            }
        }
        defer { center.removeObserver(observer) }

        var pending = Set(apps.map(\.processIdentifier))
        for app in apps { app.terminate() }

        let grace = Task {
            try? await Task.sleep(for: exitGrace); continuation.finish()
        }
        defer { grace.cancel() }
        for await pid in exits {
            pending.remove(pid)
            if pending.isEmpty { return true }
        }
        return false
    }

    /// Finder 永远不是「全部退出」的目标：对 `terminate()` 只会让它重新启动。
    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    /// 所有在 Dock 中有存在感的应用，除 Finder 与自身外；只解析一次，因此不会漂移。
    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        // 按 PID 而非激活策略判断：关于/设置窗口会临时把自身切换为 `.regular`。
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}
