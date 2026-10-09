// 文件职责：打开已解析的 Quicklink 目标，集中所有平台副作用（文件检查、应用查找与 NSWorkspace 调用）。
// 分层：Service；@MainActor，依赖 AppKit，是 Quicklink 特性中唯一执行系统打开动作的位置。
import AppKit

/// 打开已解析的目标；本特性的所有平台副作用都集中于此。
@MainActor
enum QuicklinkLauncher {
    /// 打开 Quicklink 时可能出现的失败。
    enum Failure: LocalizedError, Equatable {
        case unresolvable(String)
        case missingFile(String)
        case missingApplication(String)
        case openFailed(target: String, detail: String)

        /// 面向用户的错误描述。
        var errorDescription: String? {
            switch self {
            case .unresolvable(let link):
                return "“\(link)” isn't a URL, file path, or deeplink."
            case .missingFile(let path):
                return "Nothing exists at \(path) any more."
            case .missingApplication:
                return "The app this quicklink opens with isn't installed any more."
            case .openFailed(let target, let detail):
                return "macOS could not open \(target).\n\n\(detail)"
            }
        }

        /// 按界面语言解析的面向用户错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .unresolvable(let link):
                return String(
                    format: L10n.string(QuicklinksKey.launcherUnresolvable, language: language), link)
            case .missingFile(let path):
                return String(
                    format: L10n.string(QuicklinksKey.launcherMissingFile, language: language), path)
            case .missingApplication:
                return L10n.string(QuicklinksKey.launcherMissingApp, language: language)
            case .openFailed(let target, let detail):
                return String(
                    format: L10n.string(QuicklinksKey.launcherOpenFailed, language: language), target,
                    detail)
            }
        }

        /// 应用缺失是唯一有可用备选方案的失败——即改用系统默认处理程序。
        var missingApplicationBundleID: String? {
            if case .missingApplication(let bundleID) = self { return bundleID }
            return nil
        }
    }

    /// Chromium 与 Firefox 接受该参数，Safari 会忽略它，因此始终传入是安全的。
    private static let newWindowArgument = "--new-window"

    /// `openWithBundleID` 为 nil 表示使用系统默认处理程序。
    static func open(
        _ link: String, openWithBundleID: String?, inNewWindow: Bool
    ) async throws(Failure) {
        guard let destination = QuicklinkDestination.detect(link) else {
            throw .unresolvable(link)
        }
        let url: URL
        switch destination {
        case .web(let value), .network(let value), .deeplink(let value):
            url = value
        case .path(let path):
            // 先做检查，使已删除的文件夹能被明确报出，而不是静默地无效。
            guard FileManager.default.fileExists(atPath: path) else { throw .missingFile(path) }
            url = URL(fileURLWithPath: path)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        if inNewWindow { configuration.arguments = [newWindowArgument] }

        var application: URL?
        if let openWithBundleID {
            application = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: openWithBundleID)
            guard application != nil else { throw .missingApplication(openWithBundleID) }
        }

        do {
            if let application {
                _ = try await NSWorkspace.shared.open(
                    [url], withApplicationAt: application, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            }
        } catch {
            throw .openFailed(
                target: destination.displayText, detail: error.localizedDescription)
        }
    }
}
