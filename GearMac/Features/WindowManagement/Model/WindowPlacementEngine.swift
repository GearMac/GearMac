// 文件职责：窗口命令的核心几何引擎——解算各命令的目标 frame（平铺、缩放、微调、跨屏、还原）。
// 分层：Model；纯几何，完全在 AX 空间，仅依赖 CoreGraphics/Foundation。
import CoreGraphics
import Foundation

/// 纯几何，完全在 AX 空间中。见 docs/features/window-management.md#coordinate-space。
enum WindowPlacementEngine {
    /// 一块显示器，调用方已转换为 AX 空间。
    struct Screen: Equatable, Sendable {
        /// 在 app 中是 `CGDirectDisplayID`；测试中可用任意稳定值。
        let id: Int
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// 拒绝缩小的窗口在它槽位里的摆放方式；左半屏保持左对齐。
    struct Anchor: Equatable, Sendable {
        /// `min` 是左/上，因为此处 +Y 向下。
        enum Axis: Equatable, Sendable { case min, center, max }

        var horizontal: Axis
        var vertical: Axis

        static let topLeading = Anchor(horizontal: .min, vertical: .min)
        static let centered = Anchor(horizontal: .center, vertical: .center)

        /// 当 app 把自己夹得更大时，按锦点把 `size` 放进 `slot`。
        func place(_ size: CGSize, in slot: CGRect) -> CGRect {
            func origin(
                _ axis: Axis, slotMin: CGFloat, slotLength: CGFloat, length: CGFloat
            )
                -> CGFloat
            {
                switch axis {
                case .min: return slotMin
                case .center: return slotMin + (slotLength - length) / 2
                case .max: return slotMin + slotLength - length
                }
            }
            return CGRect(
                x: origin(
                    horizontal, slotMin: slot.minX, slotLength: slot.width, length: size.width),
                y: origin(vertical, slotMin: slot.minY, slotLength: slot.height, length: size.height),
                width: size.width, height: size.height)
        }
    }

    struct Input: Equatable, Sendable {
        var command: WindowCommand.ID
        var windowFrame: CGRect
        var screens: [Screen]
        var gap: CGFloat
        /// 循环位置，由 `WindowActionMemory` 提供，使几何自身保持无状态。
        var step: Int
        /// 步进的含义：用户为重复按下选择的模式。
        var cycle: WindowCycle
        /// 循环链起始的显示器；为 `nil` 或已被拔掉，则表示宿主显示器。
        var originScreenID: Int?
        /// 仅被 `.restore` 读取。
        var restoreFrame: CGRect?
        /// 上次放置该窗口的平铺命令，使跨显示器移动重新推导而非缩放。
        var lastTileCommand: WindowCommand.ID?

        init(
            command: WindowCommand.ID, windowFrame: CGRect, screens: [Screen], gap: CGFloat = 0,
            step: Int = 0, cycle: WindowCycle = .off, originScreenID: Int? = nil,
            restoreFrame: CGRect? = nil, lastTileCommand: WindowCommand.ID? = nil
        ) {
            self.command = command
            self.windowFrame = windowFrame
            self.screens = screens
            self.gap = gap
            self.step = step
            self.cycle = cycle
            self.originScreenID = originScreenID
            self.restoreFrame = restoreFrame
            self.lastTileCommand = lastTileCommand
        }
    }

    struct Placement: Equatable, Sendable {
        var frame: CGRect
        var screenID: Int
        var anchor: Anchor
        var resizes: Bool
    }

    // MARK: - Tuning

    /// Make Larger / Make Smaller 与四个微调都以屏幕的这一比例步进。
    private static let stepFraction: CGFloat = 0.05
    private static let almostMaximizeFraction: CGFloat = 0.9
    private static let reasonableSizeFraction: CGFloat = 0.6
    /// 硬上限（点数）：5K 显示器的 60% 不算窗口的合理尺寸。
    private static let reasonableSizeMax = CGSize(width: 1025, height: 900)

    // MARK: - Entry point

