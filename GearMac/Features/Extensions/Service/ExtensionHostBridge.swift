// 文件职责：实现 JS 扩展调用的 host API 桥接，把 clipboard/storage/cache/window/feedback/system/oauth 等请求分发到对应的 macOS 能力。
// 分层：Service；UI 仅在非后台 launch type 下才允许弹出（toast/HUD/对话框）。
import AppKit
import Foundation

/// 定义为协议，使桥接层不硬依赖持有它的 `ExtensionManager`。
@MainActor
protocol ExtensionHostContext: AnyObject {
    /// 当前正在运行命令的扩展 —— storage、cache 与 preferences 的命名空间。
    var activeExtensionName: String? { get }
    /// 后台运行不产生任何 UI：否则 toast、HUD 与对话框会按定时器不断弹出。
    var activeLaunchType: ExtensionLaunchType { get }
    var storage: ExtensionStorage { get }
    /// 粘贴将要落入的应用 —— 启动器记录的 `previousApp`。
    var pasteTarget: NSRunningApplication? { get }
    /// `getApplications()` 会返回的所有 app bundle，来自用户自己的搜索范围。
    var applicationURLs: [URL] { get }

    func closeMainWindow(clearRootSearch: Bool)
    /// 在命令隐藏启动器后将其重新唤回 —— 对扩展而言这就是 `raycast://` 的含义。
    func reopenPalette()
    func popToRoot()
    func clearSearchBar()
    func openPreferences(scope: String)
    /// 持久化 `subtitle`（传入 `null` 则清除）；缺少该键时保持不变。
    func updateCommandMetadata(subtitle: String?)
    func present(toast: ExtensionToast) -> Int
    func update(toast id: Int, with toast: ExtensionToast)
    func hide(toast id: Int)
    func showHUD(_ text: String)
    func confirmAlert(_ alert: ExtensionAlert) async -> Bool
    func openWithPicker(path: String) async
    func launch(
        command: String, extensionName: String?, arguments: [String: String],
        fallbackText: String?, launchType: ExtensionLaunchType, launchContext: [String: RenderValue]
    ) throws
    func launch(_ link: ExtensionDeepLink) throws
    func authorizeOAuth(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult
    func getOAuthTokens(providerId: String) -> String?
    func setOAuthTokens(providerId: String, tokens: String)
    func removeOAuthTokens(providerId: String)
}

/// 启动器展示所用的 toast 数据模型。
struct ExtensionToast: Sendable, Equatable, Identifiable {
    /// toast 的视觉样式，字符串值与 JS 侧约定一致。
    enum Style: String, Sendable {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case animated = "ANIMATED"

        init(raw: String?) {
            self = Style(rawValue: raw ?? "SUCCESS") ?? .success
        }
    }

    /// toast 上的可点击按钮。
    struct Action: Sendable, Equatable {
        let title: String
        /// 回传给 `runToastAction`，以便 JS 找到对应回调。
        let token: String
    }

    var id: Int = 0
    var style: Style = .success
    var title: String = ""
    var message: String?
    var primaryAction: Action?
    var secondaryAction: Action?

    init(
        id: Int = 0, style: Style = .success, title: String = "", message: String? = nil,
        primaryAction: Action? = nil, secondaryAction: Action? = nil
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    init(payload: [String: RenderValue]) {
        style = Style(raw: payload["style"]?.stringValue)
        title = payload["title"]?.stringValue ?? ""
        message = payload["message"]?.stringValue
        primaryAction = ExtensionToast.action(from: payload["primaryAction"])
        secondaryAction = ExtensionToast.action(from: payload["secondaryAction"])
    }

    private static func action(from value: RenderValue?) -> Action? {
        guard let fields = value?.objectValue, let token = fields["token"]?.stringValue else {
            return nil
        }
        return Action(title: fields["title"]?.stringValue ?? "", token: token)
    }
}

/// 确认弹窗的数据模型。
struct ExtensionAlert: Sendable {
    var title: String
    var message: String?
    var primaryTitle: String
    var dismissTitle: String
    var isDestructive: Bool

