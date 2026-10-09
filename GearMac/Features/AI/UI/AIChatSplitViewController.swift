// 文件职责：用 NSSplitViewController 把 AI Chat 窗口分成侧边栏与详情两栏，并持久化分隔位置。
// 分层：UI；只负责分栏布局与尺寸约束，不持有任何会话状态，也不 import 业务 Store。
import AppKit
import SwiftUI

/// 与 Settings 相同的真实分栏视图，使侧边栏能像原生控件一样折叠与调整宽度。
final class AIChatSplitViewController: NSSplitViewController {
    private static let autosaveName = "AIChatSplitView"

    /// 以侧边栏与详情两个 SwiftUI 视图搭建分栏，设定宽度上下限并恢复上次的分隔位置。
    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar))
        sidebarItem.minimumThickness = Theme.Size.aiChatSidebarMinimum
        sidebarItem.maximumThickness = Theme.Size.aiChatSidebarMaximum
        sidebarItem.canCollapse = true

        let detailItem = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        detailItem.minimumThickness = Theme.Size.aiChatDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.autosaveName = Self.autosaveName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
