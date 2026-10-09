// 文件职责：按用户 Terminal 的方式定位 CLI 可执行文件（登录 shell 查询 + 常见安装路径），并为其构造可用的环境变量。
// 分层：Service；不依赖 AppKit/SwiftUI，所有方法都是 nonisolated。
import Foundation

/// 像用户自己的 Terminal 那样查找 CLI；应用自身继承的 PATH 只是 Finder 的那一套。
enum ExecutableLocator {
    /// `extraHomePaths` 是相对于 home 的可执行文件路径，用于那些不共用 `bin` 目录的安装方式。
    nonisolated static func locate(
        _ command: String,
        extraHomePaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        // shell 的答案优先：常见前缀里残留的旧安装可能会遮蔽真正可用的那个。
        if let path = await shellLookup(command, shell: loginShell()) {
            let url = URL(fileURLWithPath: path)
            if isExecutable(url) { return url }
        }
        return wellKnown(command, extraHomePaths: extraHomePaths, environment: environment)
            .first(where: isExecutable)
    }

    /// npm 或 Homebrew 的 CLI 实际是 `env node`，而 Finder 的 PATH 里没有可供它找到的 `node`。
    nonisolated static func environment(
        running executable: URL,
        adding extra: [String: String] = [:],
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let paths =
            [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + [inherited["PATH"] ?? "/usr/bin:/bin"]
        return
            inherited
            .merging(extra) { _, new in new }
            .merging(["NO_COLOR": "1", "PATH": paths.joined(separator: ":")]) { _, new in new }
    }

    /// 汇总 PATH、常见前缀与用户 home 下的常见安装位置，得到候选可执行文件列表。
    nonisolated private static func wellKnown(
        _ command: String, extraHomePaths: [String], environment: [String: String]
    ) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: command) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin"].map {
            URL(fileURLWithPath: $0).appending(path: command)
        }
        candidates += [
            ".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin", ".cargo/bin",
            ".local/share/mise/shims", ".asdf/shims"
        ].map { home.appending(path: $0).appending(path: command) }
        candidates += extraHomePaths.map { home.appending(path: $0) }
        candidates += nvmInstalls(command, in: home)
        return candidates
    }

    /// nvm 每个 Node 版本一个 `bin`；最新版本就是 `nvm use default` 会选中的那个。
    nonisolated private static func nvmInstalls(_ command: String, in home: URL) -> [URL] {
        let versions = home.appending(path: ".nvm/versions/node")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return
            names
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: $0).appending(path: "bin/\(command)") }
    }

    /// 判断路径是否为可执行文件。
    nonisolated private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// `-i` 会读取把版本管理器放进 PATH 的 rc 文件；看门狗用于限制挂起时间。
    nonisolated static func shellLookup(_ command: String, shell: URL) async -> String? {
        await Task.detached {
            let process = Process()
            let (executable, arguments) = lookup(command, in: shell)
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.environment = ProcessInfo.processInfo.environment.merging(["GEARMAC": "1"]) {
                _, new in new
            }
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let stdout = Pipe()
            process.standardOutput = stdout
            guard let exit = try? process.runObservingExit() else { return nil }
            let watchdog = Task {
                try await Task.sleep(for: .seconds(5))
                if process.isRunning { process.terminate() }
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            exit.wait()
            watchdog.cancel()
            guard process.terminationStatus == 0 else { return nil }
            // 启动与登出脚本可能在查询结果的前后任一侧打印内容。
            let path =
                String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .last { $0.hasPrefix(answerMarker) }?
                .dropFirst(answerMarker.count)
                .trimmingCharacters(in: .whitespaces) ?? ""
            return path.hasPrefix("/") ? path : nil
        }.value
    }

    nonisolated private static let answerMarker = "gearmac-locator:"

    /// fish 把 `-c` 参数绑定到 `$argv` 而非 `$1`；其他 shell 均回退到 zsh。
    nonisolated private static func lookup(_ command: String, in shell: URL) -> (URL, [String]) {
        switch shell.lastPathComponent {
        case "fish":
            let script = #"printf '\#(answerMarker)%s\n' (command -v -- $argv[1])"#
            return (shell, ["-ilc", script, command])
        case "zsh", "bash", "sh", "ksh", "dash":
            let script = #"printf '\#(answerMarker)%s\n' "$(command -v -- "$1")""#
            return (shell, ["-ilc", script, "gearmac-locator", command])
        default:
            return lookup(command, in: URL(fileURLWithPath: "/bin/zsh"))
        }
    }

    /// 返回当前用户的登录 shell，取不到时回退到 `/bin/zsh`。
    nonisolated private static func loginShell() -> URL {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return URL(fileURLWithPath: "/bin/zsh")
        }
        return URL(fileURLWithPath: String(cString: shell))
    }
}
