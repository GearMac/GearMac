// 文件职责：在系统空闲时后台调度剪贴板条目的 OCR 文本提取，失败时按重试间隔重试。
// 分层：Service；@MainActor 隔离，通过注入的 canRun/extract 与环境解耦，只写入 ClipboardStore。
import CoreGraphics
import OSLog

/// 剪贴板 OCR 文本索引器：在系统空闲时后台提取条目文本，失败后按重试间隔重试。
@MainActor
final class ClipboardTextIndexer {
    private let store: ClipboardStore
    private let canRun: () -> Bool
    private let extract: @Sendable (ClipboardItem) async throws -> String
    private let retryDelay: TimeInterval
    private let delay: Duration
    private var task: Task<Void, Never>?
    private var isEnabled = false
    private var waitingForRetry = false
    /// 仅系统空闲时才启动识别，且忙碌的 Mac 也会保持同样的空闲窗口后再重检。
    private static let idleWindow: TimeInterval = 2
    private static let logger = Logger(subsystem: "com.gearmac", category: "ClipboardText")

    /// 创建索引器；canRun 判断当前是否允许运行，extract 为可注入的提取实现。
    init(
        store: ClipboardStore, delay: Duration = .milliseconds(250), retryDelay: TimeInterval = 30,
        canRun: @escaping () -> Bool,
        extract: @escaping @Sendable (ClipboardItem) async throws -> String = ClipboardTextWorker.extract
    ) {
        self.store = store
        self.delay = delay
        self.retryDelay = retryDelay
        self.canRun = canRun
        self.extract = extract
    }

    isolated deinit {
        task?.cancel()
    }

    /// 系统是否已空闲到给定时间窗口，用于避免抢占用户输入。
    static var isSystemIdle: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null) >= idleWindow
    }

    /// 启用索引器并开始调度。
    func start() {
        isEnabled = true
        schedule()
    }

    /// 停用索引器并取消进行中的调度任务。
    func stop() {
        isEnabled = false
        task?.cancel()
    }

    /// 等待当前调度任务结束。
    func waitUntilStopped() async {
        await task?.value
    }

    /// 安排后台循环：轮询待提取条目，空闲时执行 OCR，失败则等待重试。
    func schedule() {
        guard isEnabled else { return }
        if waitingForRetry {
            task?.cancel()
            return
        }
        guard task == nil else { return }
        let delay = delay
        task = Task(priority: .background) { [weak self] in
            defer {
                self?.task = nil
                self?.waitingForRetry = false
                if Task.isCancelled, self?.isEnabled == true { self?.schedule() }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self, self.isEnabled else { return }
                guard let item = self.store.nextExtractionItem() else {
                    guard let retry = self.store.nextExtractionRetry else { return }
                    self.waitingForRetry = true
                    do { try await Task.sleep(for: .seconds(max(0, retry.timeIntervalSinceNow))) } catch {
                        return
                    }
                    self.waitingForRetry = false
                    continue
                }
                guard self.canRun() else {
                    do { try await Task.sleep(for: .seconds(Self.idleWindow)) } catch { return }
                    continue
                }
                let generation = self.store.extractionGeneration
                let extract = self.extract
                let worker = Task.detached(priority: .background) { try await extract(item) }
                do {
                    let text = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    try Task.checkCancellation()
                    self.store.setExtractedText(text, for: item, generation: generation)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.logger.error(
                        "Clipboard text extraction failed: \(String(describing: error), privacy: .private)")
                    self.store.recordExtractionFailure(
                        for: item, generation: generation,
                        retryAt: Date().addingTimeInterval(self.retryDelay))
                }
            }
        }
    }
}
