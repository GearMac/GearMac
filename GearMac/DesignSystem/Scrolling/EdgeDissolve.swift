// 文件职责：为与调色板浮动条重叠的列表提供随滚动变化的边缘渐隐遮罩。参见 `docs/ui.md`。
// 分层：UI（SwiftUI ViewModifier + 遮罩）；渐隐带高度随 metrics 缩放，渐隐强度随被遮住的内容量变化。
import SwiftUI

/// 用于与调色板浮动条重叠的列表的滚动驱动边缘遮罩。参见 `docs/ui.md`。
struct EdgeDissolveMask: ViewModifier {
    /// 渐隐带长度：浮动条高度加上其探入列表的部分——顶部 32px，底部 28px。
    private var topFade: CGFloat {
        metrics.size.headerHeight + metrics.size.headerPadding + metrics.scaled(32)
    }
    private var bottomFade: CGFloat { metrics.size.bottomBarHeight + metrics.scaled(28) }
    private static let topMinAlpha: CGFloat = 0.15
    private static let bottomMinAlpha: CGFloat = 0.25
    @Environment(\.metrics) private var metrics

    /// 每侧边缘外被遮住的内容高度；列表贴住该边时为 0。
    @State private var topDistance: CGFloat = 0
    @State private var bottomDistance: CGFloat = 0
    @State private var canScroll = false

    private struct ScrollState: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var canScroll: Bool
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollState.self) { geo in
                let visible =
                    geo.containerSize.height - geo.contentInsets.top
                    - geo.contentInsets.bottom
                return ScrollState(
                    top: geo.contentOffset.y + geo.contentInsets.top,
                    bottom: geo.contentSize.height + geo.contentInsets.bottom
                        - geo.containerSize.height - geo.contentOffset.y,
                    canScroll: geo.contentSize.height > visible
                )
            } action: { _, new in
                topDistance = max(0, new.top)
                bottomDistance = max(0, new.bottom)
                canScroll = new.canScroll
            }
            .mask(
                // 必须覆盖滚动视图的*完整* frame——否则浮动条的 safe-area inset 会把渐变向内偏移，使重叠区域被裁成黑色。
                GeometryReader { geo in
                    LinearGradient(
                        stops: stops(height: geo.size.height),
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard canScroll, height > 0 else { return [.init(color: .black, location: 0)] }
        // 中点 alpha 随一整条渐隐带的内容滚过，从 1 平滑过渡到下限值。
        let topAlpha = 1 - (1 - Self.topMinAlpha) * min(topDistance / topFade, 1)
        let bottomAlpha = 1 - (1 - Self.bottomMinAlpha) * min(bottomDistance / bottomFade, 1)
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(topAlpha), location: topFade / 2 / height),
            .init(color: .black, location: topFade / height),
            .init(color: .black, location: 1 - bottomFade / height),
            .init(color: .black.opacity(bottomAlpha), location: 1 - bottomFade / 2 / height),
            .init(color: .black.opacity(0), location: 1)
        ]
    }
}

extension View {
    /// 附加到与调色板浮动条重叠的 `ScrollView`（要放在 `thinScrollbar` 之前，使滚动条覆盖层不被遮罩）。
    func edgeDissolve() -> some View {
        modifier(EdgeDissolveMask())
    }
}
