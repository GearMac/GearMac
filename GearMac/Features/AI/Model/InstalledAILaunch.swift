// 文件职责：表示用户为某个已安装 CLI 配置的覆盖项（命令路径与环境变量名），并把覆盖解析为一次启动可用的命令与环境。
// 分层：Model；值类型与纯函数，环境变量取值通过闭包从 Keychain 侧注入。
import Foundation

/// 用户为某个已安装工具设置的覆盖：命令位置及启动时使用的环境变量。
struct InstalledAIOverride: Codable, Equatable, Sendable {
    /// 为空时由 `ExecutableLocator` 负责查找命令。
    var commandPath = ""
    /// 只保存名称，顺序由用户决定；值常为密钥，因此存放在 Keychain。
    var environmentNames: [String] = []

    /// 命令路径与环境变量名都为空时为真。
    var isEmpty: Bool { commandPath.isEmpty && environmentNames.isEmpty }
}

/// 用户编辑中的一个环境变量：名称来自设置，值来自 Keychain。
struct InstalledAIVariable: Equatable, Sendable {
    var name: String
    var value: String
}

/// 变量值的存取位置，以闭包封装，使 harness 无需接触 Keychain。
struct InstalledAIEnvironmentStore: Sendable {
    /// 读取失败时抛出，编辑器不会把读取失败误认为未设置任何值。
    var values: @Sendable (InstalledAIKind) throws -> [String: String]
    /// 保存某工具的全部变量值。
    var save: @Sendable ([String: String], InstalledAIKind) throws -> Void

    /// 不保存任何内容，用于没有真正存储的场景。
    static let none = InstalledAIEnvironmentStore(values: { _ in [:] }, save: { _, _ in })
}

/// 为一次启动解析后的覆盖：已校验路径、已读取变量值。
struct InstalledAILaunch: Equatable, Sendable {
    /// 一次启动使用的命令来源。
    enum Command: Equatable, Sendable {
        /// 未设置路径，按 Terminal 的查找方式定位命令。
        case automatic
        case executable(URL)
        /// 已设置路径但该处没有可执行文件；此时不会回退到自动查找。
        case missing(path: String)
    }

    var commandPath = ""
    var environment: [String: String] = [:]

    init(commandPath: String = "", environment: [String: String] = [:]) {
        self.commandPath = commandPath
        self.environment = environment
    }

    /// 设置的路径要么生效要么失败：回退会掩盖用户想用该路径纠正的错误。
    func command(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Command {
        let trimmed = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .automatic }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), isExecutable(expanded) else {
            return .missing(path: trimmed)
        }
        return .executable(URL(fileURLWithPath: expanded))
    }

    /// 一次启动继承的环境：用户变量覆盖应用自带变量，并剔除 GearMac 自己设置的变量。
    func inherited(
        for kind: InstalledAIKind,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let mine = environment.filter {
            Self.isVariableName($0.key) && !kind.isManagedVariable($0.key)
        }
        return base.merging(mine) { _, new in new }
    }

    /// 路径不可执行时展示的错误文案。
    static func missingCommandMessage(_ path: String) -> String {
        "Nothing can be run at \(path). Check the command path."
    }

    /// 判断是否是合法的环境变量名。
    nonisolated static func isVariableName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}

extension InstalledAIKind {
    /// 每次会话启动都设置，用于把工具约束在会话内；用户设置的值不会覆盖它。
    var managedEnvironment: [String: String] {
        switch self {
        case .claude:
            return ["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false"]
        case .openCode:
            return [
                "OPENCODE_CONFIG_CONTENT": Self.openCodeConfiguration,
                "OPENCODE_AUTO_SHARE": "false",
                "OPENCODE_DISABLE_AUTOUPDATE": "true"
            ]
        case .grok:
            return ["GROK_DISABLE_AUTOUPDATER": "1", "GROK_AGENT_DASHBOARD": "0"]
        case .cursor, .codex:
            return [:]
        }
    }

    /// `NO_COLOR` 保证输出可解析；`TC_MCP_` 前缀的变量把 GearMac 的 MCP 密钥传给 Codex。
    func isManagedVariable(_ name: String) -> Bool {
        name == "NO_COLOR" || name.hasPrefix("TC_MCP_") || managedEnvironment[name] != nil
    }

    /// 传给 OpenCode 的配置内容：拒绝权限与共享。
    private static let openCodeConfiguration = """
        {"permission":"deny","share":"disabled","agent":{"build":{"permission":"deny"},\
        "plan":{"permission":"deny"}}}
        """
}
