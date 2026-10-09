// 文件职责：支持窗口的生命周期管理，所有展示路径都汇聚到这里，从而保证每次展示只移动一次提醒基准。
// 分层：Coordinator；持有 SupportReminderStore 与窗口控制器，环境注入交由 SupportWindowView。
import AppKit
import SwiftUI

/// 支持窗口的生命周期。所有路径都汇聚到这里，因此每次展示只会移动一次基准时间。
@MainActor
final class SupportCoordinator {
    /// 支持页 URL 的唯一出处；所有入口都链接到这里。
    static let supportPage = URL(string: "https://gearmac.dev/support")!

    private let store: SupportReminderStore
    /// 仅用于环境注入与读取用户活动状态——绝不用于本类型自己持有的状态。
    private unowned let core: AppCore
    private lazy var window = AppWindowController(
        title: String(
            format: core.settings.text(SupportKey.windowTitle), Bundle.main.appDisplayName),
        contentSize: SupportWindowView.initialSize,
        activation: core.activationPolicy)

    init(store: SupportReminderStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    /// 主动展示支持窗口，并记录本次询问时间。
    func showSupport() {
        store.markAsked()
        window.show {
            SupportWindowView(support: self)
                .environment(self.core.settings)
        }
    }

    /// 提醒路径：只有在用户没有其他事情占据注意力时才询问。
    func presentIfDue() {
        guard core.canInterruptUser else { return }
        showSupport()
    }

    /// 打开结账页面并关闭窗口。
    func openCheckout() {
        NSWorkspace.shared.open(Self.supportPage)
        window.close()
    }

    /// 窗口高度取内容实测高度，避免用空白把窗口撑满。
    func fit(height: CGFloat) {
        window.fitContent(width: SupportWindowView.width, height: height)
    }

    /// 若窗口已存在则聚焦它；返回是否命中已有窗口。
    func focusExisting() -> Bool {
        window.focus()
    }
}
