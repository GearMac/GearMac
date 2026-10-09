// 文件职责：监听系统“图标与小组件样式”变化，在图标真实重绘后使样式化图标缓存失效。
// 分层：Service；@MainActor，订阅 NSWorkspace 通知并在后台轮询指纹。
import AppKit

/// 监听系统设置 → 外观 → **图标与小组件样式**的变化；一旦变化，所有图标都会失效。
@MainActor
final class IconStyleMonitor {
    /// 实测：切换在通知后约 25–120ms 落地，每次运行都有抖动。
    private static let pollInterval = Duration.milliseconds(40)
    private static let settleLimit = Duration.milliseconds(600)

    private var token: NotificationToken?
    private var settling: Task<Void, Never>?
    private var rendered: Data?

    /// 订阅系统图标外观变化通知，并记录初始样式指纹。
    init() {
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(
            forName: .iconAppearanceConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateOnceIconsSwap() }
        }
        token = NotificationToken(observer, center: center)
        settling = Task { [weak self] in
            let fingerprint = await Self.fingerprint()
            self?.rendered = fingerprint
        }
    }

    /// AppKit 会在 `NSWorkspace` 提供新样式之前就发出通知，因此要等像素变化而非等待信号。
    private func invalidateOnceIconsSwap() {
        settling?.cancel()
        settling = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.settleLimit
            while !Task.isCancelled {
                let current = await Self.fingerprint()
                guard let self, !Task.isCancelled else { return }
                if current != rendered {
                    rendered = current
                    break
                }
                if ContinuousClock.now >= deadline { break }
                try? await Task.sleep(for: Self.pollInterval)
            }
            guard !Task.isCancelled else { return }
            IconCache.invalidateStyled()
        }
    }

    /// 在后台线程获取当前样式指纹。
    private static func fingerprint() async -> Data? {
        await Task.detached(priority: .userInitiated) { IconCache.styleFingerprint() }.value
    }
}

extension Notification.Name {
    /// 由 AppKit 导出但未公开声明；它是覆盖所有重绘场景的唯一信号。
    static let iconAppearanceConfigurationDidChange = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification")
}
