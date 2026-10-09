// 文件职责：管理首次运行引导向导窗口的生命周期，并提供显示、贴合高度、聚焦与完成引导的入口。
// 分层：Coordinator；负责窗口与状态编排，不持有引导流程的业务状态。
import SwiftUI

/// 首次运行向导自己的窗口生命周期。
@MainActor
final class OnboardingCoordinator {
    private let window: AppWindowController
    /// 仅用于环境注入 —— 绝不用来持有本类型自己的状态。
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: core.settings.text(OnboardingKey.windowTitle),
            contentSize: OnboardingView.initialSize,
            activation: core.activationPolicy)
    }

    /// 窗口取当前步骤实测的高度，因此没有步骤会被裁切或被额外撞高。
    func fit(height: CGFloat) {
        window.fitContent(width: OnboardingView.width, height: height)
    }

    func showOnboarding() {
        window.show {
            OnboardingView()
                .environment(self.core)
                .environment(self.core.settings)
                .environment(self.core.hotKeys)
        }
    }

    /// 最后一步：关闭向导并直接进入启动器。
    func finishOnboarding() {
        window.close()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
