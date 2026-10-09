// 文件职责：音量 HUD 控制器，显示当前音量或静音状态。
// 分层：Coordinator/UI；@MainActor，复用同一个 VolumeState，使重复触发只做数值动画。
import AppKit
import SwiftUI

/// 音量读数；用方框而非胶囊，因为电平需要同时展示进度条与数字。
@MainActor
final class VolumeHUDController {
    private let settings: AppSettings
    private let presenter = HUDPresenter(
        anchor: .heightFraction(bottomFraction), dwell: Theme.Duration.volumeHUD,
        screen: { .underCursor })
    private let state = VolumeState(level: 0)

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 更新并显示音量读数；静音时以文字代替数字。
    func show(level: Float32, muted: Bool) {
        // 视图观察 `state`，因此重复触发只做进度条动画，而非重播整段呈现。
        let showing = presenter.isShowing
        state.level = VolumeLevel.clamped(Double(level))
        state.muted = muted
        if showing {
            presenter.extend()
        } else {
            let metrics = settings.interfaceSize.metrics
            presenter.show(
                VolumeHUDView(state: state)
                    .environment(\.metrics, metrics)
                    .environment(settings),
                size: CGSize(width: metrics.size.hudWidth, height: metrics.size.hudHeight))
        }
    }

    /// 比胶囊更靠上；方框更高，这样两者到屏幕边缘的视觉间距才一致。
    private static let bottomFraction: CGFloat = 0.12
}
