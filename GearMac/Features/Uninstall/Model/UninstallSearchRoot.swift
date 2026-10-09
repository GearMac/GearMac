// 文件职责：卸载扫描的搜索根表——去哪里查找、该处允许哪些匹配方式。
// 分层：Model（Uninstall）；纯数据表，不做文件系统访问。
import Foundation

/// 说明去哪里查找、该处允许哪些匹配方式；以数据表形式给出，而非为每个根写代码。
struct UninstallSearchRoot: Hashable, Sendable {
    /// 搜索根的基准目录：用户资源库或系统资源库。
    enum Base: Hashable, Sendable {
        case userLibrary
        case systemLibrary
    }

    /// 某个搜索根允许的匹配方式。
    enum MatchStyle: String, Hashable, Sendable, CaseIterable {
        case bundleID
        case groupContainer
        case displayName
    }

    let base: Base
    /// 相对于 `base` 的路径，非空。
    let relativePath: String
    let styles: Set<MatchStyle>

    /// 展开为实际绝对路径。
    func path(home: String) -> String {
        switch base {
        case .userLibrary: return home + "/Library/" + relativePath
        case .systemLibrary: return "/Library/" + relativePath
        }
    }

    /// 只扫描直接子项；家目录本身不在表中。详见 docs/features/uninstall.md。
    static let all: [UninstallSearchRoot] = [
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Caches", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Containers", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Group Containers", styles: [.groupContainer]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Scripts",
            styles: [.bundleID, .groupContainer]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Preferences/ByHost", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Saved Application State", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "HTTPStorages", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "WebKit", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Cookies", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Autosave Information", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        // 插件池：其子项是以产品名命名的包装类型，匹配时去掉后缀。
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Internet Plug-Ins", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Spotlight", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Automator", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Input Methods", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/HAL", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Caches", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Logs", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "LaunchDaemons", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PrivilegedHelperTools", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Internet Plug-Ins",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/HAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName])
    ]

    /// CLI 启动器的落点目录，按链接目标扫描，绝不按名称。
    static let binDirectories: [String] = [
        "/usr/local/bin", "/opt/homebrew/bin", "~/.local/bin", "~/bin"
    ]
}
