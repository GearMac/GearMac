// 文件职责：运行外部命令行工具并收集其合并后的标准输出与错误输出。
// 分层：Service（Process/Pipe 封装，并发安全）；只负责超时控制与输出采集，不做业务判断。
import Foundation

/// 边到达边读取，避免工具写满管道缓冲区后卡死。
enum ToolRunner {
    /// 一次工具调用的结果：退出码与合并输出。
    struct Result: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }

        /// 取输出尾部，工具通常把真正的错误信息放在那里。
        var tail: String {
            let lines = output.split(separator: "\n").suffix(8)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "no output" : text
        }
    }

    /// `timeout` 为 nil 时永不杀进程：工具可能是在等人操作，而不是卡死。
    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval? = 120
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = OutputCollector()
        pipe.fileHandleForReading.readabilityHandler = { collector.absorb($0.availableData) }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                collector.absorb((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                continuation.resume(
                    returning: Result(status: finished.terminationStatus, output: collector.text))
            }
            do {
                try process.run()
            } catch {
                // 从未启动成功的进程不会触发终止回调，因此在此处直接返回错误。
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            guard let timeout else { return }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }
}

/// 会被管道读取队列与终止回调同时写入，因此这把锁必不可少。
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// 已缓冲字节的解码结果。
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Latin-1 解码不会失败，使用其他编码的内容也仍能呈现给用户。
        return String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1) ?? ""
    }

    /// 缓冲的是字节而非文本：若在字符中间解码会得到替换字符。
    func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}
