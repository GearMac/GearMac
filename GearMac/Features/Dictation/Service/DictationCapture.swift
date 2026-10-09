// 文件职责：用 AVCaptureSession 采集麦克风音频，产出浮点采样并实时计算频谱电平。
// 分层：Service/@MainActor；采集回调在专用队列，UI 回调切回主线程。
import AVFoundation
import AudioToolbox
import CoreMedia

/// 麦克风采集器：负责权限、设备选择、会话生命周期与电平回调。
@MainActor
final class DictationCapture {
    /// 采集相关的用户可见错误。
    enum Failure: LocalizedError {
        case microphoneUnavailable
        case microphoneDenied
        case captureUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: return L10n.string(DictationKey.failNoMicrophone, language: .english)
            case .microphoneDenied: return L10n.string(DictationKey.failMicrophoneDenied, language: .english)
            case .captureUnavailable: return L10n.string(DictationKey.failCaptureUnavailable, language: .english)
            }
        }

        /// 按指定语言解析错误文案。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .microphoneUnavailable: return L10n.string(DictationKey.failNoMicrophone, language: language)
            case .microphoneDenied: return L10n.string(DictationKey.failMicrophoneDenied, language: language)
            case .captureUnavailable: return L10n.string(DictationKey.failCaptureUnavailable, language: language)
            }
        }
    }

    /// 当前可用的麦克风设备列表。
    static var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    /// 电平更新回调（主线程）。
    var onLevels: (([Float]) -> Void)?
    /// 达到最大采样数时的回调。
    var onLimit: (() -> Void)?

    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var collector: AudioCollector?

    /// 请求麦克风权限、按设备 ID 启动采集会话，失败时抛 Failure。
    func start(microphoneID: String?) async throws {
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        if permission == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            granted = permission == .authorized
        }
        guard granted else { throw Failure.microphoneDenied }
        let device =
            microphoneID.map { id in Self.microphones.first { $0.uniqueID == id } }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw Failure.microphoneUnavailable }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Failure.captureUnavailable
        }

        let capture = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DictationWire.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            throw Failure.captureUnavailable
        }
        capture.addInput(input)
        capture.addOutput(output)
        let collector = try AudioCollector(
            onLevels: { [weak self] levels in
                Task { @MainActor [weak self] in self?.onLevels?(levels) }
            },
            onLimit: { [weak self] in
                Task { @MainActor [weak self] in self?.onLimit?() }
            })
        output.setSampleBufferDelegate(collector, queue: collector.queue)
        self.session = capture
        self.output = output
        self.collector = collector
        let box = CaptureSessionBox(capture)
        await Task.detached { box.session.startRunning() }.value
        guard capture.isRunning else {
            _ = await stop()
            throw Failure.captureUnavailable
        }
    }

    /// 停止采集并返回已录制的全部采样。
    func stop() async -> [Float] {
        guard let session else { return [] }
        self.session = nil
        let box = CaptureSessionBox(session)
        await Task.detached { box.session.stopRunning() }.value
        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        let samples = collector?.finish() ?? []
        collector = nil
        return samples
    }
}

// 会话配置必须在主线程；仅 start/stop 串行地在后台执行。
private struct CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

// 采样缓冲与可变状态都限制在代理队列上，finish() 也在该队列同步读取。
private final class AudioCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    let queue = DispatchQueue(label: "com.gearmac.dictation.audio")
    private var samples: [Float] = []
    private var displayedLevels: [Float]
    private let spectrum: DictationSpectrum
    private var waveformStartIndex = 0
    private var lastLevelUpdate: TimeInterval = 0
    private var reachedLimit = false
    private let onLevels: @Sendable ([Float]) -> Void
    private let onLimit: @Sendable () -> Void

    /// 初始化频谱计算器与初始电平数组。
    init(onLevels: @escaping @Sendable ([Float]) -> Void, onLimit: @escaping @Sendable () -> Void) throws {
        spectrum = try DictationSpectrum()
        displayedLevels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        self.onLevels = onLevels
        self.onLimit = onLimit
    }

    /// 接收音频采样缓冲，追加采样、触发上限回调并更新电平。
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return }
        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0, samples.count < DictationWire.maximumSamples else { return }
        let floats = data.assumingMemoryBound(to: Float.self)
        let accepted = min(count, DictationWire.maximumSamples - samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: accepted))
        if samples.count == DictationWire.maximumSamples, !reachedLimit {
            reachedLimit = true
            onLimit()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        let levels = spectrum.levels(for: samples[waveformStartIndex...])
        waveformStartIndex = samples.count
        for index in levels.indices {
            let response: Float = levels[index] > displayedLevels[index] ? 0.6 : 0.25
            displayedLevels[index] += (levels[index] - displayedLevels[index]) * response
        }
        onLevels(displayedLevels)
    }

    /// 在代理队列上同步取出已采集的采样。
    func finish() -> [Float] { queue.sync { samples } }
}
