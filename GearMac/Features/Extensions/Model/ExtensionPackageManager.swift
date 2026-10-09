// 文件职责：枚举可用的包管理器并为扩展构建定位其可执行文件、安装/构建参数与搜索路径（含 Node）。
// 分层：Model；仅枚举与副作用的参数计算，不 import AppKit/SwiftUI。
import Foundation

/// 在构建前安装扩展的依赖。只有从 GitHub 安装的扩展才需要包管理器。
enum ExtensionPackageManager: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case pnpm
    case npm
    case yarn
    case bun

    var id: String { rawValue }

    /// 用于 UI 展示的名称。
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .pnpm: return "pnpm"
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .bun: return "Bun"
        }
    }

    /// `automatic` 的尝试顺序：最快、最省磁盘的在前，npm 作为最常存在的一个置于最后。
    static let preferenceOrder: [ExtensionPackageManager] = [.pnpm, .bun, .yarn, .npm]

    /// 该包管理器对应的可执行文件名；`automatic` 无对应可执行文件。
    var executableName: String {
        switch self {
        case .automatic: return ""
        case .pnpm: return "pnpm"
        case .npm: return "npm"
        case .yarn: return "yarn"
        case .bun: return "bun"
        }
    }

    /// 不用冻结 lockfile 的变体：已提交的 lockfile 往往已陈旧。
    var installArguments: [String] {
        switch self {
        case .automatic: return []
        case .pnpm: return ["install", "--ignore-scripts"]
        case .npm: return ["install", "--ignore-scripts", "--no-audit", "--no-fund"]
        case .yarn: return ["install", "--ignore-scripts"]
        case .bun: return ["install", "--ignore-scripts"]
        }
    }

    /// 运行 manifest 中的 `build` 脚本；对 Raycast 扩展而言即 `ray build`。
    var buildArguments: [String] {
        switch self {
        case .automatic: return []
        case .pnpm: return ["run", "build"]
        case .npm: return ["run", "build"]
        case .yarn: return ["run", "build"]
        case .bun: return ["run", "build"]
        }
    }

    /// GUI 应用不会继承 shell 的 PATH；更少见的位置则用 `extensionCustomSearchPaths`。
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        NSHomeDirectory() + "/.volta/bin",
        NSHomeDirectory() + "/.bun/bin",
        NSHomeDirectory() + "/.asdf/shims",
        NSHomeDirectory() + "/.local/share/mise/shims",
        NSHomeDirectory() + "/.local/share/fnm/aliases/default/bin",
        NSHomeDirectory() + "/.nvm/versions/node/current/bin",
        NSHomeDirectory() + "/.yarn/bin",
        NSHomeDirectory() + "/.npm-global/bin"
    ]

    /// `additionalSearchPaths` 会先于内置路径检查，因此用户目录可以覆盖内置结果。
    func resolve(
        in fileManager: FileManager = .default, additionalSearchPaths: [String] = []
    ) -> (manager: ExtensionPackageManager, url: URL)? {
        guard self != .automatic else {
            for candidate in Self.preferenceOrder {
                if let found = candidate.resolve(
                    in: fileManager, additionalSearchPaths: additionalSearchPaths)
                {
                    return found
                }
            }
            return nil
        }
        for directory in additionalSearchPaths + Self.searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: candidate.path) { return (self, candidate) }
        }
        return nil
    }

    /// `ray build` 依赖 Node，而 bun 是唯一不隐含 Node 的包管理器。
    static func nodeURL(
        in fileManager: FileManager = .default, additionalSearchPaths: [String] = []
    ) -> URL? {
        for directory in additionalSearchPaths + searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("node")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
