// 文件职责：在 /bin/zsh 下执行自定义命令：既提供等待结果的批式运行，也提供基于伪终端的流式运行，并负责输出解码与停止控制。
// 分层：Service；不经主 actor，阻塞的等待放在自有的并发 DispatchQueue 上，输出经过 ANSI/UTF-8 解码后再向上层提交。
import Darwin
import Foundation

/// 一次运行的结束方式。`launchFailed` 表示 shell 根本没启动，因此没有捕获到任何内容。
enum ShellCommandTermination: Sendable, Equatable {
    case exited(status: Int32)
    case launchFailed(String)
    /// 除退出状态外无其他信息；被信号终止的 shell 会报告为 143 或 15。
    case stopped

    /// 因信号死亡时状态码即信号编号，因此这里与非零退出一样判定为失败。
    var succeeded: Bool { self == .exited(status: 0) }
}

/// 流式运行期间推送的事件：输出片段或最终结果。
enum ShellCommandEvent: Sendable {
    case output(String)
    case finished(ShellCommandResult)
}

/// `stop` 不是流本身的取消：放弃消费事件不应杀死命令。
struct ShellCommandSession: Sendable {
    let events: AsyncStream<ShellCommandEvent>
    let stop: @Sendable () -> Void
}

/// 仅非流式运行会填充两个输出尾部；流式运行通过事件上报。
struct ShellCommandResult: Sendable, Equatable {
    let termination: ShellCommandTermination
    /// 保持精简：它只用于命令结束后展示的一行报告。
    let standardOutput: String?
    let standardError: String?

    var succeeded: Bool { termination.succeeded }

    /// 命令输出的最后一行，用于只有一行空间的报告。
    var lastOutputLine: String? {
        standardOutput?
            .split(whereSeparator: \.isNewline).last
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    init(
        termination: ShellCommandTermination, standardOutput: String? = nil,
        standardError: String? = nil
    ) {
        self.termination = termination
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// 自定义命令的 shell 执行器：既提供等待结果的批式运行，也提供基于伪终端的流式运行。
enum ShellCommandRunner {
    /// 仅在失败时对外呈现，此时最后几行就已说明全部问题。
    private static let standardErrorLimit = 8 * 1024
    /// 只会展示最后一行，因此这是对它相当宽松的上限。
    private static let standardOutputLimit = 4 * 1024
    private static let shell = "/bin/zsh"
    /// 足够大，使话多的命令只需少量读取；又足够小，以保持实时性。
    private static let readSize = 16 * 1024
    /// 合并突发输出，避免大量输出时每行都触发一次重绘。
    private static let flushInterval: Duration = .milliseconds(40)
    /// 提示符或进度条永远不会换行；超过此长度就强制展示。
    private static let unlinedLimit = 4 * 1024
    /// 命令被停止后，留给它优雅退出的时间，超时即强杀。
    private static let stopGrace: DispatchTimeInterval = .seconds(2)
    /// 等待退出会阻塞，因此不占用协作线程池；这里是并发队列而非串行队列。
    private static let queue = DispatchQueue(
        label: "com.gearmac.shell-command", qos: .userInitiated, attributes: .concurrent)

    /// 发后不理，只保留错误尾部；需要展示的输出走 `stream`。
    nonisolated static func run(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false,
        workingDirectory: String? = nil
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: execute(
                        command, arguments: arguments,
                        loadingShellEnvironment: loadingShellEnvironment,
                        workingDirectory: workingDirectory))
            }
        }
    }

    nonisolated private static func execute(
        _ command: String, arguments: [String], loadingShellEnvironment: Bool,
        workingDirectory: String?
    ) -> ShellCommandResult {
        let launch: Launch
        do {
            launch = try prepare(
                command, arguments: arguments, loadingShellEnvironment: loadingShellEnvironment,
                workingDirectory: workingDirectory)
        } catch {
            return ShellCommandResult(termination: .launchFailed(error.reason))
        }
        defer { launch.removeScript() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = launch.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: launch.directory)
        // 让 shell 配置在调用方是 GearMac 时跳过耗时的段落。
        process.environment = ProcessInfo.processInfo.environment.merging(["GEARMAC": "1"]) { _, new in
            new
        }
        // 关键：配置中的交互提示会读到 EOF 后继续，从而永远不会挂住。
        process.standardInput = FileHandle.nullDevice

        let output = StreamCapture.make()
        let errors = StreamCapture.make()
        process.standardOutput = output?.handle ?? FileHandle.nullDevice
        process.standardError = errors?.handle ?? FileHandle.nullDevice
        defer {
            output?.remove()
            errors?.remove()
        }

        do {
            try process.runObservingExit().wait()
        } catch {
            return ShellCommandResult(termination: .launchFailed(error.localizedDescription))
        }

        return ShellCommandResult(
            termination: .exited(status: process.terminationStatus),
            standardOutput: output?.readSuffix(limit: standardOutputLimit),
            standardError: errors?.readSuffix(limit: standardErrorLimit))
    }

