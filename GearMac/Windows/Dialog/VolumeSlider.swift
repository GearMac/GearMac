// 文件职责：音量对话框中的滑块控件，联动图标与百分比读数。
// 分层：UI；双向绑定到传入的 `VolumeState`。
import SwiftUI

/// 音量滑块：图标、滑杆与百分比读数三部分。
struct VolumeSlider: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let state: VolumeState

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(systemName: VolumeLevel.symbol(level: state.level))
                .font(metrics.typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.menuIcon)
            Slider(value: level, in: 0...1)
                .labelsHidden()
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel(settings.text(WindowsKey.volumeSliderLabel))
            Text(VolumeLevel.percentage(state.level))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .frame(width: metrics.size.volumeReadout, alignment: .trailing)
        }
    }

    /// 将滑块取值夹紧后写回状态的绑定。
    private var level: Binding<Double> {
        Binding(
            get: { state.level },
            set: { state.level = VolumeLevel.clamped($0) })
    }
}
