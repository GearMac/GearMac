// 文件职责：管理听写模型的安装状态、下载、删除、转录调度与闲置释放。
// 分层：Service/@MainActor；模型存储目录位于 caches，推理交由 DictationWorker 子进程。
import Foundation

/// 模型仓库：对外暴露安装/下载/转录能力，内部维护单个常驻 worker。
@MainActor
@Observable
final class DictationModelStore {
    typealias Failure = DictationWire.Failure

    private(set) var downloading: DictationModel?
    private(set) var downloadProgress: (received: Int64, total: Int64)?
    private(set) var removing: DictationModel?
    private(set) var transcribing = false
    private(set) var loadedModel: DictationModel?
    private(set) var installedModels: Set<DictationModel> = []
    @ObservationIgnored private var worker: DictationWorker?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var idleRelease: DictationIdleRelease
    @ObservationIgnored private var downloadTask: Task<Void, Error>?
    @ObservationIgnored private var downloadID: UUID?
    private let root: URL
    private let makeWorker: () throws -> DictationWorker

    /// 初始化存储根目录与 worker 工厂，并刷新已安装模型。
    init(
        idleRelease: DictationIdleRelease,
        root: URL = AppPaths.caches().appending(path: "Dictation"),
        makeWorker: @escaping () throws -> DictationWorker = { try DictationWorker() }
    ) {
        self.idleRelease = idleRelease
        self.root = root
        self.makeWorker = makeWorker
        refreshInstalledModels()
    }

    /// 更新闲置释放策略，必要时重排释放任务。
    func setIdleRelease(_ option: DictationIdleRelease) {
        idleRelease = option
        if worker != nil, !transcribing {
            scheduleRelease()
        } else {
            releaseTask?.cancel()
            releaseTask = nil
        }
    }

    /// 指定模型所需文件是否齐全。
    func isInstalled(_ model: DictationModel) -> Bool {
        installedModels.contains(model)
    }

    /// 重新扫描磁盘，更新已安装模型集合。
    func refreshInstalledModels() {
        installedModels = Set(
            DictationModel.allCases.filter { model in
                let directory = directory(for: model)
                return model.requiredFiles.allSatisfy {
                    FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
                }
            })
    }

    /// 统计已安装模型占用的字节数（后台遍历，可取消）。
    func installedSize(_ model: DictationModel) async -> Int64? {
        guard isInstalled(model) else { return nil }
        let directory = directory(for: model)
        let task = Task.detached(priority: .utility) { () -> Int64? in
            guard
                let files = FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            else { return nil }
            var size: Int64 = 0
            while let url = files.nextObject() as? URL {
                guard !Task.isCancelled else { return nil }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let bytes = values.fileSize
                else { continue }
                size += Int64(bytes)
            }
            return size
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 下载模型，转发进度并串行化并发请求。
    func download(_ model: DictationModel) async throws {
        guard downloading == nil, removing != model else { throw Failure.busy }
        guard !isInstalled(model) else { return }
        downloading = model
        let id = UUID()
        downloadID = id
        let destination = directory(for: model)
        let task = Task.detached(priority: .utility) { [weak self] in
            try await DictationModelDownloader.download(model, destination: destination) {
                [weak self] received, total in
                Task { @MainActor [weak self] in
                    guard let self, self.downloadID == id else { return }
                    self.downloadProgress = (max(self.downloadProgress?.received ?? 0, received), total)
                }
            }
        }
        downloadTask = task
        defer { downloading = nil; downloadTask = nil; downloadID = nil; downloadProgress = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        installedModels.insert(model)
    }

    /// 取消进行中的下载。
    func cancelDownload() {
        downloadID = nil
        downloadTask?.cancel()
    }

    /// 删除已安装模型；转录中或下载同一模型时报 busy。
    func delete(_ model: DictationModel) async throws {
        guard !transcribing, removing == nil, downloading != model else { throw Failure.busy }
        removing = model
        defer { removing = nil }
        if loadedModel == model { await release() }
        let directory = directory(for: model)
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }.value
        installedModels.remove(model)
    }

    /// 用指定模型转录采样，必要时重载 worker 并管理闲置释放。
    func transcribe(
        _ samples: [Float], model: DictationModel, language: String? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        guard !transcribing, removing != model else { throw Failure.busy }
        guard isInstalled(model) else { throw Failure.notInstalled }
        releaseTask?.cancel()
        releaseTask = nil
        transcribing = true
        defer { transcribing = false; scheduleRelease() }
        do {
            if loadedModel != model { await release() }
            try Task.checkCancellation()
            let worker = try self.worker ?? makeWorker()
            self.worker = worker
            let request = DictationWire.Request(
                id: UUID(), model: model, directory: directory(for: model),
                sampleCount: samples.count, language: model.isQwen ? language : nil)
            let text = try await worker.transcribe(samples, request: request) { [weak self] in
                guard let self, self.worker === worker, self.transcribing else { return }
                self.loadedModel = model
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            await release()
            throw error
        }
    }

    /// 释放常驻 worker 与已加载模型。
    func release() async {
        releaseTask?.cancel()
        releaseTask = nil
        let worker = self.worker
        self.worker = nil
        loadedModel = nil
        await worker?.stop()
    }

    /// 取消下载并释放 worker（停用听写时调用）。
    func stop() async {
        downloadTask?.cancel()
        try? await downloadTask?.value
        await release()
    }

    /// 退出前立即取消下载并终止 worker 进程。
    func prepareForTermination() { downloadTask?.cancel(); worker?.terminate() }

    /// 按闲置时长安排一次模型释放，转录结束或策略变化时重排。
    private func scheduleRelease() {
        releaseTask?.cancel()
        guard worker != nil, idleRelease != .never else { releaseTask = nil; return }
        let interval = Duration.seconds(idleRelease.rawValue * 60)
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: interval, tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let self, !self.transcribing else { return }
            await self.release()
        }
    }

    /// 某个模型在缓存根下的存放目录。
    private func directory(for model: DictationModel) -> URL {
        root.appendingPathComponent(model.folderName)
    }
}
