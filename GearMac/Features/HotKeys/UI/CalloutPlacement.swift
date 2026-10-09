// 文件职责：计算快捷键 callout 相对输入框的摆放位置与指针指向，属于纯几何计算。
// 分层：UI（纯计算）；不持有视图状态，度量与间距均由调用方注入。
import CoreGraphics

/// callout 的摆放位置及指针落点；纯计算，度量由外部注入。
struct CalloutPlacement: Equatable {
    /// 指针所在的一侧。
    enum CaretEdge: Equatable {
        case top
        case bottom
    }

    /// callout 中心在容器坐标系中的位置，可直接用于 `.position`。
    let center: CGPoint
    let caretEdge: CaretEdge
    /// 指针在 callout 自身 x 轴上的位置，已避开圆角弧段。
    let caretX: CGFloat

    /// 空间足够时放在输入框上方，否则放在下方；两种情况都会被限制在容器内。
    static func resolve(
        field: CGRect, container: CGSize, size: CGSize, gap: CGFloat, inset: CGFloat,
        cornerRadius: CGFloat, caretWidth: CGFloat
    ) -> CalloutPlacement {
        let above = field.minY >= size.height + gap
        let half = size.width / 2

        // `max` 用于防护容器比 callout 还窄、两个边界相互交叉的情况。
        let lower = half + inset
        let centerX = min(max(field.midX, lower), max(container.width - half - inset, lower))
        let centerY =
            above
            ? field.minY - gap - size.height / 2
            : field.maxY + gap + size.height / 2

        // 一旦发生 clamp，指针会随之平移，仍然指向输入框。
        let limit = cornerRadius + caretWidth / 2
        let tip = field.midX - (centerX - half)

        return CalloutPlacement(
            center: CGPoint(x: centerX, y: centerY),
            caretEdge: above ? .bottom : .top,
            caretX: min(max(tip, limit), max(size.width - limit, limit))
        )
    }
}
