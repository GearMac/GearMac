// 文件职责：独立摄像头面板的 SwiftUI 内容视图：实时舞台与底部操作区（镜像、切换摄像头、关闭、拍照）。
// 分层：UI（SwiftUI）；状态均由 CameraCoordinator 提供，本视图不直接操作会话。
import SwiftUI

/// 独立摄像头界面：实时舞台、镜像开关，以及拍照直接写入剪贴板。
struct CameraView: View {
    @Environment(AppSettings.self) private var settings
    let coordinator: CameraCoordinator

    var body: some View {
        VStack(spacing: 0) {
            CameraStage(feed: coordinator.feed, mirrored: coordinator.mirrored)
                .frame(
                    width: Theme.Size.cameraStage.width,
                    height: Theme.Size.cameraStage.height)
            footer
        }
        .frame(width: Theme.Size.cameraStage.width)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
    }

    /// 当前会话是否已进入实时预览状态。
    private var isLive: Bool {
        if case .live = coordinator.feed { return true }
        return false
    }

    /// 底部操作区：镜像/切换摄像头（仅实时）与关闭/拍照按钮。
    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isLive {
                CameraButton(
                    title: settings.text(CameraKey.mirror),
                    emphasis: coordinator.mirrored ? .primary : .secondary
                ) {
                    coordinator.mirrored.toggle()
                }
                if coordinator.canSwitchCamera {
                    CameraButton(
                        title: settings.text(CameraKey.switchCamera), emphasis: .secondary) {
                        coordinator.switchCamera()
                    }
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(title: settings.text(CameraKey.close), keyCap: "esc", emphasis: .secondary) {
                coordinator.close()
            }
            if isLive {
                CameraButton(title: settings.text(CameraKey.takePhoto), keyCap: "↵") {
                    coordinator.takePhoto()
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
