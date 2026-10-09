// 文件职责：摄像头采集会话的封装：权限申请、会话配置与启停、设备切换、拍照并输出 PNG 数据。
// 分层：Service（@MainActor）；AVCaptureSession 的阻塞调用一律通过 CaptureBox 放到主线程之外执行。
import AVFoundation
import AppKit

/// `AVCaptureSession` 不是 `Sendable`，因此阻塞调用经由一个 box 放到主线程之外执行。
@MainActor
final class CameraSession {
    /// 会话的用途；拍照需要更大的 preset 与额外的 output。
    enum Purpose {
        case preview
        case capture
    }

    /// 在面板打开前就确定，避免在用户眼前替换掉舞台画面。
    enum Feed {
        case live(AVCaptureSession)
        case denied
        case noCamera
    }

    /// 当前 Mac 上可用的全部摄像头，顺序与 `switchToNextDevice` 循环切换的顺序一致。
    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    private let purpose: Purpose
    private var capture: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var device: AVCaptureDevice?
    private var pendingPhoto: PhotoCapture?

    /// 以指定用途创建会话。
    init(_ purpose: Purpose = .preview) {
        self.purpose = purpose
    }

    /// 这里刻意阻塞在 `startRunning`：目的是让首帧就是视频画面，而不是黑屏。
    func start() async -> Feed {
        var access = Permissions.cameraAccess()
        if access == .notDetermined {
            _ = await Permissions.requestCameraAccess()
            access = Permissions.cameraAccess()
        }
        guard access == .granted else { return .denied }
        guard let capture = capture ?? configure() else { return .noCamera }
        self.capture = capture
        guard !capture.isRunning else { return .live(capture) }
        let box = CaptureBox(session: capture)
        await Task.detached { box.session.startRunning() }.value
        return .live(capture)
    }

    /// 停止会话并释放输出；摄像头指示灯随面板一起熄灭。
    func stop() {
        guard let capture else { return }
        // 复用会话时若自身没有 output，新的预览图层将拿不到任何帧。
        self.capture = nil
        photoOutput = nil
        guard capture.isRunning else { return }
        // 摄像头指示灯必须随面板一起熄灭，因此这绝不留给反初始化处理。
        let box = CaptureBox(session: capture)
        Task.detached { box.session.stopRunning() }
    }

    /// 是否存在多个可选摄像头。
    var hasMultipleDevices: Bool { Self.devices.count > 1 }

    /// 只替换输入：会话持续运行，因此舞台画面不会变黑。
    func switchToNextDevice() async {
        let devices = Self.devices
        guard devices.count > 1, let capture, let device else { return }
        // 若当前设备不在 discovery 列表中，则回绕到第一个而不是保持不变。
        let index = devices.firstIndex(of: device) ?? devices.count - 1
        let next = devices[(index + 1) % devices.count]
        guard let input = try? AVCaptureDeviceInput(device: next) else { return }
        let box = CaptureBox(session: capture, input: input)
        await Task.detached {
            box.session.beginConfiguration()
            for existing in box.session.inputs { box.session.removeInput(existing) }
            if let input = box.input, box.session.canAddInput(input) {
                box.session.addInput(input)
            }
            box.session.commitConfiguration()
        }.value
        self.device = next
    }

    /// 编码为 PNG 而非相机原生格式，使剪贴板历史能把它识别为图片。
    func capturePhoto(mirrored: Bool) async -> Data? {
        guard let photoOutput, capture?.isRunning == true else { return nil }
        if let connection = photoOutput.connection(with: .video),
            connection.isVideoMirroringSupported
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        let capture = PhotoCapture()
        pendingPhoto = capture
        defer { pendingPhoto = nil }
        guard let encoded = await capture.take(from: photoOutput) else { return nil }
        return await Task.detached {
            NSBitmapImageRep(data: encoded)?.representation(using: .png, properties: [:])
        }.value
    }

    /// 重新打开时优先使用上次切换到的摄像头，除非它已被拔下。
    private func configure() -> AVCaptureSession? {
        let preferred = device?.isConnected == true ? device : AVCaptureDevice.default(for: .video)
        guard let device = preferred, let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        let capture = AVCaptureSession()
        capture.sessionPreset = purpose == .capture ? .photo : .medium
        guard capture.canAddInput(input) else { return nil }
        capture.addInput(input)
        self.device = device
        guard purpose == .capture else { return capture }
        let output = AVCapturePhotoOutput()
        guard capture.canAddOutput(output) else { return capture }
        capture.addOutput(output)
        photoOutput = output
        return capture
    }
}

/// 仅限本文件使用：所有在主线程之外访问采集对象的调用都经由它。
private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
    var input: AVCaptureDeviceInput?
}

/// 使用 unchecked：continuation 在主线程写入，并在 AVFoundation 队列上只读取一次。
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data?, Never>?

    /// 触发一次拍照并等待结果数据。
    @MainActor
    func take(from output: AVCapturePhotoOutput) async -> Data? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    /// 拍照完成回调：把数据或错误结果返回给等待中的 continuation。
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        continuation?.resume(returning: error == nil ? photo.fileDataRepresentation() : nil)
        continuation = nil
    }
}
