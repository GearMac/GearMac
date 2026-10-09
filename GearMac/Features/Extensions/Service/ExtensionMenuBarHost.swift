// 文件职责：菜单栏命令的宿主上下文实现，为某个菜单栏命令提供 ExtensionHostContext 能力（HUD、提醒对话框、启动其他命令、OAuth 等），并把交互能力限定在交互式启动时。
// 分层：Service（@MainActor）；作为 ExtensionHostContext 的实现方，自身不驱动 UI，仅将请求转发给 coordinator 与 manager。
import AppKit

/// 单个菜单栏命令的宿主：持有该命令所属扩展、存储与命令引用，并代为响应运行时请求。
@MainActor
final class ExtensionMenuBarHost: ExtensionHostContext {
    let owner: InstalledExtension
    let storage: ExtensionStorage
    private let reference: ExtensionCommandRef
    private var isInteractive: Bool
    private weak var manager: ExtensionManager?
    private weak var coordinator: ExtensionCoordinator?
    private let oauth = ExtensionOAuthSession()

    /// 创建宿主；由 launchType 决定初始是否为交互模式（userInitiated 才可交互）。
    init(
        owner: InstalledExtension, command: ExtensionCommand, launchType: ExtensionLaunchType,
        storage: ExtensionStorage,
        manager: ExtensionManager, coordinator: ExtensionCoordinator
    ) {
        self.owner = owner
        reference = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        isInteractive = launchType == .userInitiated
        self.storage = storage
        self.manager = manager
        self.coordinator = coordinator
    }

    var activeExtensionName: String? { owner.manifest.name }
    var activeLaunchType: ExtensionLaunchType { isInteractive ? .userInitiated : .background }
    var pasteTarget: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }
    var applicationURLs: [URL] { coordinator?.applicationURLs ?? [] }

    /// 停止宿主，取消可能正在进行的 OAuth 流程。
    func stop() { oauth.cancel() }
    func enableInteraction() { isInteractive = true }
    func closeMainWindow(clearRootSearch: Bool) {}
    func reopenPalette() { coordinator?.reopenPalette(hasRunningCommand: false) }
    func popToRoot() {}
    func clearSearchBar() {}
    func openPreferences(scope: String) { coordinator?.showExtensionSettings(for: owner) }
    func updateCommandMetadata(subtitle: String?) {
        manager?.updateCommandMetadata(subtitle: subtitle, for: reference)
    }
    func present(toast: ExtensionToast) -> Int { 0 }
    func update(toast id: Int, with toast: ExtensionToast) {}
    func hide(toast id: Int) {}

    /// 展示 HUD；仅交互模式下的命令才可见。
    func showHUD(_ text: String) {
        if isInteractive { coordinator?.showHUD(text) }
    }

    /// 弹出确认对话框；非交互模式直接返回 false。
    func confirmAlert(_ alert: ExtensionAlert) async -> Bool {
        guard isInteractive else { return false }
        return await coordinator?.confirmExtensionAlert(alert) ?? false
    }

    func openWithPicker(path: String) async { await manager?.openWithPicker(path: path) }

    /// 从菜单栏命令启动另一个命令；未指定扩展时默认沿用当前扩展。
    func launch(
        command: String, extensionName: String?, arguments: [String: String],
        fallbackText: String?, launchType: ExtensionLaunchType, launchContext: [String: RenderValue]
    ) throws {
        try manager?.launch(
            command: command, extensionName: extensionName ?? owner.manifest.name,
            arguments: arguments, fallbackText: fallbackText, launchType: launchType,
            launchContext: launchContext)
    }

    func launch(_ link: ExtensionDeepLink) throws { try manager?.launch(link) }

    /// 发起 OAuth 授权；后台（非交互）运行不允许弹出授权流程。
    func authorizeOAuth(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult
    {
        guard isInteractive else { throw ExtensionHostError.unsupported("Background authorization") }
        return try await oauth.authorize(options: options)
    }

    func getOAuthTokens(providerId: String) -> String? {
        ExtensionOAuthKeychain.getTokens(extensionName: owner.manifest.name, providerId: providerId)
    }

    func setOAuthTokens(providerId: String, tokens: String) {
        ExtensionOAuthKeychain.setTokens(tokens, extensionName: owner.manifest.name, providerId: providerId)
    }

    func removeOAuthTokens(providerId: String) {
        ExtensionOAuthKeychain.removeTokens(extensionName: owner.manifest.name, providerId: providerId)
    }
}
