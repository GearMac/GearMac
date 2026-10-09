// 文件职责：房间预览的 SwiftUI 视图层，绘制桌面模糊背景与待放置窗口卡片（标题栏 + 应用图标）。
// 分层：UI（SwiftUI）；仅负责渲染，通过 RoomPreviewModel 读取状态，不持有业务逻辑。
// 改编自 Rooms (MIT)：https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
import SwiftUI

/// 预览在某台显示器上的部分：模糊变暗的桌面，房间卡片叠在其上。
struct RoomPreviewView: View {
    let model: RoomPreviewModel
    /// 该显示器左上角在 AX 空间中的位置。AX 与 SwiftUI 都向下增长，因此无需翻转。
    let origin: CGPoint
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bounds: CGRect { CGRect(origin: origin, size: size) }

    /// 视图主体：绘制遮罩层与交叉本显示器的卡片，位置按 AX 坐标换算。
    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Colors.roomPreviewDim
            ForEach(model.cards.filter { $0.frame.intersects(bounds) }) { card in
                RoomPreviewCardView(
                    card: card,
                    avoiding: model.avoiding.map { $0.offsetBy(dx: -card.frame.minX, dy: -card.frame.minY) }
                )
                .frame(width: card.frame.width, height: card.frame.height)
                .offset(x: card.frame.minX - origin.x, y: card.frame.minY - origin.y)
                .transition(cardTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(DeskBlur())
        .accessibilityHidden(true)
    }

    /// 卡片出现/消失的过渡动画（开启减弱动画时为无过渡）。
    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: Theme.Duration.roomCardEnter)),
            removal: .opacity.animation(.easeIn(duration: Theme.Duration.roomCardExit)))
    }
}

/// 一个待放置窗口：标题栏显示 App 与窗口名，主体中是 App 图标。
private struct RoomPreviewCardView: View {
    let card: RoomPreviewCard
    /// 面板在该卡片坐标系中的 frame，图标会避开它。
    let avoiding: CGRect?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.roomCard, style: .continuous)
    }

    /// 卡片主体：标题栏 + 分隔线 + 图标叠层，外加圆角、描边与阴影。
    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            Color.clear
        }
        .overlay(alignment: .top) { icon }
        .background(shape.fill(Theme.Colors.roomCardFill))
        .overlay(shape.strokeBorder(Theme.Colors.roomCardStroke, lineWidth: Theme.Size.roomCardStroke))
        .clipShape(shape)
        .shadow(
            color: Theme.Colors.roomCardShadow, radius: Theme.Size.roomCardShadowRadius,
            y: Theme.Size.roomCardShadowOffset)
    }

    /// 模拟窗口标题栏：三个圆点、App 名与窗口标题。
    private var titleBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Theme.Colors.roomCardDot)
                        .frame(width: Theme.Size.roomCardDot, height: Theme.Size.roomCardDot)
                }
            }
            Text(card.appName)
                .font(.headline)
                .foregroundStyle(.primary)
                .layoutPriority(1)
            if !card.title.isEmpty {
                Text("—  \(card.title)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.roomCardTitleBar)
    }

    /// 在卡片主体中居中放置 App 图标；无图标 URL 或高度不足时不绘制。
    @ViewBuilder
    private var icon: some View {
        let body = CGSize(width: card.frame.width, height: card.frame.height - Theme.Size.roomCardTitleBar)
        if let appURL = card.appURL, card.frame.height >= Theme.Size.roomCardIconMinHeight {
            let side = iconSide
            EntryIconView(source: .file(stamp: FileIconStamp.value(for: appURL)), fileURL: appURL)
                .frame(width: side, height: side)
                .offset(y: Theme.Size.roomCardTitleBar + iconCenter(in: body, side: side) - side / 2)
        }
    }

    /// 图标尺寸：卡片足够大时使用大号图标。
    private var iconSide: CGFloat {
        let large = Theme.Size.roomCardLargeIconMinSide
        return card.frame.width > large && card.frame.height > large
            ? Theme.Size.roomCardIconLarge : Theme.Size.roomCardIcon
    }

    /// 主体的中点，或面板未遮挡的较大部分的中点。
    private func iconCenter(in body: CGSize, side: CGFloat) -> CGFloat {
        let top = Theme.Size.roomCardTitleBar
        guard let avoiding,
            avoiding.maxY > top, avoiding.minY < top + body.height,
            avoiding.maxX > (body.width - side) / 2, avoiding.minX < (body.width + side) / 2
        else { return body.height / 2 }
        let above = max(0, avoiding.minY - top)
        let below = max(0, top + body.height - avoiding.maxY)
        return above >= below ? above / 2 : body.height - below / 2
    }
}

/// 覆盖整块显示器的窗口背后模糊，如同调度中心柔化桌面的效果。
private struct DeskBlur: NSViewRepresentable {
    /// 创建全屏毛玻璃效果的 NSVisualEffectView。
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