    // MARK: - Streaming

    /// 在伪终端下运行；管道为何做不到这一点见 `PseudoTerminal`。
    nonisolated static func stream(
        _ command: String, arguments: [String] = [], loadingShellEnvironment: Bool = false,
        workingDirectory: String? = nil
    ) -> ShellCommandSession {
        let launch: Launch
        do {
            launch = try prepare(
                command, arguments: arguments, loadingShellEnvironment: loadingShellEnvironment,
                workingDirectory: workingDirectory)
        } catch {
            return failedSession(error.reason)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GEARMAC"] = "1"
        // 终端会让工具输出彩色，因此声明窗口能够绘制的颜色。
        environment["TERM"] = "xterm-256color"

        guard
            let terminal = PseudoTerminal.spawn(
                executable: shell, arguments: launch.arguments, environment: environment,
                workingDirectory: launch.directory)
        else {
            launch.removeScript()
            return failedSession("The shell could not be started.")
        }

        let stopped = StopFlag()
        let events = AsyncStream<ShellCommandEvent> { continuation in
            queue.async {
                drain(terminal, stopped: stopped, into: continuation)
                launch.removeScript()
            }
        }
        return ShellCommandSession(
            events: events,
            stop: { [weak stopFlag = stopped] in
                stopFlag?.mark()
                terminal.signalSession(SIGTERM)
                // 兜底手段，用于无视礼貌请求的命令。
                queue.asyncAfter(deadline: .now() + stopGrace) {
                    terminal.signalSession(SIGKILL)
                }
            })
    }

    nonisolated private static func failedSession(_ reason: String) -> ShellCommandSession {
        ShellCommandSession(
            events: AsyncStream { continuation in
                continuation.yield(.finished(ShellCommandResult(termination: .launchFailed(reason))))
                continuation.finish()
            },
            stop: {})
    }

    /// 单队列单读取者：解码缓冲区只在这里被访问，因此无需加锁。
    nonisolated private static func drain(
        _ terminal: PseudoTerminal, stopped: StopFlag,
        into continuation: AsyncStream<ShellCommandEvent>.Continuation
    ) {
        var decoder = TerminalTextDecoder()
        var buffer = [UInt8](repeating: 0, count: readSize)
        var lastYield = ContinuousClock().now

        while true {
            // 返回 0 表示 EOF；返回 -1 且 errno 为 EIO，是 pty 主端在子进程消失后的表现。
            let count = read(terminal.parentEnd, &buffer, readSize)
            guard count > 0 else { break }
            decoder.append(buffer, count: count)
            let due = ContinuousClock().now - lastYield >= flushInterval
            if let text = decoder.take(force: due) {
                continuation.yield(.output(text))
                lastYield = ContinuousClock().now
            }
        }
        if let text = decoder.take(force: true) { continuation.yield(.output(text)) }

        let status = terminal.wait()
        terminal.close()
        continuation.yield(
            .finished(
                ShellCommandResult(
                    termination: stopped.isSet ? .stopped : .exited(status: status))))
        continuation.finish()
    }

    /// 由主 actor 设置、在 drain 队列读取，因此该标志自带锁。
    private final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func mark() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    /// 只输出完整行：换行符是标量边界，因此任何一次读取都不会在字符中间解码。
    private struct TerminalTextDecoder {
        private var pending: [UInt8] = []

        /// 追加新读到的字节，等待组成完整行后再取出。
        mutating func append(_ bytes: [UInt8], count: Int) {
            pending.append(contentsOf: bytes[0..<count])
        }

        /// `force` 在退出时、以及提示符始终不换行时强制冲刷，但仍切在字符边界上。
        mutating func take(force: Bool) -> String? {
            guard !pending.isEmpty else { return nil }
            var end = pending.lastIndex(of: 0x0A).map { $0 + 1 }
            if end == nil {
                guard force || pending.count >= unlinedLimit else { return nil }
                end = scalarBoundary(before: pending.count)
            }
            guard let end, end > 0 else { return nil }
            // Latin-1 解码不会失败，因此其他编码的内容仍能送达读者。
            let bytes = Array(pending[0..<end])
            pending.removeFirst(end)
            return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1)
        }

        /// 最多回退三个续字节，定位到完整字符的起点。
        private func scalarBoundary(before index: Int) -> Int {
            var boundary = index
            var stepped = 0
            while boundary > 0, stepped < 4, pending[boundary - 1] & 0xC0 == 0x80 {
                boundary -= 1
                stepped += 1
            }
            // 仅当首字节所在的序列尚未完整时，才回退到该首字节。
            guard boundary > 0 else { return index }
            let lead = pending[boundary - 1]
            let width = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            return index - boundary + 1 >= width ? index : boundary - 1
        }
    }

