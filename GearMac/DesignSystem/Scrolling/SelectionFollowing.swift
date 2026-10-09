// 文件职责：让键盘选中项始终留在浮动条之间的可见带内，维护选中行 frame 与滚动带的对齐。
// 分层：UI（SwiftUI ViewModifier + Preference）；只有被选中的行会上报 frame。
import SwiftUI

extension View {
    /// 为 `scrollFollowsSelection` 上报选中行的 frame；只有被选中的行会进行测量。
    func selectionFrame(_ selected: Bool) -> some View {
        overlay {
            if selected {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SelectionFrameKey.self, value: geometry.frame(in: .scrollView))
                }
            }
        }
    }

    /// 让键盘选中项保持在浮动条之间的可见带内；需要行上已应用 `selectionFrame`。
    func scrollFollowsSelection(
        _ scroll: ScrollIntent, row: String?, atOrigin: Bool, proxy: ScrollViewProxy
    ) -> some View {
        modifier(SelectionFollowing(scroll: scroll, row: row, atOrigin: atOrigin, proxy: proxy))
    }
}

private struct SelectionFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

private struct SelectionFollowing: ViewModifier {
    let scroll: ScrollIntent
    let row: String?
    let atOrigin: Bool
    let proxy: ScrollViewProxy

    @State private var band = Band(insetTop: 0, height: 0)
    @State private var selection: CGRect?
    /// 选中项仍需安置到的位置；安置完成后为 nil，此后由指针接管。
    @State private var target: Target?

    /// 规则读取的几何信息：可见带高度，以及其稳定后会改变静止位置的 inset。
    private struct Band: Equatable {
        var insetTop: CGFloat
        var height: CGFloat
    }

    private enum Target {
        /// 落在带内任意位置，取移动量最小的方案。
        case band
        /// 带的中部，需要行的已测量 frame 才能精确落位。
        case middle
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Band.self) {
                Band(insetTop: $0.contentInsets.top, height: $0.containerSize.height)
            } action: { old, new in
                band = new
                // inset 在挂载后才稳定，且会改变静止偏移，因此需重新执行一次落位。
                if old.insetTop != new.insetTop, scroll.kind != .follow {
                    return begin(scroll.kind)
                }
                align()
            }
            .onPreferenceChange(SelectionFrameKey.self) { frame in
                selection = frame
                align()
            }
            .onChange(of: scroll) { _, scroll in begin(scroll.kind) }
    }

    private func begin(_ kind: ScrollIntent.Kind) {
        switch kind {
        case .top:
            target = nil
            proxy.scrollToOrigin()
        case .follow:
            target = .band
            align()
        case .center:
            target = .middle
            align()
        }
    }

    private func align() {
        guard let target, let row else { return }
        // 回到原点而非行顶部，使第一行所属的分组标题仍留在屏幕上。
        if atOrigin {
            self.target = nil
            return proxy.scrollToOrigin()
        }
        // 懒加载栈已回收该选中行：先按 id 滚回它，再重新检查其 frame。
        guard let selection else {
            return proxy.scrollTo(row, anchor: target == .middle ? .center : nil)
        }
        // 已测量的行可以精确居中，因此不再需要继续监听。
        if target == .middle {
            self.target = nil
            return proxy.scrollTo(row, anchor: .center)
        }
        guard
            let edge = SelectionReveal.edge(
                rowTop: selection.minY, rowBottom: selection.maxY, band: band.height)
        else {
            self.target = nil
            return
        }
        proxy.scrollTo(row, anchor: edge == .top ? .top : .bottom)
    }
}
