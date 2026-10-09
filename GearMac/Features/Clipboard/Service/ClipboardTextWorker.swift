// 文件职责：将文本提取交给 ClipboardTextHelper 子进程执行，收集标准输出并处理超时与取消。
// 分层：Service；nonisolated，通过子进程隔离 Vision 的内存分配，避免影响主程序。
import Foundation

/// 每个条目运行一个 `ClipboardTextHelper` 子进程，使 Vision 的内存分配随子进程一起释放。
nonisolated enum ClipboardTextWorker {
    /// 子进程提取失败的原因：识别失败或输出超限。
    enum Failure: Error { case recognition, outputLimit }

    /// 与 `ClipboardTextExtractor.maximumTextBytes` 保持一致：helper 不在主应用模块内。
    private static let maximumOutputBytes = 32_000
    private static let readSize = 4096
    /// 读取循环与退出等待会阻塞，因此放在该队列上，避免占用协作线程池。
    private static let queue = DispatchQueue(
        label: "com.gearmac.clipboard-text", qos: .background, attributes: .concurrent)

    /// 针对剪贴板条目提取文本；非图片/PDF 条目返回空串。
    static func extract(_ item: ClipboardItem) async throws -> String {
        guard let path = item.imagePath ?? item.filePath else { return "" }
        let kind = item.kind == .image ? ClipboardFileKind.image : ClipboardFileKind.of(path: path)
        guard kind == .image || kind == .pdf else { return "" }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ClipboardTextHelper")
        return try await extract(at: URL(fileURLWithPath: path), isPDF: kind == .pdf, executable: executable)
    }

    /// 启动 helper 子进程提取文本，处理超时、取消与输出上限。
    static func extract(
        at url: URL, isPDF: Bool, executable: URL, timeout: Duration = .seconds(60)
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [isPDF ? "pdf" : "image", url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .background
        guard let exit = try? process.runObservingExit() else { throw Failure.recognition }
        // 取消可能落在上面的检查与进程启动之间，这一步没有其它地方能捕获到。
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .background) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: collect(from: process, awaiting: exit, reading: output))
                }
            }
        } onCancel: {
            terminate(process)
        }
        deadline.cancel()
        try Task.checkCancellation()
        return try result.get()
    }

    /// 全程阻塞，也是唯一回收 helper 的位置：每条退出路径都会执行 `defer`。
    private static func collect(
        from process: Process, awaiting exit: ProcessExit, reading output: Pipe
    ) -> Result<String, Failure> {
        let reader = output.fileHandleForReading
        defer {
            terminate(process)
            exit.wait()
            try? reader.close()
        }
        var data = Data()
        do {
            while let chunk = try reader.read(upToCount: readSize), !chunk.isEmpty {
                data.append(chunk)
                if data.count > maximumOutputBytes { return .failure(.outputLimit) }
            }
        } catch {
            return .failure(.recognition)
        }
        exit.wait()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return .failure(.recognition)
        }
        return .success(text)
    }

    /// `terminate()` 对未启动的进程会触发陷阱，因此必须先查询进程状态。
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