    /// 指定的目录不存在时返回 nil：在非预期位置运行比不运行更糟。
    nonisolated private static func resolvedWorkingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return expanded
    }

    /// 一次运行所创建的内容；`#!` 命令还会持有一个供 zsh 执行的脚本文件。
    private struct Launch: Sendable {
        let arguments: [String]
        let directory: String
        let script: URL?

        /// 删除临时脚本文件（若有）。
        func removeScript() {
            guard let script else { return }
            try? FileManager.default.removeItem(at: script)
        }
    }

    /// 启动失败的原因，携带面向用户的说明。
    private struct LaunchFailure: Error {
        let reason: String
    }

    /// 取值以 `$1`、`$2` 的形式跟在后面，绝不拼接进命令文本，以免被 zsh 当作语法重新解析。
    nonisolated private static func prepare(
        _ command: String, arguments: [String], loadingShellEnvironment: Bool,
        workingDirectory: String?
    ) throws(LaunchFailure) -> Launch {
        guard let directory = resolvedWorkingDirectory(workingDirectory) else {
            throw LaunchFailure(reason: "The folder “\(workingDirectory ?? "")” no longer exists.")
        }
        // zsh 只对交互式 shell 读取 `.zshrc`，因此仅用 `-l` 看不到别名。
        let flag = loadingShellEnvironment ? "-ilc" : "-lc"
        guard command.hasPrefix("#!") else {
            return Launch(
                arguments: [flag, command, "gearmac"] + arguments, directory: directory,
                script: nil)
        }
        // 由内核读取 `#!` 行，因此文本会直接交给对应解释器，不经过 zsh 解析。
        let script = FileManager.default.temporaryDirectory
            .appending(path: "gearmac-command-script-\(UUID().uuidString)")
        guard
            FileManager.default.createFile(
                atPath: script.path, contents: Data(command.utf8),
                attributes: [.posixPermissions: 0o700])
        else { throw LaunchFailure(reason: "The script could not be written.") }
        return Launch(
            arguments: [flag, #"exec "$0" "$@""#, script.path] + arguments, directory: directory,
            script: script)
    }

    /// 使用临时文件而非 `Pipe`：管道在命令退出前无人读取。
    private final class StreamCapture: @unchecked Sendable {
        let url: URL
        let handle: FileHandle

        /// 以给定的临时文件 URL 与句柄创建捕获器。
        init(url: URL, handle: FileHandle) {
            self.url = url
            self.handle = handle
        }

        /// 读取文件末尾至多 `limit` 字节的文本；无内容时返回 nil。
        func readSuffix(limit: Int) -> String? {
            try? handle.synchronize()
            guard let end = try? handle.seekToEnd() else { return nil }
            let start = end > UInt64(limit) ? end - UInt64(limit) : 0
            try? handle.seek(toOffset: start)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
            // 按字节偏移截取的尾部可能切在字符中间；丢弃孤立的续字节可避免开头出现 U+FFFD。
            let body = start > 0 ? data.drop { $0 & 0xC0 == 0x80 } : data[...]
            return String(decoding: body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        func remove() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }

        /// 创建一个临时文件用于捕获输出；失败时返回 nil。
        static func make() -> StreamCapture? {
            let template = FileManager.default.temporaryDirectory
                .appendingPathComponent("gearmac-command-stream.XXXXXX").path
            var bytes = Array(template.utf8CString)
            let descriptor = bytes.withUnsafeMutableBufferPointer { buffer in
                mkstemp(buffer.baseAddress!)
            }
            guard descriptor >= 0 else { return nil }
            let path = String(
                decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return StreamCapture(
                url: URL(fileURLWithPath: path),
                handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
        }
    }
}

extension String {
    /// 字符串为空时返回 nil，否则返回自身。
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
