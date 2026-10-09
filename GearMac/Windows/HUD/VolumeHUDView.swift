// 文件职责：音量 HUD 的方框视图，展示喇叭图标、音量条与读数。
// 分层：UI；采用命令面板的表面配方而非玻璃效果。
import SwiftUI

/// 音量方框：图标、进度条与数字，采用命令面板的表面配方而非玻璃效果。
struct VolumeHUDView: View {
    let state: VolumeState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolImage(
                name: VolumeLevel.symbol(level: state.level, muted: state.muted),
                size: Theme.Size.dialogIcon
            )
            .foregroundStyle(Color.primary)
            HStack(spacing: Theme.Spacing.md) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.controlSurface)
                        Capsule()
                            .fill(Theme.Colors.textPrimary.opacity(state.muted ? 0.35 : 0.85))
                            .frame(width: geometry.size.width * fill)
                    }
                }
                .frame(height: Theme.Size.volumeTrackHeight)
                // 静音时直接显示文字：进度条已为空，再显示数字会自相矛盾。
                Text(state.muted ? settings.text(WindowsKey.hudMuted) : VolumeLevel.percentage(state.level))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
        }
        // 上下与左右内边距不对称：在 200pt 的方框上，左右内边距的代价远高于 420pt 的对话框。
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
        // 重复触发时进度条平滑滑向新值，而不是直接跳变。
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.level)
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.muted)
    }

    /// 进度条填充比例；静音时为 0。
    private var fill: CGFloat {
        state.muted ? 0 : VolumeLevel.clamped(state.level)
    }
}
