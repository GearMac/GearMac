// 文件职责：摄像头画面的 SwiftUI 舞台视图，展示实时视频，或在无权限/无摄像头时显示占位提示。
// 分层：UI（SwiftUI + NSViewRepresentable）；AVCaptureVideoPreviewLayer 仅在本文件内承载。
import AVFoundation
import SwiftUI

/// 所有摄像头界面在底部按钮之上展示的内容：实时视频，或无法显示的原因。
struct CameraStage: View {
    @Environment(AppSettings.self) private var settings
    let feed: CameraSession.Feed
    var mirrored = true

    var body: some View {
        switch feed {
        case .live(let capture):
            CameraFeed(session: capture, mirrored: mirrored)
        case .denied:
            unavailable(settings.text(CameraKey.noAccess))
        case .noCamera:
            unavailable(settings.text(CameraKey.noCamera))
        }
    }

    /// 无法显示摄像头时的占位视图（图标 + 说明）。
    private func unavailable(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "video.slash", size: Theme.Size.dialogIcon)
            Text(message)
                .font(Theme.Typography.rowTrailing)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 唯一承载 `AVCaptureVideoPreviewLayer` 的地方，周边一切均由 GearMac 自己绘制。
private struct CameraFeed: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        let view = NSView()
        // 采用 layer-hosting 而非 layer-backed：在 `wantsLayer` 之前赋值，AppKit 才不会替换它。
        view.layer = preview
        view.wantsLayer = true
        apply(mirrored, to: preview)
        return view
    }

    /// 重新赋值 session 会重建预览连接，使该图层短暂黑一帧。
    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer else { return }
        if preview.session !== session { preview.session = session }
        apply(mirrored, to: preview)
    }

    /// 在支持镜像时按设置应用视频镜像。
    private func apply(_ mirrored: Bool, to preview: AVCaptureVideoPreviewLayer) {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else {
            return
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
