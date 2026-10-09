// 文件职责：为扩展提供 host 侧的 `fetch` 网络请求与异步子进程（proc）支持。
// 分层：Service；请求体/响应体以 base64 跨桥传输，子进程按 pid 登记并支持超时终止。
import Foundation
import Synchronization

/// 请求体以 base64 编码跨越桥接层，从而能保留二进制响应。
final class ExtensionFetcher: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    enum FetchError: LocalizedError {
        case badURL(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let url): return "Invalid URL: \(url)"
            }
        }
    }

    /// 按 JS 侧传入的 `{url, method, headers, bodyBase64}` 描述发起请求，返回含状态码、响应头与 base64 响应体的字典。
    func request(_ spec: RenderValue?) async throws -> [String: Any] {
        let fields = spec?.objectValue ?? [:]
        let urlString = fields["url"]?.stringValue ?? ""
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw FetchError.badURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = fields["method"]?.stringValue ?? "GET"
        for (name, value) in fields["headers"]?.objectValue ?? [:] {
            guard let text = value.stringValue else { continue }
            request.setValue(text, forHTTPHeaderField: name)
        }
        if let base64 = fields["bodyBase64"]?.stringValue, let body = Data(base64Encoded: base64) {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            guard let name = key as? String, let text = value as? String else { continue }
            headers[name.lowercased()] = text
        }
        let status = http?.statusCode ?? 200
        return [
            "status": status,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
            "headers": headers,
            "url": response.url?.absoluteString ?? urlString,
            "bodyBase64": data.base64EncodedString()
        ]
    }
}

/// `ExtensionNodeShims` 在 JS 队列上启动子进程；`wait` 在该队列之外回收它。
enum ExtensionAsyncProcess {
    enum ProcessError: LocalizedError {
        case notStarted

        var errorDescription: String? { "No running child process with that pid." }
    }

    /// 一个已启动的子进程及其管道。
    struct Child: Sendable {
        let task: Process
        let exit: ProcessExit
        let stdout: Pipe
        let stderr: Pipe

        /// 子进程写满 64 KB 管道后会阻塞而无法退出，因此先排空管道。
        func collect(timeout: Double?) -> [String: Any] {
            var watchdog: DispatchSourceTimer?
            if let timeout, timeout > 0 { watchdog = terminationWatchdog(after: timeout / 1000) }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            exit.wait()
            watchdog?.cancel()

            return [
                "stdout": outData.base64EncodedString(),
                "stderr": errData.base64EncodedString(),
                "status": Int(task.terminationStatus),
                "signal": task.terminationReason == .uncaughtSignal ? "SIGTERM" : NSNull()
            ]
        }

        /// 向 pid 发送信号而非操作 `Process`，因为 `@Sendable` 的定时器回调无法捕获它。
        fileprivate func terminationWatchdog(after seconds: Double) -> DispatchSourceTimer {
            let pid = task.processIdentifier
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + seconds)
            timer.setEventHandler { kill(pid, SIGTERM) }
            timer.resume()
            return timer
        }
    }

    /// 由 `enqueue` 启动、尚未被 `wait` 领取的子进程，以 pid 为键。
    private static let uncollected = Mutex<[Int32: (child: Child, watchdog: DispatchSourceTimer?)]>([:])

    /// 在 PATH（含 Homebrew 等常见目录）中解析可执行文件；App bundle 不会继承登录 shell 的环境，因此直接调用裸 `brew` 会失败。
    static func resolveExecutable(_ command: String) -> URL? {
        let fileManager = FileManager.default
        if command.contains("/") {
            let expanded = (command as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded)
                ? URL(fileURLWithPath: expanded) : nil
        }
        let search =
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [
                "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin",
                "/sbin"
            ]
        for directory in search {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// 登记已启动的子进程，并按超时时长提前武装看门狗。
    static func enqueue(_ child: Child, timeout: Double?) {
        // 在启动时就设定：`wait` 要等流式输出结束后才开始计时。
        let watchdog = timeout.flatMap { $0 > 0 ? child.terminationWatchdog(after: $0 / 1000) : nil }
        uncollected.withLock { $0[child.task.processIdentifier] = (child, watchdog) }
    }

    /// 读取 fd 1 或 2 的下一块数据，EOF 时返回 nil；随后 `wait` 会发现两个管道都已排空。
    static func read(_ arguments: [RenderValue]) async throws -> String? {
        guard let pid = arguments.first?.doubleValue.flatMap({ Int32(exactly: $0) }),
            let child = uncollected.withLock({ $0[pid]?.child })
        else { throw ProcessError.notStarted }
        let pipe = arguments[safe: 1]?.doubleValue == 2 ? child.stderr : child.stdout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.availableData
                continuation.resume(returning: data.isEmpty ? nil : data.base64EncodedString())
            }
        }
    }

    /// 回收该 pid 的子进程，返回 stdout/stderr、退出码与信号信息。
    static func wait(_ pid: RenderValue?) async throws -> [String: Any] {
        guard let pid = pid?.doubleValue.flatMap({ Int32(exactly: $0) }),
            let entry = uncollected.withLock({ $0.removeValue(forKey: pid) })
        else { throw ProcessError.notStarted }

        let child = entry.child
        let result = await withCheckedContinuation { continuation in
            // 排空操作会一直阻塞到子进程关闭输出，这可能要等好几分钟。
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: child.collect(timeout: nil))
            }
        }
        entry.watchdog?.cancel()
        return result
    }
}
