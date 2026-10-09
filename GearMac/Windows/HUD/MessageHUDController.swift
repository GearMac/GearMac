// 文件职责：消息 HUD 控制器，为“操作已生效”这类瞬时反馈提供统一的胶囊提示。
// 分层：Coordinator/UI；@MainActor，基于 HUDPresenter，按设置选择屏幕与界面尺寸。
import AppKit
import SwiftUI

/// 消息胶囊，供所有需要给出瞬时确认反馈的功能共用。
@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    /// 显示一条瞬时消息；tone 决定图标与配色。
    func show(message: String, tone: DialogTone = .success) {
        presenter.show(
            MessageHUDView(message: message, accessory: .tone(tone))
                .environment(\.metrics, metrics)
                .environment(settings))
    }

    /// 一直显示到所报告的工作结束并被新的内容替换，或调用 `dismiss()` 为止。
    func showProgress(message: String, onCancel: (() -> Void)? = nil) {
        presenter.show(
            MessageHUDView(message: message, accessory: .progress, onCancel: onCancel)
                .environment(\.metrics, metrics)
                .environment(settings),
            dwells: false,
            interactive: onCancel != nil)
    }

    /// 隐藏当前消息提示。
    func dismiss() {
        presenter.dismiss()
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }
}
