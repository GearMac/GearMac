// 文件职责：加入会议前的摄像头预览视图，上方是视频画面，下方是会议标题/倒计时与「取消 / 加入」按钮。
// 分层：UI（SwiftUI）；不持有摄像头会话，仅展示传入的 feed 并回调 onJoin / onCancel。
import SwiftUI

/// 加入前预览：把摄像头画面叠在即将打开的会议信息之上。
struct CameraPreviewView: View {
    @Environment(AppSettings.self) private var settings
    let meeting: MeetingEvent
    let now: Date
    let feed: CameraSession.Feed
    let onJoin: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CameraStage(feed: feed)
                .frame(
                    width: Theme.Size.cameraPreview.width,
                    height: Theme.Size.cameraPreview.height)
            footer
        }
        .frame(width: Theme.Size.cameraPreview.width)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
    }

    /// 底部操作区：会议标题、倒计时以及取消/加入按钮。
    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(meeting.localizedTitle(settings.language))
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(
                    UpcomingWindow.countdown(
                        to: meeting.start, now: now, language: settings.language))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(
                title: settings.text(CameraKey.cancel), keyCap: "esc", emphasis: .secondary,
                onActivate: onCancel)
            CameraButton(
                title: settings.text(CameraKey.join), keyCap: "↵", onActivate: onJoin)
        }
        .padding(Theme.Spacing.xl)
    }
}