    init(payload: [String: RenderValue]) {
        title = payload["title"]?.stringValue ?? "Are you sure?"
        message = payload["message"]?.stringValue
        let primary = payload["primaryAction"]?.objectValue
        primaryTitle = primary?["title"]?.stringValue ?? "Confirm"
        dismissTitle = payload["dismissAction"]?.objectValue?["title"]?.stringValue ?? "Cancel"
        isDestructive = primary?["style"]?.stringValue == "destructive"
    }
}

/// host 调用失败的分类与用户可读的错误描述。
enum ExtensionHostError: LocalizedError {
    case noActiveExtension
    case unknown(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .noActiveExtension: return "No extension command is running."
        case .unknown(let what): return "Unknown host call '\(what)'."
        case .unsupported(let what): return "\(what) is not supported in GearMac extensions."
        }
    }
}

/// host API 桥接层：接收 JS 扩展的调用，按 api/method 分发到相应的 macOS 能力实现。
@MainActor
final class ExtensionHostBridge: ExtensionHostAPI {
    weak var context: ExtensionHostContext?
    private let clipboardStore: ClipboardStore
    private let fetcher: ExtensionFetcher
    private let sockets = ExtensionWebSocketBridge()

    init(clipboardStore: ClipboardStore, fetcher: ExtensionFetcher = ExtensionFetcher()) {
        self.clipboardStore = clipboardStore
        self.fetcher = fetcher
    }

    /// 返回一个绑定到指定上下文的桥接副本，共享同一个 clipboardStore 与 fetcher。
    func scoped(to context: ExtensionHostContext) -> ExtensionHostBridge {
        let bridge = ExtensionHostBridge(clipboardStore: clipboardStore, fetcher: fetcher)
        bridge.context = context
        return bridge
    }

    /// 执行一次 host 调用，并把结果序列化为 JSON 字符串返回给 JS。
    func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
        guard context != nil else { throw ExtensionHostError.noActiveExtension }
        let value = try await dispatch(api: api, method: method, arguments: arguments)
        return ExtensionRuntime.jsonString(from: value)
    }

    private func dispatch(api: String, method: String, arguments: [RenderValue]) async throws -> Any? {
        switch api {
        case "clipboard": return try clipboard(method: method, arguments: arguments)
        case "storage": return try storage(method: method, arguments: arguments)
        case "cache": return try cache(method: method, arguments: arguments)
        case "window": return window(method: method, arguments: arguments)
        case "feedback": return try await feedback(method: method, arguments: arguments)
        case "system": return try await system(method: method, arguments: arguments)
        case "fetch": return try await fetcher.request(arguments.first)
        case "websocket": return try await sockets.perform(method: method, arguments: arguments)
        case "dns": return await ExtensionNameResolver.resolve(arguments.first)
        case "proc" where method == "read": return try await ExtensionAsyncProcess.read(arguments)
        case "proc": return try await ExtensionAsyncProcess.wait(arguments.first)
        case "oauth": return try await oauth(method: method, arguments: arguments)
        default: throw ExtensionHostError.unknown("\(api).\(method)")
        }
    }

    private func requireContext() throws -> (ExtensionHostContext, String) {
        guard let context, let name = context.activeExtensionName else {
            throw ExtensionHostError.noActiveExtension
        }
        return (context, name)
    }

    /// 在每个丢弃命令上下文的出口调用：任何未关闭的资源都不应比其会话存活更久。
    func sessionEnded() {
        sockets.closeAll()
    }

    // MARK: - Clipboard