    /// 目标放置；当移动器完全不应写入时为 `nil`。
    static func placement(for input: Input) -> Placement? {
        guard let command = WindowCommandCatalog.command(id: input.command),
            command.kind == .geometry || command.kind == .restore,
            !input.screens.isEmpty
        else { return nil }

        if command.kind == .restore { return restorePlacement(input) }

        guard let host = screen(containing: input.windowFrame, in: input.screens),
            host.visibleFrame.width > 0, host.visibleFrame.height > 0
        else { return nil }

        let gap = sanitizedGap(input.gap, in: host.visibleFrame)

        switch input.command {
        case .nextDisplay, .previousDisplay:
            return displayPlacement(input, from: host, gap: gap)
        default:
            break
        }

        // 非循环命令的 `cycleLength` 为 1，因此陈旧的步进绝不会渗入。
        let step = wrapped(
            input.step,
            into: cycleLength(for: input.command, screens: input.screens, cycle: input.cycle))

        if let half = Half.of(input.command) {
            return halfPlacement(input, half: half, host: host, step: step)
        }
        if let fractions = tileFractions(input.command) {
            return tilePlacement(fractions, on: host, gap: gap)
        }

        let canvas = canvas(host.visibleFrame, gap: gap)
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let current = input.windowFrame

        switch input.command {
        case .maximize:
            return Placement(
                frame: canvas, screenID: host.id, anchor: .topLeading, resizes: true)

        case .almostMaximize:
            let size = CGSize(
                width: canvas.width * almostMaximizeFraction,
                height: canvas.height * almostMaximizeFraction)
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        // 上限使它与显示器无关；0.6 < 1 无需夹取即落在 canvas 内。
        case .reasonableSize:
            let size = CGSize(
                width: min(canvas.width * reasonableSizeFraction, reasonableSizeMax.width),
                height: min(canvas.height * reasonableSizeFraction, reasonableSizeMax.height))
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        // 两者都保留未触碰的轴，但对其夹取，使跑出显示器的窗口回到屏内。
        case .maximizeHeight:
            let frame = CGRect(
                x: current.minX, y: canvas.minY, width: current.width, height: canvas.height)
            return Placement(
                frame: rounded(clamped(frame, into: canvas)), screenID: host.id,
                anchor: .topLeading, resizes: true)

        case .maximizeWidth:
            let frame = CGRect(
                x: canvas.minX, y: current.minY, width: canvas.width, height: current.height)
            return Placement(
                frame: rounded(clamped(frame, into: canvas)), screenID: host.id,
                anchor: .topLeading, resizes: true)

        case .center:
            let size = CGSize(
                width: min(current.width, canvas.width), height: min(current.height, canvas.height))
            return Placement(
                frame: rounded(Anchor.centered.place(size, in: canvas)), screenID: host.id,
                anchor: .centered, resizes: true)

        case .makeLarger, .makeSmaller:
            return Placement(
                frame: resized(current, in: canvas, larger: input.command == .makeLarger),
                screenID: host.id, anchor: .centered, resizes: true)

        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return Placement(
                frame: nudged(current, in: canvas, command: input.command), screenID: host.id,
                anchor: .topLeading, resizes: false)

        default:
            return nil
        }
    }

    // MARK: - Screens

    /// 窗口所在的显示器：重叠面积最大者胜出，否则取包含其中心的那个。
    static func screen(containing frame: CGRect, in screens: [Screen]) -> Screen? {
        guard !screens.isEmpty else { return nil }
        var best: (screen: Screen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        if let best, best.area > 0 { return best.screen }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.frame.contains(centre) } ?? screens.first
    }

