// 文件职责：把布局条目（比例、锚点、偏移）解析为 frame，并反向还原为条目；纯 AX 空间几何。
// 分层：Model；纯函数，仅依赖 CoreGraphics/Foundation，不 import AppKit/SwiftUI。
import CoreGraphics
import Foundation

/// 把布局条目解析成 frame，再反向还原。纯函数，完全在 AX 空间中进行。
enum WindowLayoutGeometry {
    /// 与 `WindowPlacementEngine.tile` 自身的下限一致：绝不写入零面积 frame。
    static let minimumLength: CGFloat = 1

    /// 条目比例所基于的盒子。gap 为零时它就是纯粹的可见区域。
    static func box(_ screen: WindowPlacementEngine.Screen, gap: CGFloat) -> CGRect {
        WindowPlacementEngine.canvas(
            screen.visibleFrame,
            gap: WindowPlacementEngine.sanitizedGap(gap, in: screen.visibleFrame))
    }

    /// 条目请求的 frame；显示器没有可用可见区域时为 nil。
    static func resolve(
        _ entry: WindowLayoutEntry, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> CGRect? {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else { return nil }

        let size = CGSize(
            width: length(box.width * fraction(entry.widthFraction), in: box.width),
            height: length(box.height * fraction(entry.heightFraction), in: box.height))

        // 先偏移再夹取：微调是用户的意图，夹取只是安全网。
        let placed = entry.anchor.placement.place(size, in: box)
            .offsetBy(dx: nudge(entry.offset.x), dy: nudge(entry.offset.y))
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: box))
    }

    /// `resolve` 复现一个观测到的 frame 所需的信息。
    struct Capture: Equatable, Sendable {
        var widthFraction: CGFloat
        var heightFraction: CGFloat
        var anchor: WindowLayoutAnchor
        var offset: CGPoint
    }

    /// `resolve` 的逆运算：对盒内任意 frame，`resolve(describe(frame)) == frame`。
    static func describe(
        _ frame: CGRect, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> Capture {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else {
            return Capture(widthFraction: 1, heightFraction: 1, anchor: .center, offset: .zero)
        }

        // 先夹取再算比例，使存储的比例总能被 `resolve` 复现。
        let size = CGSize(
            width: min(frame.width, box.width), height: min(frame.height, box.height))
        let horizontal = nearestAxis(
            frame.minX, boxMin: box.minX, boxLength: box.width, length: size.width)
        let vertical = nearestAxis(
            frame.minY, boxMin: box.minY, boxLength: box.height, length: size.height)
        let anchor = WindowLayoutAnchor.named(horizontal: horizontal, vertical: vertical)
        let origin = anchor.placement.place(size, in: box).origin

        // 余量保持精确：奇数空闲空间上的居中锚点会落在半点上，
        // 在此处取整会把窗口移动一个点。`resolve` 对组合后的 frame 取整。
        return Capture(
            widthFraction: size.width / box.width, heightFraction: size.height / box.height,
            anchor: anchor,
            offset: CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y))
    }

    /// 捕获到的窗口在它被发现的显示器上所变成的条目。
    static func entry(
        bundleID: String, display: WindowLayoutDisplay, frame: CGRect,
        on screen: WindowPlacementEngine.Screen
    ) -> WindowLayoutEntry {
        // 不用 gap，这样之后修改 `windowGap` 不会移动每一个已捕获的窗口。
        let capture = describe(frame, on: screen, gap: 0)
        return WindowLayoutEntry(
            bundleID: bundleID, display: display, widthFraction: capture.widthFraction,
            heightFraction: capture.heightFraction, anchor: capture.anchor, offset: capture.offset)
    }

    // MARK: - Primitives

    /// `place` 每个轴只由自身轴决定，因此九选一最近只需 3 + 3。
    private static func nearestAxis(
        _ position: CGFloat, boxMin: CGFloat, boxLength: CGFloat, length: CGFloat
    ) -> WindowPlacementEngine.Anchor.Axis {
        let free = boxLength - length
        // 居中优先，使完全打平时保持“留在居中”而不是钉到边缘。
        let candidates: [(WindowPlacementEngine.Anchor.Axis, CGFloat)] = [
            (.center, boxMin + free / 2), (.min, boxMin), (.max, boxMin + free)
        ]
        var best = candidates[0]
        for candidate in candidates.dropFirst()
        where abs(position - candidate.1) < abs(position - best.1) {
            best = candidate
        }
        return best.0
    }

    private static func fraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let range = WindowLayoutEntry.fractionRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func length(_ value: CGFloat, in available: CGFloat) -> CGFloat {
        min(available, max(minimumLength, value))
    }

    private static func nudge(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
}
