// 文件职责：以带看门狗、输出上限与取消机制的短时子进程方式运行已安装 CLI 命令并读取输出。
// 分层：Service；不接触 UI，仅提供一次性运行、保持管道等待回答、版本号与登录态解析。
import Foundation

/// 一次短时的命令运行，受看门狗、输出上限与取消三重约束。
enum InstalledAIProbe {
    private static let maximumOutputBytes = 2 * 1_048_576
    private static let readChunkBytes = 64 * 1_024

    /// 命令运行结果：退出状态码与标准输出文本。
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    /// 可跨并发传递的进程句柄，用锁保证“设置进程”与“取消”即使竞态也不会漏掉终止。
    private final class ProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        /// 将新进程交给句柄；若此前已被取消，则立即终止该进程。
        func set(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldTerminate = cancelled
            lock.unlock()
            if shouldTerminate { process.terminate() }
        }

        /// 标记已取消并终止当前进程（若存在且仍在运行）。
        func cancel() {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            if let process, process.isRunning { process.terminate() }
        }
    }

    /// `input` 会被完整写入并随后关闭管道，适用于应答单次请求即退出的 CLI。
    nonisolated static func run(
        executable: URL, arguments: [String], workspace: URL,
        environment: [String: String]? = nil, input: Data? = nil,
        timeout: Duration = .seconds(10)
    ) async -> Result {
        let handle = ProcessHandle()
        return await withTaskCancellationHandler(
            operation: {
                // 使用 detached：读取循环与退出等待会阻塞，因此绝不能占用线程池线程。
                await Task.detached {
                    try? FileManager.default.createDirectory(
                        at: workspace, withIntermediateDirectories: true)
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.currentDirectoryURL = workspace
                    process.environment =
                        environment ?? ExecutableLocator.environment(running: executable)
                    let stdin = input.map { _ in Pipe() }
                    process.standardInput = stdin ?? FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    guard let exit = try? process.runObservingExit() else {
                        return Result(status: -1, output: "")
                    }
                    handle.set(process)
                    if let stdin, let input { Self.write(input, to: stdin, closing: true) }
                    let watchdog = Task {
                        try? await Task.sleep(for: timeout)
                        if process.isRunning { process.terminate() }
                    }
                    var data = Data()
                    while data.count < Self.maximumOutputBytes {
                        let count = min(Self.readChunkBytes, Self.maximumOutputBytes - data.count)
                        guard let chunk = try? output.fileHandleForReading.read(upToCount: count),
                            !chunk.isEmpty
                        else { break }
                        data.append(chunk)
                    }
                    if data.count == Self.maximumOutputBytes, process.isRunning {
                        process.terminate()
                    }
                    exit.wait()
                    watchdog.cancel()
                    return Result(
                        status: process.terminationStatus,
                        output: String(bytes: data, encoding: .utf8) ?? "")
                }.value
            },
            onCancel: {
                handle.cancel()
            })
    }

    /// 保持 stdin 打开直到某一行满足查询条件，因为 CLI 会在输入关闭后退退。
    nonisolated static func request(
        executable: URL, arguments: [String], workspace: URL,
        environment: [String: String]? = nil, input: Data,
        until answered: @escaping @Sendable (String) -> Bool, timeout: Duration = .seconds(30)
    ) async -> String {
        await Task.detached {
            try? FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
            let process = Process()
            let stdin = Pipe()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workspace
            process.environment =
                environment ?? ExecutableLocator.environment(running: executable)
            process.standardInput = stdin
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard let exit = try? process.runObservingExit() else { return "" }
            Self.write(input, to: stdin, closing: false)
            let watchdog = Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning { process.terminate() }
            }
            var data = Data()
            // 不用 `read(upToCount:)`，因为它会等到读满一个块或 EOF，也就等于等到了看门狗。
            while data.count < Self.maximumOutputBytes {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                data.append(chunk)
                if answered(String(bytes: data, encoding: .utf8) ?? "") { break }
            }
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            exit.wait()
            watchdog.cancel()
            return String(bytes: data, encoding: .utf8) ?? ""
        }.value
    }

    /// 若子进程在读取前退出，写入必须返回失败，而不是让 GearMac 收到 SIGPIPE。
    nonisolated private static func write(_ data: Data, to pipe: Pipe, closing: Bool) {
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? pipe.fileHandleForWriting.write(contentsOf: data)
        if closing { try? pipe.fileHandleForWriting.close() }
    }

    /// 从命令输出中提取首个版本号（如 `1.2.3`，可带预发布与构建后缀）。
    nonisolated static func version(in output: String) -> String? {
        output.firstMatch(of: #/\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/#).map {
            String($0.output)
        }
    }

    /// 从状态 JSON 中判断是否已登录；兼容 `loggedIn`/`authenticated`/`isAuthenticated` 三种字段。
    nonisolated static func loggedIn(inStatusJSON output: String) -> Bool {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true
            || object["authenticated"] as? Bool == true
            || object["isAuthenticated"] as? Bool == true
    }

}
