// 文件职责：承载扩展引擎启动时一次性下发的主机环境信息，以及单个命令启动所需的上下文（环境、偏好、缓存、参数）。
// 分层：Model；保持纯净，仅做数据建模与 JSON 序列化，不 import AppKit/SwiftUI。
import Foundation

/// Node 垫片（shim）无需回调宿主即可答复的机器信息。引擎启动时发送一次。
struct ExtensionBootConfig: Sendable {
    var arch: String
    var release: String
    var hostname: String
    var username: String
    var shell: String
    var homeDirectory: String
    var temporaryDirectory: String
    var workingDirectory: String
    var totalMemory: Double
    var environmentVariables: [String: String]

    /// 从当前进程与文件系统采集一份启动配置；`supportDirectory` 作为扩展的工作目录。
    static func current(supportDirectory: URL) -> ExtensionBootConfig {
        let info = ProcessInfo.processInfo
        var arch = "arm64"
        #if arch(x86_64)
            arch = "x64"
        #endif
        // GUI 应用继承的环境很精简；而扩展调用 shell 时往往期望接近登录态的 PATH。
        var variables = info.environment
        variables["PATH"] =
            (variables["PATH"].map { $0 + ":" } ?? "")
            + "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        variables["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path

        return ExtensionBootConfig(
            arch: arch,
            release: info.operatingSystemVersionString,
            hostname: info.hostName,
            username: NSUserName(),
            shell: info.environment["SHELL"] ?? "/bin/zsh",
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            temporaryDirectory: FileManager.default.temporaryDirectory.path,
            workingDirectory: supportDirectory.path,
            totalMemory: Double(info.physicalMemory),
            environmentVariables: variables)
    }

    /// 序列化为给 Node 垫片使用的 JSON 字符串（键名对应 Node 的 `os` 等模块字段）。
    func jsonString() -> String {
        ExtensionRuntime.jsonString(
            from: [
                "node": [
                    "arch": arch,
                    "release": release,
                    "hostname": hostname,
                    "username": username,
                    "shell": shell,
                    "homedir": homeDirectory,
                    "tmpdir": temporaryDirectory,
                    "cwd": workingDirectory,
                    "totalmem": totalMemory,
                    "env": environmentVariables,
                    "execPath": ""
                ]
            ])
    }
}

/// 单个命令挂载（mount）时所需的全部信息：环境、偏好、缓存与参数。
struct ExtensionLaunchContext: Sendable {
    var extensionName: String
    var extensionTitle: String
    var commandName: String
    var commandMode: ExtensionCommandMode
    var assetsPath: String
    var supportPath: String
    var preferences: [String: ExtensionPreferenceValue]
    var caches: [String: [String: String]]
    var arguments: [String: String]
    var fallbackText: String?
    var launchType: ExtensionLaunchType = .userInitiated
    /// 由外部注入、自身从不读取：运行中的命令保持启动时拿到的值。
    var isDarkAppearance: Bool
    var launchContext: [String: RenderValue] = [:]

    /// 序列化为命令启动时传给垫片的 JSON 字符串（包含 environment、preferences、caches 与 launchProps）。
    func jsonString() -> String {
        var environment: [String: Any] = [
            "extensionName": extensionName,
            "commandName": commandName,
            "commandMode": commandMode.rawValue,
            "assetsPath": assetsPath,
            "supportPath": supportPath,
            "isDevelopment": false,
            // 扩展会依据此值开关功能；上报垫片所实现的 API 版本级别。
            "raycastVersion": ExtensionRuntimeVersion.raycastAPI,
            "textSize": "medium",
            "appearance": isDarkAppearance ? "dark" : "light",
            "launchType": launchType.rawValue,
            "canAccess": false
        ]
        environment["ownerOrAuthorName"] = extensionTitle

        var launchProps: [String: Any] = ["launchType": launchType.rawValue, "arguments": arguments]
        if let fallbackText { launchProps["fallbackText"] = fallbackText }
        if !launchContext.isEmpty { launchProps["launchContext"] = launchContext.mapValues(\.jsonValue) }

        return ExtensionRuntime.jsonString(
            from: [
                "environment": environment,
                "preferences": preferences.mapValues(\.jsonValue),
                "caches": caches,
                "launchProps": launchProps
            ])
    }
}

/// 内置垫片所对标的上游 API 版本号。
enum ExtensionRuntimeVersion {
    /// 内置垫片跟踪的 @raycast/api 版本，通过 `environment.raycastVersion` 暴露给扩展。
    static let raycastAPI = "2.0.3"
}
