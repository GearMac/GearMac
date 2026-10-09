// 文件职责：以子进程方式驱动 DictationHelper 辅助程序，通过管道输送采样并取回文本。
// 分层：Service/进程封装；所有管道读写串行在专用队列，超时或取消即终止子进程。
import Foundation

/// 常驻辅助进程的封装：一次可复用多次转录，附超时与终止处理。
final class DictationWorker: Sendable {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let exit: ProcessExit
    private let queue = DispatchQueue(label: "com.gearmac.dictation-worker", qos: .userInitiated)

    /// 启动辅助进程并接线 stdin/stdout 管道。
    init(executable: URL = DictationWorker.executable, arguments: [String] = []) throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(.EIO)
        }
        self.exit = try process.runObservingExit()
        self.process = process
        self.input = input.fileHandleForWriting
        self.output = output.fileHandleForReading
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }

    /// 辅助程序在 bundle 内的可执行文件路径。
    static var executable: URL {
        Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/\(executableName).app/Contents/MacOS/\(executableName)")
    }

    /// 按构建配置选择辅助程序名称。
    private static var executableName: String {
        #if DEBUG
            "GearMac-dev Dictation"
        #else
            "GearMac Dictation"
        #endif
    }

    /// 发送请求与采样，等待 ready/result 应答，超时或取消时终止进程。
    func transcribe(
        _ samples: [Float], request: DictationWire.Request,
        onReady: @escaping @MainActor @Sendable () -> Void
    ) async throws -> String {
        try Task.checkCancellation()
        guard samples.count == request.sampleCount, (1...DictationWire.maximumSamples).contains(samples.count)
        else {
            throw DictationWire.Failure.unavailable
        }
        let timeout = 60 + samples.count / DictationWire.sampleRate * 2
        let deadline = Task.detached(priority: .utility) {
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            self.terminate()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            let responses = AsyncThrowingStream<DictationWire.Response, Error>(
                bufferingPolicy: .bufferingOldest(2)
            ) { continuation in
                queue.async {
                    do {
                        try DictationWire.write(request, to: self.input)
                        guard
                            let ready = try DictationWire.read(
                                DictationWire.Response.self, from: self.output),
                            ready.id == request.id, ready.status == .ready
                        else {
                            throw DictationWire.Failure.unavailable
                        }
                        continuation.yield(ready)
                        try samples.withUnsafeBytes { try self.input.write(contentsOf: $0) }
                        guard
                            let result = try DictationWire.read(
                                DictationWire.Response.self, from: self.output),
                            result.id == request.id, result.status == .result
                        else {
                            throw DictationWire.Failure.unavailable
                        }
                        continuation.yield(result)
                        continuation.finish()
                    } catch {
                        self.terminate()
                        continuation.finish(throwing: error)
                    }
                }
            }
            var text: String?
            for try await response in responses {
                if response.status == .ready { await onReady() }
                if response.status == .result { text = response.text }
            }
            try Task.checkCancellation()
            guard let text else { throw DictationWire.Failure.unavailable }
            return text
        } onCancel: {
            self.terminate()
        }
    }

    /// 终止子进程（若仍在运行）。
    func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// 终止进程并等待退出，随后关闭管道。
    func stop() async {
        terminate()
        await withCheckedContinuation { continuation in
            queue.async {
                self.exit.wait()
                try? self.input.close()
                try? self.output.close()
                continuation.resume()
            }
        }
    }
}