    private func clipboard(method: String, arguments: [RenderValue]) throws -> Any? {
        switch method {
        case "copy", "paste":
            let content = arguments.first?.objectValue ?? [:]
            let options = arguments[safe: 1]?.objectValue ?? [:]
            let concealed =
                options["concealed"]?.boolValue == true
                || options["transient"]?.boolValue == true
            // 文件以文件形式写入剪贴板，粘贴时才会呈现为其本身的图像。
            if let path = content["file"]?.stringValue, !path.isEmpty {
                let target = context?.pasteTarget
                if method == "paste" { context?.closeMainWindow(clearRootSearch: false) }
                writeFileToPasteboard(path, concealed: method == "copy" && concealed)
                guard method == "paste" else { return nil }
                target?.activate()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    Paster.postCommandV()
                }
                return nil
            }
            guard let text = clipboardText(from: content) else { return nil }
            if method == "copy" {
                // 历史记录只会记录未标记的复制；ConcealedType 是让敏感内容不被记录的方式。
                if concealed {
                    writeConcealedString(text)
                } else {
                    Paster.copyPlainText(text)
                }
            } else {
                Paster.pasteString(text, previousApp: context?.pasteTarget)
            }
            return nil

        case "clear":
            NSPasteboard.general.clearContents()
            return nil

        case "readText":
            return NSPasteboard.general.string(forType: .string) ?? ""

        case "read":
            var payload: [String: Any] = [:]
            if let text = NSPasteboard.general.string(forType: .string) { payload["text"] = text }
            if let url = NSPasteboard.general.string(forType: .URL) { payload["file"] = url }
            return payload

        default:
            throw ExtensionHostError.unknown("clipboard.\(method)")
        }
    }

    /// 同时写入文件、其图像与路径：接收方自行选择它支持的表示形式。
    private func writeFileToPasteboard(_ path: String, concealed: Bool) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var items: [NSPasteboardWriting] = [url as NSURL]
        if let image = NSImage(contentsOf: url) { items.append(image) }
        pasteboard.writeObjects(items)
        pasteboard.setString(url.path, forType: .string)
        if concealed {
            pasteboard.setData(Data(), forType: Self.concealedPasteboardType)
        }
    }

    private func writeConcealedString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: Self.concealedPasteboardType)
    }

    private static let concealedPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType")

    private func clipboardText(from content: [String: RenderValue]) -> String? {
        if let text = content["text"]?.stringValue { return text }
        if let html = content["html"]?.stringValue { return html }
        return nil
    }

    // MARK: - LocalStorage

    private func storage(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        switch method {
        case "get":
            guard let key = arguments.first?.stringValue else { return nil }
            return context.storage.localStorageValue(extension: name, key: key)?.jsonValue

        case "set":
            guard let key = arguments.first?.stringValue,
                let value = arguments[safe: 1].flatMap(ExtensionStorage.StoredValue.init(renderValue:))
            else { return nil }
            context.storage.setLocalStorage(extension: name, key: key, value: value)
            return nil

        case "remove":
            guard let key = arguments.first?.stringValue else { return nil }
            context.storage.removeLocalStorage(extension: name, key: key)
            return nil

        case "clear":
            context.storage.clearLocalStorage(extension: name)
            return nil

        case "all":
            return context.storage.allLocalStorage(extension: name).mapValues(\.jsonValue)

        default:
            throw ExtensionHostError.unknown("storage.\(method)")
        }
    }

    // MARK: - Cache

    private func cache(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        let namespace = arguments.first?.stringValue ?? "default"
        switch method {
        case "set":
            // key 为 nil 时清空整个命名空间；value 为 nil 时删除单个条目。
            let key = arguments[safe: 1]?.stringValue
            let value = arguments[safe: 2]?.stringValue
            context.storage.setCache(extension: name, namespace: namespace, key: key, value: value)
            return nil
        case "clear":
            context.storage.clearCache(extension: name, namespace: namespace)
            return nil
        default:
            throw ExtensionHostError.unknown("cache.\(method)")
        }
    }

    // MARK: - Window

    private func window(method: String, arguments: [RenderValue]) -> Any? {
        guard context?.activeLaunchType != .background else { return nil }
        switch method {
        case "close":
            let options = arguments.first?.objectValue ?? [:]
            context?.closeMainWindow(clearRootSearch: options["clearRootSearch"]?.boolValue ?? false)
        case "popToRoot":
            context?.popToRoot()
        case "clearSearchBar":
            context?.clearSearchBar()
        case "openPreferences":
            context?.openPreferences(scope: arguments.first?.stringValue ?? "extension")
        default:
            break
        }
        return nil
    }

    // MARK: - Feedback

    private func feedback(method: String, arguments: [RenderValue]) async throws -> Any? {
        guard let context else { throw ExtensionHostError.noActiveExtension }
        guard context.activeLaunchType != .background else { return nil }
        switch method {
        case "showToast":
            guard let payload = arguments.first?.objectValue else { return nil }
            return context.present(toast: ExtensionToast(payload: payload))

        case "updateToast":
            guard let id = arguments.first?.doubleValue.map(Int.init),
                let payload = arguments[safe: 1]?.objectValue
            else { return nil }
            context.update(toast: id, with: ExtensionToast(payload: payload))
            return nil

        case "hideToast":
            if let id = arguments.first?.doubleValue.map(Int.init) { context.hide(toast: id) }
            return nil

        case "showHUD":
            context.showHUD(arguments.first?.stringValue ?? "")
            return nil

        case "confirmAlert":
            guard let payload = arguments.first?.objectValue else { return false }
            return await context.confirmAlert(ExtensionAlert(payload: payload))

        default:
            throw ExtensionHostError.unknown("feedback.\(method)")
        }
    }

    // MARK: - System

    private func system(method: String, arguments: [RenderValue]) async throws -> Any? {
        switch method {
        case "open":
            guard let target = arguments.first?.stringValue else { return nil }
            open(target: target, application: arguments[safe: 1]?.stringValue)
            return nil

        case "openWith":
            await context?.openWithPicker(path: arguments.first?.stringValue ?? "")
            return nil

        case "showInFinder":
            guard let path = arguments.first?.stringValue else { return nil }
            AppLauncher.showInFinder(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return nil

        case "trash":
            let paths = (arguments.first?.arrayValue ?? []).compactMap(\.stringValue)
            for path in paths {
                try? FileManager.default.trashItem(
                    at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                    resultingItemURL: nil)
            }
            return nil

        case "applications":
            return applications(forPath: arguments.first?.stringValue)

        case "defaultApplication":
            guard let target = arguments.first?.stringValue,
                let url = NSWorkspace.shared.urlForApplication(toOpen: targetURL(for: target))
            else { throw ExtensionHostError.unsupported("getDefaultApplication") }
            return describe(application: url)

        case "frontmostApplication":
            guard let app = context?.pasteTarget ?? NSWorkspace.shared.frontmostApplication,
                let url = app.bundleURL
            else { throw ExtensionHostError.unsupported("getFrontmostApplication") }
            return describe(application: url)

        case "selectedText":
            return try selectedText()

        case "selectedFinderItems":
            return try finderSelection()

        case "launchCommand":
            let options = arguments.first?.objectValue ?? [:]
            guard let name = options["name"]?.stringValue else {
                throw ExtensionHostError.unsupported("launchCommand without a name")
            }
            var launchArguments: [String: String] = [:]
            for (key, value) in options["arguments"]?.objectValue ?? [:] {
                launchArguments[key] = value.stringValue
            }
            let launchType: ExtensionLaunchType =
                options["type"]?.stringValue == ExtensionLaunchType.background.rawValue
                ? .background : .userInitiated
            try context?.launch(
                command: name, extensionName: options["extensionName"]?.stringValue,
                arguments: launchArguments, fallbackText: options["fallbackText"]?.stringValue,
                launchType: launchType, launchContext: options["context"]?.objectValue ?? [:])
            return nil

        case "updateCommandMetadata":
            let fields = arguments.first?.objectValue ?? [:]
            guard fields.keys.contains("subtitle") else { return nil }
            context?.updateCommandMetadata(subtitle: fields["subtitle"]?.stringValue)
            return nil

        default:
            throw ExtensionHostError.unknown("system.\(method)")
        }
    }

    /// `https:` 目标指向的是 scheme 处理器而非文件：用 `fileURLWithPath:` 会破坏它。
    private func targetURL(for target: String) -> URL {
        URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
    }

    private func open(target: String, application: String?) {
        let url = targetURL(for: target)
        // 扩展通过 scheme 寻址 Raycast；直接交给 workspace 会真正启动 Raycast。
        if ExtensionDeepLink.claims(url) {
            openRaycastURL(url)
            return
        }
        guard let appIdentifier = application else {
            NSWorkspace.shared.open(url)
            return
        }
        let appURL =
            appIdentifier.hasPrefix("/")
            ? URL(fileURLWithPath: appIdentifier)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: appIdentifier)
        guard let appURL else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil)
    }

    /// 命令 URL 在已安装时直接执行该命令；其余 Raycast URL 只是把启动器唤回。
    private func openRaycastURL(_ url: URL) {
        if let link = ExtensionDeepLink.parse(url: url), (try? context?.launch(link)) != nil {
            return
        }
        context?.reopenPalette()
    }

    private func applications(forPath path: String?) -> [[String: Any]] {
        let urls: [URL]
        if let path, !path.isEmpty {
            let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            urls = NSWorkspace.shared.urlsForApplications(toOpen: target)
        } else {
            urls = context?.applicationURLs ?? []
        }
        return urls.map(describe(application:))
    }

    private func describe(application url: URL) -> [String: Any] {
        let bundle = Bundle(url: url)
        let name = bundle?.installedAppName ?? url.deletingPathExtension().lastPathComponent
        return [
            "name": name, "path": url.path, "bundleId": bundle?.bundleIdentifier ?? NSNull(),
            "localizedName": name
        ]
    }

    /// 读取被启动器让出焦点的应用，而非系统范围内的当前焦点应用。
    private func selectedText() throws -> String {
        guard Permissions.ensureAccessibility() else {
            throw ExtensionHostError.unsupported("getSelectedText without the Accessibility permission")
        }
        guard let target = context?.pasteTarget,
            target.processIdentifier != NSRunningApplication.current.processIdentifier
        else { throw ExtensionHostError.unsupported("getSelectedText (no target application)") }

        guard let text = AccessibilityText.selection(in: target), !text.isEmpty else {
            throw ExtensionHostError.unsupported("getSelectedText (no selection)")
        }
        return text
    }

    /// 以换行符连接，Finder 不允许文件名含换行；用逗号则会把路径切断。
    private func finderSelection() throws -> [[String: String]] {
        let script = """
            set AppleScript's text item delimiters to linefeed
            tell application "Finder" to set chosen to (get selection as alias list)
            set paths to {}
            repeat with one in chosen
                set end of paths to POSIX path of one
            end repeat
            return paths as text
            """
        guard let apple = NSAppleScript(source: script) else { return [] }
        var error: NSDictionary?
        let result = apple.executeAndReturnError(&error)
        guard error == nil else { return [] }
        return result.stringValue?
            .split(separator: "\n")
            .map { ["path": String($0)] } ?? []
    }

    // MARK: - OAuth

    private func oauth(method: String, arguments: [RenderValue]) async throws -> Any? {
        guard let context else { throw ExtensionHostError.noActiveExtension }
        switch method {
        case "authorize":
            guard let urlString = arguments.first?.stringValue, let url = URL(string: urlString) else {
                throw ExtensionHostError.unsupported("authorize requires url")
            }
            let options = ExtensionOAuthAuthorizeOptions(
                url: url, state: arguments[safe: 1]?.stringValue)
            let result = try await context.authorizeOAuth(options: options)
            var dict: [String: Any] = ["authorizationCode": result.authorizationCode]
            if let token = result.accessToken { dict["accessToken"] = token }
            if let state = result.state { dict["state"] = state }
            return dict

        case "getTokens":
            let providerId = arguments.first?.stringValue ?? ""
            guard let tokens = context.getOAuthTokens(providerId: providerId) else { return nil }
            return tokens

        case "setTokens":
            let providerId = arguments.first?.stringValue ?? ""
            let tokens = arguments[safe: 1]?.stringValue ?? ""
            context.setOAuthTokens(providerId: providerId, tokens: tokens)
            return nil

        case "removeTokens":
            let providerId = arguments.first?.stringValue ?? ""
            context.removeOAuthTokens(providerId: providerId)
            return nil

        default:
            throw ExtensionHostError.unknown("oauth.\(method)")
        }
    }
}
