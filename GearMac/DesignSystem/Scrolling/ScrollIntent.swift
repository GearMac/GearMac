// 文件职责：定义滚动意图（回到顶部/跟随选中/居中）及其 nonce，并提供滚动原点锚点与恢复入口。
// 分层：UI（SwiftUI 滚动编排）；`nonce` 用于区分连续同类意图，保证 `onChange` 仍会触发。
import SwiftUI

/// 一次滚动请求；重置与跟随需要不同的操作，因此由调用方明确指定类型。
struct ScrollIntent: Equatable {
    enum Kind {
        /// 重置到内容原点；锚点位于 offset 0，因此无需推测位置。
        case top
        /// 键盘导航：最小幅度滚动到可见，已可见的行保持原位。
        case follow
        /// 落在第一行之后的目标：将其居中，使其上方各行仍留在视野内。
        case center
    }

    var kind: Kind
    /// 用于区分前后紧邻的同类型意图，使 `onChange` 仍能触发。
    var nonce = UUID()
}

extension View {
    /// 把内容顶部标记为 `scrollToOrigin` 的目标；需在 padding 之后应用。
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }

}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// 恢复到精确的静止偏移；需要内容上已应用 `scrollOriginAnchor()`。
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }
}
