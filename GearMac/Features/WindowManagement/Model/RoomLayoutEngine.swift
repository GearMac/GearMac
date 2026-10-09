// 文件职责：为房间布局计算 frame——Focus/Stack/Columns/Grid 排布、Auto 选择与比例分配。
// 分层：Model；纯几何，仅依赖 CoreGraphics，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// 房间布局产出的每一个 frame，均在 AX 空间。见 docs/features/window-rooms.md#layouts。
enum RoomLayoutEngine {
    /// 低于此值，平铺窗口就不再好用。
    static let comfortable = CGSize(width: 480, height: 360)
    /// 整齐布局给窗口的最小值，使未知的最小尺寸绝不会被挤成零。
    static let usable = CGSize(width: 320, height: 240)
    static let peek: CGFloat = 32

    /// 窗口平铺所在的盒子，以及每种布局使用的同一个 gap，均只清洗一次。
    struct Area {
        let canvas: CGRect
        let gap: CGFloat

        init(visible: CGRect, gap: CGFloat) {
            self.gap = WindowPlacementEngine.sanitizedGap(gap, in: visible)
            canvas = WindowPlacementEngine.canvas(visible, gap: self.gap)
        }
    }

    /// `minimums` 为每个窗口持有一个尺寸，或为空；不会要求任何 app 低于它自身的下限。
    static func frames(
        count: Int, kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize] = []
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let area = Area(visible: visible, gap: gap)
        let minimums = padded(minimums, to: count)
        switch kind {
        // 房间自身的记录负责解算 `.custom` 与 `.saved`；在这里它们等同于 Auto。
        case .auto, .custom, .saved:
            let tidy = autoKind(count: count, in: visible, gap: gap, minimums: minimums)
            return frames(count: count, kind: tidy, in: visible, gap: gap, minimums: minimums)
        case .stack:
            return stack(count, in: area, minimums: minimums).map {
                WindowPlacementEngine.clamped($0, into: area.canvas)
            }
        case .focus, .columns, .grid:
            let candidates = arrangements(count, kind: kind, in: area, minimums: minimums)
            // 重叠优于出屏：溢出最少的候选会被拉回屏内。
            let best =
                candidates.first { works($0, in: area.canvas) }
                ?? candidates.min { overflow($0, in: area.canvas) < overflow($1, in: area.canvas) }
                ?? []
            return best.map { WindowPlacementEngine.clamped($0, into: area.canvas) }
        }
    }

    /// `kind` 是否不重叠地放下每个窗口。Stack 是故意重叠的，因此它永远算放得下。
    static func fits(
        count: Int, kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize] = []
    ) -> Bool {
        guard count > 0 else { return false }
        switch kind {
        case .auto, .stack, .custom, .saved:
            return true
        case .focus, .columns, .grid:
            let area = Area(visible: visible, gap: gap)
            return arrangements(
                count, kind: kind, in: area, minimums: padded(minimums, to: count)
            ).contains { works($0, in: area.canvas) }
        }
    }

    /// 此处 Auto 的含义：第一个让每个侧边窗口都足够舒适的整齐布局。
    static func autoKind(
        count: Int, in visible: CGRect, gap: CGFloat, minimums: [CGSize] = []
    ) -> RoomLayoutKind {
        guard count > 1 else { return .focus }
        let area = Area(visible: visible, gap: gap)
        let minimums = padded(minimums, to: count)
        let order: [RoomLayoutKind] = count <= 4 ? [.focus, .columns, .grid] : [.grid, .columns, .focus]
        for kind in order {
            // 在任何夹取之前判定，且 Columns 意味着一行：换行才是 Grid 的职责。
            let options = arrangements(count, kind: kind, in: area, minimums: minimums).filter {
                kind != .columns || Set($0.map(\.minY)).count == 1
            }
            guard let fit = options.first(where: { works($0, in: area.canvas) }) else { continue }
            let roomy = fit.dropFirst().allSatisfy {
                $0.width >= comfortable.width - 1 && $0.height >= comfortable.height - 1
            }
            if roomy { return kind }
        }
        return .stack
    }

    /// 在盒内且互不重叠：一个可以直接使用的布局。
    static func isClean(_ rects: [CGRect], in box: CGRect) -> Bool {
        guard overflow(rects, in: box) < 1 else { return false }
        for i in rects.indices {
            for j in rects.indices where i < j {
                let shared = rects[i].intersection(rects[j])
                if !shared.isNull, shared.width > 1, shared.height > 1 { return false }
            }
        }
        return true
    }

    /// 按 `weights` 把 `total` 拆成整数点，绝不低于 `minimums`（即使因此溢出）。
    static func distribute(
        _ total: CGFloat, gap: CGFloat, minimums: [CGFloat], weights: [CGFloat]
    ) -> [CGFloat] {
        let count = minimums.count
        guard count > 0 else { return [] }
        let available = total - gap * CGFloat(count - 1)
        var fixed = Array(repeating: false, count: count)
        var sizes = Array(repeating: CGFloat(0), count: count)
        while true {
            let flexibleWeight = (0..<count).filter { !fixed[$0] }.map { weights[$0] }.reduce(0, +)
            let fixedSpace = (0..<count).filter { fixed[$0] }.map { sizes[$0] }.reduce(0, +)
            guard flexibleWeight > 0 else { break }
            var changed = false
            for index in 0..<count where !fixed[index] {
                sizes[index] = max(0, available - fixedSpace) * weights[index] / flexibleWeight
            }
            for index in 0..<count where !fixed[index] && sizes[index] < minimums[index] {
                sizes[index] = minimums[index]
                fixed[index] = true
                changed = true
            }
            if !changed { break }
        }
        // 单独对每块取整会让一行宽出一个点，与其最后一个窗口重叠。
        var rounded = sizes.map { $0.rounded(.down) }
        var spare = Int((available - rounded.reduce(0, +)).rounded(.down))
        let byRemainder = sizes.indices.sorted {
            sizes[$0] - rounded[$0] > sizes[$1] - rounded[$1]
        }
        for index in byRemainder where spare > 0 {
            rounded[index] += 1
            spare -= 1
        }
        return rounded
    }

    /// 在 `rect` 内按 `columns` 列排成多行；最后一行不足时拉伸到整宽。
    static func grid(
        _ count: Int, columns: Int, in rect: CGRect, gap: CGFloat, minimums: [CGSize]
    ) -> [CGRect] {
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let rowItems = (0..<rows).map { row in
            Array(row * columns..<min(count, (row + 1) * columns))
        }
        let heights = distribute(
            rect.height, gap: gap,
            minimums: rowItems.map { $0.map { minimums[$0].height }.max() ?? 0 },
            weights: Array(repeating: 1, count: rows))
        var frames: [CGRect] = []
        var y = rect.minY
        for (row, items) in rowItems.enumerated() {
            let widths = distribute(
                rect.width, gap: gap, minimums: items.map { minimums[$0].width },
                weights: Array(repeating: 1, count: items.count))
            var x = rect.minX
            for width in widths {
                frames.append(
                    CGRect(x: x.rounded(), y: y.rounded(), width: width, height: heights[row]))
                x += width + gap
            }
            y += heights[row] + gap
        }
        return frames
    }

    // MARK: - Arrangements

    private static let heroShares: [CGFloat] = [0.6, 0.5]
    private static let stackShares: [CGFloat] = [0.6, 0.4]

    private struct FocusOption {
        var rects: [CGRect]
        var heroWidth: CGFloat
        var isPreferred: Bool
        var isReordered: Bool
        var rank: Int
    }

    /// 按偏好排序的候选，每个都在任何夹取之前由 `works` 判定。
    private static func arrangements(
        _ count: Int, kind: RoomLayoutKind, in area: Area, minimums given: [CGSize]
    ) -> [[CGRect]] {
        let minimums = given.map {
            CGSize(width: max($0.width, usable.width), height: max($0.height, usable.height))
        }
        switch kind {
        case .focus:
            return focusArrangements(count, in: area, minimums: minimums)
        case .columns:
            let preferred = min(count, 4)
            return ([preferred] + (1..<preferred).reversed()).map {
                grid(count, columns: $0, in: area.canvas, gap: area.gap, minimums: minimums)
            }
        default:
            let preferred = Int(Double(count).squareRoot().rounded(.up))
            return [preferred, preferred + 1, max(1, preferred - 1)].filter { $0 <= count }.map {
                grid(count, columns: $0, in: area.canvas, gap: area.gap, minimums: minimums)
            }
        }
    }

    /// 主窗口在左，其余在右列；最宽的窗口可能被移到最后一行。
    private static func focusArrangements(
        _ count: Int, in area: Area, minimums: [CGSize]
    ) -> [[CGRect]] {
        let canvas = area.canvas
        let gap = area.gap
        guard count > 1 else { return [[canvas]] }
        let side = Array(1..<count)
        let preferredColumns = side.count > 3 ? 2 : 1
        var orders = [side]
        if let widest = side.max(by: { minimums[$0].width < minimums[$1].width }),
            widest != side.last, minimums[widest].width > 0
        {
            orders.append(side.filter { $0 != widest } + [widest])
        }
        var options: [FocusOption] = []
        for share in heroShares {
            for columns in 1...min(3, side.count) {
                for (orderIndex, order) in orders.enumerated() {
                    let sideWidth = rowMinimumWidth(
                        order, columns: columns, minimums: minimums, gap: gap)
                    let widths = distribute(
                        canvas.width, gap: gap, minimums: [minimums[0].width, sideWidth],
                        weights: [share, 1 - share])
                    let hero = CGRect(
                        x: canvas.minX, y: canvas.minY, width: widths[0], height: canvas.height)
                    let column = CGRect(
                        x: hero.maxX + gap, y: canvas.minY, width: widths[1], height: canvas.height)
                    let cells = grid(
                        order.count, columns: columns, in: column, gap: gap,
                        minimums: order.map { minimums[$0] })
                    var rects = Array(repeating: CGRect.zero, count: count)
                    rects[0] = hero
                    for (cell, window) in order.enumerated() { rects[window] = cells[cell] }
                    options.append(
                        FocusOption(
                            rects: rects, heroWidth: widths[0],
                            isPreferred: columns == preferredColumns && share == heroShares[0]
                                && orderIndex == 0,
                            isReordered: orderIndex > 0, rank: options.count))
                }
            }
        }
        // 常见布局优先；其后是任何能让主窗口保持最大的方案。
        return options.sorted { lhs, rhs in
            if lhs.isPreferred != rhs.isPreferred { return lhs.isPreferred }
            if abs(lhs.heroWidth - rhs.heroWidth) > 1 { return lhs.heroWidth > rhs.heroWidth }
            if lhs.isReordered != rhs.isReordered { return !lhs.isReordered }
            return lhs.rank < rhs.rank
        }.map(\.rects)
    }

    /// 侧边窗口相互重叠的 Focus：第二个在最前，每个标题栏都可见。
    private static func stack(_ count: Int, in area: Area, minimums: [CGSize]) -> [CGRect] {
        let canvas = area.canvas
        guard count > 1 else { return [canvas] }
        let side = Array(minimums.dropFirst())
        let sideMinimum = CGSize(
            width: side.map(\.width).max() ?? 0, height: side.map(\.height).max() ?? 0)
        let widths = distribute(
            canvas.width, gap: area.gap, minimums: [minimums[0].width, sideMinimum.width],
            weights: stackShares)
        let hero = CGRect(x: canvas.minX, y: canvas.minY, width: widths[0], height: canvas.height)
        let behind = CGFloat(side.count - 1)
        let peek = min(
            Self.peek, max(0, ((canvas.height - sideMinimum.height) / max(1, behind)).rounded(.down)))
        let height = canvas.height - peek * behind
        let x = hero.maxX + area.gap
        return [hero]
            + side.indices.map { index in
                CGRect(
                    x: x, y: canvas.minY + peek * (behind - CGFloat(index)), width: widths[1],
                    height: height)
            }
    }

    private static func rowMinimumWidth(
        _ order: [Int], columns: Int, minimums: [CGSize], gap: CGFloat
    ) -> CGFloat {
        stride(from: 0, to: order.count, by: columns).map { start in
            let row = order[start..<min(order.count, start + columns)]
            return row.map { minimums[$0].width }.reduce(0, +) + gap * CGFloat(row.count - 1)
        }.max() ?? 0
    }

    private static func works(_ rects: [CGRect], in box: CGRect) -> Bool {
        overflow(rects, in: box) < 1
            && rects.allSatisfy {
                $0.width >= usable.width - 1 && $0.height >= usable.height - 1
            }
    }

    private static func overflow(_ rects: [CGRect], in box: CGRect) -> CGFloat {
        rects.reduce(0) { sum, rect in
            sum + max(0, box.minX - rect.minX) + max(0, rect.maxX - box.maxX)
                + max(0, box.minY - rect.minY) + max(0, rect.maxY - box.maxY)
        }
    }

    private static func padded(_ minimums: [CGSize], to count: Int) -> [CGSize] {
        minimums.count == count ? minimums : Array(repeating: .zero, count: count)
    }
}