    /// 先从左到右，再从上到下：无论 `NSScreen.screens` 如何排序都稳定。
    static func ordered(_ screens: [Screen]) -> [Screen] {
        screens.sorted {
            $0.frame.minX != $1.frame.minX
                ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    private static func displayPlacement(
        _ input: Input, from host: Screen, gap: CGFloat
    )
        -> Placement?
    {
        let ordered = ordered(input.screens)
        // 单显示器时两个命令都安静地空操作，而不是无意义地重新放置。
        guard ordered.count > 1, let index = ordered.firstIndex(where: { $0.id == host.id })
        else { return nil }
        let offset = input.command == .nextDisplay ? 1 : -1
        let destination = ordered[(index + offset + ordered.count) % ordered.count]
        let frame = moved(
            input.windowFrame, from: host, to: destination, gap: gap,
            lastTile: input.lastTileCommand)
        return Placement(
            frame: frame, screenID: destination.id, anchor: .centered, resizes: true)
    }

    private static func moved(
        _ frame: CGRect, from: Screen, to: Screen, gap: CGFloat, lastTile: WindowCommand.ID?
    ) -> CGRect {
        // 精确优于按比例：未被触碰的平铺是重新推导，而不是被缩放。
        if let lastTile, let fractions = tileFractions(lastTile) {
            return tile(
                to.visibleFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
                y1: fractions.y1, gap: sanitizedGap(gap, in: to.visibleFrame))
        }
        let source = from.visibleFrame
        let target = to.visibleFrame
        guard source.width > 0, source.height > 0 else { return frame }
        // 相对于 `visibleFrame`，使贴着 Dock 的窗口落地后依然贴着。
        let relativeX = (frame.minX - source.minX) / source.width
        let relativeY = (frame.minY - source.minY) / source.height
        let scaled = CGRect(
            x: target.minX + relativeX * target.width,
            y: target.minY + relativeY * target.height,
            width: min(target.width, frame.width / source.width * target.width),
            height: min(target.height, frame.height / source.height * target.height))
        return rounded(clamped(scaled, into: target))
    }

    // MARK: - Restore

    private static func restorePlacement(_ input: Input) -> Placement? {
        guard let restoreFrame = input.restoreFrame,
            let host = screen(containing: restoreFrame, in: input.screens)
        else { return nil }
        let overlap = host.visibleFrame.intersection(restoreFrame)
        // 遗落在所有显示器之外的还原点会以居中方式回来，而不是无法抵达。
        let stranded = overlap.isNull || overlap.width < 40 || overlap.height < 40
        let frame =
            stranded
            ? rounded(
                clamped(
                    Anchor.centered.place(restoreFrame.size, in: host.visibleFrame),
                    into: host.visibleFrame))
            : restoreFrame
        return Placement(frame: frame, screenID: host.id, anchor: .centered, resizes: true)
    }

    // MARK: - Tiles

    private struct Fractions {
        var x0: CGFloat
        var x1: CGFloat
        var y0: CGFloat
        var y1: CGFloat
        var anchor: Anchor
    }

    private static let oneThird: CGFloat = 1.0 / 3.0
    private static let twoThirds: CGFloat = 2.0 / 3.0

    /// 四个半屏之一：它切分的轴，以及它贴住该轴的哪条边。
    private struct Half {
        enum Axis { case horizontal, vertical }
        enum Edge { case leading, trailing }

        var axis: Axis
        var edge: Edge

        static func of(_ command: WindowCommand.ID) -> Half? {
            switch command {
            case .leftHalf: Half(axis: .horizontal, edge: .leading)
            case .rightHalf: Half(axis: .horizontal, edge: .trailing)
            case .topHalf: Half(axis: .vertical, edge: .leading)
            case .bottomHalf: Half(axis: .vertical, edge: .trailing)
            default: nil
            }
        }

        /// 沿该轴覆盖屏幕 `fraction` 比例、贴住边缘的边界。
        func fractions(_ fraction: CGFloat) -> Fractions {
            let leads = edge == .leading
            let span: (CGFloat, CGFloat) = leads ? (0, fraction) : (1 - fraction, 1)
            let along: Anchor.Axis = leads ? .min : .max
            switch axis {
            case .horizontal:
                return Fractions(
                    x0: span.0, x1: span.1, y0: 0, y1: 1,
                    anchor: Anchor(horizontal: along, vertical: .min))
            case .vertical:
                return Fractions(
                    x0: 0, x1: 1, y0: span.0, y1: span.1,
                    anchor: Anchor(horizontal: .min, vertical: along))
            }
        }
    }

    /// 开启尺寸循环时半屏步进的各个尺寸。
    private static let sizeCycle: [CGFloat] = [0.5, oneThird, twoThirds]

    /// 循环链回绕前的按下次数；为 1 表示该命令完全不循环。
    static func cycleLength(
        for command: WindowCommand.ID, screens: [Screen], cycle: WindowCycle
    ) -> Int {
        guard WindowCommandCatalog.command(id: command)?.cyclesOnRepeat == true else { return 1 }
        switch cycle {
        case .off: return 1
        case .sizes: return sizeCycle.count
        // 单显示器时显示器循环是空操作，而不是原地左右互换。
        case .displays: return screens.count > 1 ? screens.count * 2 : 1
        }
    }

    /// 本次按下的半屏槽位：它在宿主显示器上的那条边，或沿显示器带走动一格的结果。
    private static func halfPlacement(
        _ input: Input, half: Half, host: Screen, step: Int
    ) -> Placement {
        guard input.cycle == .displays else {
            return tilePlacement(half.fractions(sizeCycle[step]), on: host, gap: input.gap)
        }
        let strip = ordered(input.screens)
        // 链到中途时窗口已在另一块显示器上，从它开始计数会多走。
        guard strip.count > 1,
            let originIndex = strip.firstIndex(where: { $0.id == input.originScreenID })
                ?? strip.firstIndex(where: { $0.id == host.id })
        else {
            return tilePlacement(half.fractions(0.5), on: host, gap: input.gap)
        }
        // Left 与 Top 向后走，使一个快捷键能沿同一方向扫过整个桌面。
        let leads = half.edge == .leading
        let slot = wrapped(
            originIndex * 2 + (leads ? 0 : 1) + (leads ? -step : step), into: strip.count * 2)
        let edge: Half.Edge = slot.isMultiple(of: 2) ? .leading : .trailing
        return tilePlacement(
            Half(axis: half.axis, edge: edge).fractions(0.5), on: strip[slot / 2], gap: input.gap)
    }

    private static func tilePlacement(
        _ fractions: Fractions, on screen: Screen, gap: CGFloat
    ) -> Placement {
        let frame = tile(
            screen.visibleFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
            y1: fractions.y1, gap: sanitizedGap(gap, in: screen.visibleFrame))
        return Placement(
            frame: frame, screenID: screen.id, anchor: fractions.anchor, resizes: true)
    }

    /// 某平铺命令在其基础位置的比例边界；不是平铺命令时为 `nil`。
    private static func tileFractions(_ command: WindowCommand.ID) -> Fractions? {
        if let half = Half.of(command) { return half.fractions(0.5) }
        switch command {
        case .topLeftQuarter:
            return Fractions(x0: 0, x1: 0.5, y0: 0, y1: 0.5, anchor: .topLeading)
        case .topRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0, y1: 0.5, anchor: Anchor(horizontal: .max, vertical: .min))
        case .bottomLeftQuarter:
            return Fractions(
                x0: 0, x1: 0.5, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .min, vertical: .max))
        case .bottomRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .max, vertical: .max))

