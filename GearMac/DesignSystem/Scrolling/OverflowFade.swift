// 文件职责：为有边界的列表提供边缘渐隐，提示还有被遮住的内容，列表滚到该边后渐隐消失。
// 分层：UI（SwiftUI ViewModifier + 遮罩）；渐隐带默认 24pt，仅 popup 等需要时才开启顶边。
import SwiftUI

/// 用于有边界列表的边缘渐隐：标示被隐藏的内容，并在列表到达该边缘后清除。
struct OverflowFadeMask: ViewModifier {
    /// 长度足够短，读起来像一种边缘处理，而不是最后一行被调暗。
    var band: CGFloat = 24
    var includesTop = false

    /// 每侧可见边缘之外被遮住的内容高度；列表贴住该边时为 0。
    @State private var overflow = Overflow()

    private struct Overflow: Equatable {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Overflow.self) { geo in
                Overflow(
                    top: geo.contentOffset.y + geo.contentInsets.top,
                    bottom: geo.contentSize.height + geo.contentInsets.bottom
                        - geo.containerSize.height - geo.contentOffset.y)
            } action: { _, new in
                overflow = Overflow(top: max(0, new.top), bottom: max(0, new.bottom))
            }
            .mask(
                GeometryReader { geo in
                    LinearGradient(
                        stops: stops(height: geo.size.height),
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard includesTop else { return bottomStops(height: height) }
        // popup 的两端使用多个渐变色标，使两端都不会在一行中间生硬截断。
        let topStrength = min(overflow.top / band, 1)
        let bottomStrength = min(overflow.bottom / band, 1)
        guard max(topStrength, bottomStrength) > 0, height > 0 else {
            return [.init(color: .black, location: 0)]
        }
        let extent = min(band / height, 0.5)
        return [
            .init(color: .black.opacity(1 - topStrength), location: 0),
            .init(
                color: .black.opacity(1 - topStrength * 0.75),
                location: extent * 0.35),
            .init(
                color: .black.opacity(1 - topStrength * 0.25),
                location: extent * 0.7),
            .init(color: .black, location: extent),
            .init(color: .black, location: 1 - extent),
            .init(
                color: .black.opacity(1 - bottomStrength * 0.25),
                location: 1 - extent * 0.7),
            .init(
                color: .black.opacity(1 - bottomStrength * 0.75),
                location: 1 - extent * 0.35),
            .init(color: .black.opacity(1 - bottomStrength), location: 1)
        ]
    }

    /// 当没有 popup 启用顶边渐隐时，保持原有 Settings 与 Notes 的曲线不变。
    private func bottomStops(height: CGFloat) -> [Gradient.Stop] {
        let strength = min(overflow.bottom / band, 1)
        guard strength > 0, height > band else { return [.init(color: .black, location: 0)] }
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: 1 - band / height),
            .init(color: .black.opacity(1 - strength), location: 1)
        ]
    }
}

extension View {
    /// 需在 `thinScrollbar` 之前附加。不要用 `edgeDissolve`，那个是针对调色板浮动条调过的。
    func overflowFade(band: CGFloat = 24, includingTop: Bool = false) -> some View {
        modifier(OverflowFadeMask(band: band, includesTop: includingTop))
    }
}