        case .firstThreeFourths:
            return Fractions(x0: 0, x1: 0.75, y0: 0, y1: 1, anchor: .topLeading)
        case .lastThreeFourths:
            return Fractions(
                x0: 0.25, x1: 1, y0: 0, y1: 1, anchor: Anchor(horizontal: .max, vertical: .min))

        case .firstThird:
            return Fractions(x0: 0, x1: oneThird, y0: 0, y1: 1, anchor: .topLeading)
        case .centerThird:
            return Fractions(
                x0: oneThird, x1: twoThirds, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))
        case .lastThird:
            return Fractions(
                x0: twoThirds, x1: 1, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .max, vertical: .min))
        case .firstTwoThirds:
            return Fractions(x0: 0, x1: twoThirds, y0: 0, y1: 1, anchor: .topLeading)
        case .lastTwoThirds:
            return Fractions(
                x0: oneThird, x1: 1, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .max, vertical: .min))

        // 占屏幕面积的一半，使它与 Center Third 读作同族。
        case .centerHalf:
            return Fractions(
                x0: 0.25, x1: 0.75, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))
        case .centerTwoThirds:
            return Fractions(
                x0: oneThird / 2, x1: 1 - oneThird / 2, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))

        default:
            return nil
        }
    }

    /// 该命令是否落在那套比例网格上，跨显示器移动时可据此重新推导。
    static func isTileCommand(_ command: WindowCommand.ID) -> Bool {
        tileFractions(command) != nil
    }

    /// 由 `visible` 的比例边界生成的平铺。见 docs/features/window-management.md#geometry。
    static func tile(
        _ visible: CGRect, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, gap: CGFloat
    ) -> CGRect {
        let left = visible.minX + x0 * visible.width + (x0 == 0 ? gap : gap / 2)
        let right = visible.minX + x1 * visible.width - (x1 == 1 ? gap : gap / 2)
        let top = visible.minY + y0 * visible.height + (y0 == 0 ? gap : gap / 2)
        let bottom = visible.minY + y1 * visible.height - (y1 == 1 ? gap : gap / 2)
        return rounded(
            CGRect(
                x: left, y: top, width: max(1, right - left), height: max(1, bottom - top)))
    }

    /// 自由悬浮命令使用的盒子：四边都是完整 gap，而不是网格的半 gap。
    static func canvas(_ visible: CGRect, gap: CGFloat) -> CGRect {
        rounded(visible.insetBy(dx: gap, dy: gap))
    }

    // MARK: - Sizing

    /// 绝不让反复缩小把窗口塌缩成零。
    private static func minimumSize(in canvas: CGRect) -> CGSize {
        CGSize(
            width: min(canvas.width, max(200, canvas.width * 0.15)),
            height: min(canvas.height, max(150, canvas.height * 0.15)))
    }

    /// 取偶数，使每条边移动整数个点，两个命令保持可精确互逆。
    private static func evenStep(_ dimension: CGFloat) -> CGFloat {
        max(2, (dimension * stepFraction / 2).rounded() * 2)
    }

    /// 围绕中心，按屏幕比例缩放。见 docs/features/window-management.md#geometry
    private static func resized(_ frame: CGRect, in canvas: CGRect, larger: Bool) -> CGRect {
        let direction: CGFloat = larger ? 1 : -1
        let floorSize = minimumSize(in: canvas)
        let width = min(
            canvas.width, max(floorSize.width, frame.width + direction * evenStep(canvas.width)))
        let height = min(
            canvas.height, max(floorSize.height, frame.height + direction * evenStep(canvas.height)))
        let centred = CGRect(
            x: frame.minX - (width - frame.width) / 2, y: frame.minY - (height - frame.height) / 2,
            width: width, height: height)
        return rounded(clamped(centred, into: canvas))
    }

    private static func nudged(
        _ frame: CGRect, in canvas: CGRect, command: WindowCommand.ID
    )
        -> CGRect
    {
        let dx = (canvas.width * stepFraction).rounded()
        let dy = (canvas.height * stepFraction).rounded()
        var moved = frame
        switch command {
        case .moveLeft: moved.origin.x -= dx
        case .moveRight: moved.origin.x += dx
        case .moveUp: moved.origin.y -= dy
        case .moveDown: moved.origin.y += dy
        default: break
        }
        return rounded(clamped(moved, into: canvas))
    }

    // MARK: - Primitives

    /// 对四条边分别取整，使共享边界的两个平铺对边界取整结果一致。
    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded()
        let maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// 在不改变尺寸的前提下把 `frame` 保持在 `box` 内；过大的窗口钉住其前缘。
    static func clamped(_ frame: CGRect, into box: CGRect) -> CGRect {
        let x = min(max(frame.minX, box.minX), max(box.minX, box.maxX - frame.width))
        let y = min(max(frame.minY, box.minY), max(box.minY, box.maxY - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// 设置中提供的 gap 范围（点数）；文件也被限制在同一范围内。
    static let gapRange = 0...64

    /// 比屏幕还宽的 gap 会产生零宽平铺，因此在任何计算前先设上限。
    static func sanitizedGap(_ gap: CGFloat, in visible: CGRect) -> CGFloat {
        guard gap.isFinite, gap > 0, visible.width > 0, visible.height > 0 else { return 0 }
        return min(gap, min(visible.width, visible.height) / 10)
    }

    /// 回绕进 `0..<length`，使负值或超限的步进都不会逃出循环。
    private static func wrapped(_ value: Int, into length: Int) -> Int {
        ((value % length) + length) % length
    }
}
