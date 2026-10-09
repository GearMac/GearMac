// 文件职责：验证命令面板的默认摆放、位置还原、吸附与菜单面板锚点等几何规则（PalettePlacement / MenuPanelCorner）。
// 分层：测试 harness；仅依赖 CoreGraphics/Foundation，使用真实 Theme 常量以便改版时暴露回归。
import CoreGraphics
import Foundation

/// 使用真实的 `Theme` 常量，避免重新调参后把面板还原到屏幕外。
@main
@MainActor
struct PalettePlacementTests {
    static var failures = 0
    static var passes = 0

    // 与 `PaletteWindowController` 传入的值完全一致，尺寸取用户选定的 Interface Size。
    static let metrics = InterfaceMetrics.standard
    static let width = metrics.size.panelWidth
    static let graspable = CGSize(width: width, height: metrics.size.compactHeight)
    static let minimumVisible = Theme.Size.paletteMinimumVisible
    static let snap = Theme.Size.paletteSnapDistance
    static let topFraction = Theme.Size.paletteTopMarginFraction

    /// 一台 1440p 显示器，已扣除顶部菜单栏占用。
    static let laptop = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    /// 堆叠在右侧的第二台显示器，与 `NSScreen.screens` 上报的样子一致。
    static let external = CGRect(x: 2560, y: 0, width: 1920, height: 1055)

    /// 断言条件成立，否则计为失败并打印失败信息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 断言两个 CGFloat 在容差范围内相等。
    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    static func home(_ screen: CGRect) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen, width: width, topMarginFraction: topFraction)
    }

    static func restored(_ stored: CGPoint, on screen: CGRect) -> CGPoint? {
        PalettePlacement.restored(
            stored, graspable: graspable, visibleFrame: screen, minimumVisible: minimumVisible)
    }

    static func main() {
        theDefaultPlacement()
        clipboardBarDock()
        restoringOnItsOwnDisplay()
        offsetsFollowTheirDisplay()
        restoringPartlyOffscreen()
        snapping()
        expandedDetentFollowsGeometry()
        menuPanelAnchors()
        tokenGrammar()
        everyInterfaceSize()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - 未经改动的默认摆放

    /// 核心不变量：默认锤点水平居中，顶边按比例下移，且展开后仍能放进屏幕。
    static func theDefaultPlacement() {
        let anchor = home(laptop)
        expect(anchor.x, laptop.midX - width / 2, "the panel centres horizontally")
        expect(
            anchor.y, laptop.maxY - laptop.height * topFraction,
            "its top edge sits the margin fraction below the top of the visible area")
        expect(anchor.y < laptop.maxY, "the top edge is inside the screen, not on its edge")

        // 面板从锤点向下生长，因此完全展开的列表也必须能放进屏幕。
        expect(
            anchor.y - metrics.size.panelHeight > laptop.minY,
            "an expanded palette clears the bottom of the screen it opened on")

        // 原点有偏移的屏幕不得把面板推出它自己的范围。
        let offset = home(external)
        expect(offset.x, external.midX - width / 2, "a non-origin display centres the same way")
        expect(
            offset.y, external.maxY - external.height * topFraction,
            "and its top edge is measured from its own maxY")
    }

    // MARK: - 剪贴板横条的底部停靠

    /// 核心验收：横条占满可见区整宽、底边贴底，绝不悬在屏幕中间。
    static func clipboardBarDock() {
        let height = metrics.size.clipboardBarHeight

        let docked = PalettePlacement.bottomBarFrame(in: laptop, height: height)
        expect(docked.minX, laptop.minX, "the clipboard bar spans from the display's left edge")
        expect(
            docked.maxX, laptop.maxX,
            "the clipboard bar spans to the display's right edge")
        expect(
            docked.minY, laptop.minY,
            "the clipboard bar hugs the bottom edge of the visible area")
        expect(docked.height, height, "the docked bar keeps its own height")
        expect(
            docked.maxY < laptop.maxY - laptop.height / 2,
            "the docked bar sits in the bottom half, never the middle of the screen")

        // 带原点偏移的第二台显示器同样整宽贴底。
        let dockedExternal = PalettePlacement.bottomBarFrame(in: external, height: height)
        expect(dockedExternal.minX, external.minX, "a non-origin display spans from its own left")
        expect(dockedExternal.maxX, external.maxX, "and to its own right edge")
        expect(dockedExternal.minY, external.minY, "and hugs its own bottom edge")
    }

    // MARK: - 还原已保存的位置

    /// 保存的位置只能在同一块显示器上原样还原，不得溢到相邻屏幕。
    static func restoringOnItsOwnDisplay() {
        let onExternal = CGPoint(x: 2700, y: 900)
        expect(
            restored(onExternal, on: external) == onExternal,
            "a drop comes back verbatim on the display it was made on")
        expect(
            restored(onExternal, on: laptop) == nil,
            "and is never read onto the neighbouring display the palette is summoned on")

        // 兜底位置必须确实可达，而不只是与保存值不同。
        expect(
            restored(home(laptop), on: laptop) != nil,
            "the default placement is always restorable on its own screen")
    }

    /// 位置相对于显示器存储，因此重排或改分辨率后仍能保持拖放位置。
    /// 以显示器为参照记录偏移，因此重排/缩放显示器后仍能找回拖放点。
    static func offsetsFollowTheirDisplay() {
        let dropped = CGPoint(x: external.minX + 400, y: external.maxY - 260)
        let offset = PalettePlacement.offset(of: dropped, on: external)
        expect(offset.x, 400, "the offset runs rightward from the display's own left edge")
        expect(offset.y, 260, "and downward from its top edge")
        expect(
            PalettePlacement.anchor(for: offset, on: external) == dropped,
            "reading it back on the unchanged display returns the point that was dropped")

        // 同一台显示器，在“显示器”设置里被移到另一侧。
        let rearranged = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let moved = PalettePlacement.anchor(for: offset, on: rearranged)
        expect(moved.x, rearranged.minX + 400, "a rearranged display keeps the drop on itself")
        expect(moved.y, rearranged.maxY - 260, "wherever the global origin left it")
        expect(restored(moved, on: rearranged) != nil, "and the bar is grabbable there")

        // 分辨率变更会从底部收短屏幕，因此顶部偏移量仍然成立。
        let scaled = CGRect(x: 2560, y: 0, width: 1440, height: 775)
        let resized = PalettePlacement.anchor(for: offset, on: scaled)
        expect(resized.y, scaled.maxY - 260, "a rescaled display keeps the distance from the top")
        expect(restored(resized, on: scaled) != nil, "and still shows enough of the bar to grab")

        let edge = PalettePlacement.offset(
            of: CGPoint(x: external.maxX - 10, y: external.maxY - 260), on: external)
        expect(
            restored(PalettePlacement.anchor(for: edge, on: scaled), on: scaled) == nil,
            "an offset past the edge of a shrunken display falls home instead")
    }

    /// 部分滑出屏幕的位置：只要还剩最小可抓取量就仍可还原。
    static func restoringPartlyOffscreen() {
        // 有意向右滑出屏幕：只要还露出可抓取的一小条，就仍然可以还原。
        let sliver = CGPoint(x: laptop.maxX - minimumVisible, y: 900)
        expect(
            restored(sliver, on: laptop) != nil,
            "exactly the minimum sliver of the compact bar is still grabbable")
        let tooFar = CGPoint(x: laptop.maxX - minimumVisible + 1, y: 900)
        expect(
            restored(tooFar, on: laptop) == nil,
            "one point less than that is not, and falls back to the default")

        // 从顶部滑出的情况，最先消失的是整条抓取区域。
        let peeking = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible)
        expect(
            restored(peeking, on: laptop) != nil,
            "a bar hanging off the top edge is grabbable while the minimum still shows")
        let gone = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible + 1)
        expect(
            restored(gone, on: laptop) == nil,
            "pushed one point further up it is dropped")
    }

    // MARK: - 不可见的中线

    /// 验证中线与高度卡位的吸附、已锁定的保持行为以及速度门槛。
    static func snapping() {
        for screen in [laptop, external] {
            let origin = home(screen)
            let expandedY = screen.midY + metrics.size.panelHeight / 2
            func snapped(
                _ point: CGPoint, previous: PalettePlacement.Snap? = nil, speed: CGFloat = 0
            ) -> PalettePlacement.Snap {
                PalettePlacement.snapped(
                    point, home: origin, visibleFrame: screen,
                    expandedHeight: metrics.size.panelHeight, within: snap,
                    previous: previous, speed: speed)
            }
            let freeY = (origin.y + expandedY) / 2
            let centered = PalettePlacement.Snap(
                anchor: CGPoint(x: origin.x, y: freeY), centeredX: true, height: nil)
            expect(
                snapped(CGPoint(x: origin.x + snap, y: freeY)).anchor.x, origin.x,
                "the centre line catches at the right boundary")
            expect(
                snapped(CGPoint(x: origin.x - snap, y: freeY)).anchor.x, origin.x,
                "the centre line catches at the left boundary")
            expect(
                !snapped(CGPoint(x: origin.x + snap + 1, y: freeY)).centeredX,
                "an unlatched drag does not catch beyond the entry range")
            expect(
                snapped(CGPoint(x: origin.x + snap * 2, y: origin.y + 1), previous: centered)
                    .height == .home,
                "a latched drag holds the centre line and its height detent twice as far")
            expect(
                !snapped(
                    CGPoint(x: origin.x + snap * 2 + 1, y: origin.y + 1),
                    previous: centered
                ).centeredX,
                "a latched drag releases beyond twice the entry range")
            expect(
                snapped(CGPoint(x: origin.x + snap + 1, y: origin.y + 1)).anchor
                    == CGPoint(x: origin.x + snap + 1, y: origin.y + 1),
                "the home detent does not extend horizontally")
            expect(
                snapped(CGPoint(x: origin.x + snap + 1, y: expandedY + 1)).height == nil,
                "the expanded detent does not extend horizontally")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + snap)).height == .home,
                "the home detent catches on the centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: expandedY - snap)).anchor.y,
                expandedY, "the expanded detent centres the full-height palette")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: freeY)).anchor.y, freeY,
                "height remains free between the two detents")
            let fast = PalettePlacement.maxSnapEntrySpeedPointsPerSecond + 1
            expect(
                !snapped(CGPoint(x: origin.x + 1, y: freeY), speed: fast).centeredX,
                "a fast pass does not enter the centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: freeY), speed: fast - 1).centeredX,
                "a deliberate pass can still enter the centre line")
            expect(
                snapped(CGPoint(x: origin.x + snap * 2, y: freeY), previous: centered, speed: fast)
                    .centeredX,
                "speed does not release an already held centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + 1), previous: centered, speed: fast)
                    .height == nil,
                "a fast pass on the centre line does not enter a height detent")
            let held = PalettePlacement.Snap(anchor: origin, centeredX: true, height: .home)
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + 1), previous: held, speed: fast)
                    .height == .home,
                "speed does not release an already held detent")
        }
    }

    /// 展开卡位必须随显示器几何与 Interface Size 重新居中。
    static func expandedDetentFollowsGeometry() {
        let shifted = CGRect(x: 300, y: 50, width: 1800, height: 1000)
        for size in InterfaceSize.allCases {
            let panelHeight = size.metrics.size.panelHeight
            let top = PalettePlacement.expandedCenterY(
                in: shifted, expandedHeight: panelHeight)
            expect(
                top - panelHeight / 2, shifted.midY,
                "the expanded detent stays centred after display or Interface Size changes")
        }
    }

    // MARK: - 菜单面板

    /// 验证三种菜单面板锚点及其缩放时固定的边。
    static func menuPanelAnchors() {
        let parent = CGRect(x: 100, y: 200, width: 750, height: 475)
        let content = CGSize(width: 276, height: 240)
        let inset = metrics.spacing.md
        let headerExtent = metrics.size.headerPadding + metrics.size.headerHeight

        let leading = MenuPanelCorner.bottomLeading.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(leading.minX, parent.minX + inset, "the left menu follows the footer's leading edge")
        expect(leading.minY, parent.minY + inset, "the left menu follows the footer's bottom edge")

        let trailing = MenuPanelCorner.bottomTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(trailing.maxX, parent.maxX - inset, "the action menu follows the trailing button")
        expect(trailing.minY, parent.minY + inset, "the action menu follows the footer's bottom edge")

        let header = MenuPanelCorner.belowHeaderTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(header.maxX, parent.maxX - inset * 2, "a header menu follows its trailing control")
        expect(header.maxY, parent.maxY - headerExtent, "a header menu opens below the field")

        // 停靠横条贴近屏幕底边，菜单从面板上边缘向上悬挂。
        let aboveLeading = MenuPanelCorner.aboveLeading.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(aboveLeading.minX, parent.minX + inset, "the above menu follows the leading edge")
        expect(aboveLeading.minY, parent.maxY + inset, "the above menu clears the panel's top")

        let aboveTrailing = MenuPanelCorner.aboveTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(aboveTrailing.maxX, parent.maxX - inset, "the above menu follows the trailing edge")
        expect(aboveTrailing.minY, parent.maxY + inset, "and clears the panel's top too")

        // 锚定目标矩形（如被右键的卡片）正上方，水平居中且夹在面板内。
        let card = CGRect(x: 400, y: 240, width: 150, height: 140)
        let aboveCard = MenuPanelCorner.aboveRect(card).frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(aboveCard.minY, card.maxY + inset, "a card menu clears the card's top")
        expect(aboveCard.midX, card.midX, "a card menu centres on its card")
        let edgeCard = CGRect(x: parent.minX - 40, y: 240, width: 150, height: 140)
        let clamped = MenuPanelCorner.aboveRect(edgeCard).frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(clamped.minX, parent.minX + inset, "an edge card clamps the menu inside the panel")

        let scale = Theme.MenuMotion.maximumScale
        let leadingCanvas = MenuPanelCorner.bottomLeading.scaledFrame(leading, by: scale)
        let trailingCanvas = MenuPanelCorner.bottomTrailing.scaledFrame(trailing, by: scale)
        let headerCanvas = MenuPanelCorner.belowHeaderTrailing.scaledFrame(header, by: scale)
        let aboveCanvas = MenuPanelCorner.aboveTrailing.scaledFrame(aboveTrailing, by: scale)
        expect(leadingCanvas.minX, leading.minX, "left expansion keeps its leading edge fixed")
        expect(leadingCanvas.minY, leading.minY, "left expansion keeps its bottom edge fixed")
        expect(trailingCanvas.maxX, trailing.maxX, "right expansion keeps its trailing edge fixed")
        expect(trailingCanvas.minY, trailing.minY, "right expansion keeps its bottom edge fixed")
        expect(headerCanvas.maxX, header.maxX, "header expansion keeps its trailing edge fixed")
        expect(headerCanvas.maxY, header.maxY, "header expansion keeps its top edge fixed")
        expect(aboveCanvas.maxX, aboveTrailing.maxX, "above expansion keeps its trailing edge fixed")
        expect(aboveCanvas.minY, aboveTrailing.minY, "above expansion keeps its bottom edge fixed")
    }

    // MARK: - 这些规则依赖的常量约束

    /// 断言这些几何规则依赖的常量仍处于合理范围。
    static func tokenGrammar() {
        // 一旦超过面板自身高度，任何已保存位置都将不再可还原。
        expect(
            minimumVisible <= graspable.height,
            "the minimum visible sliver fits inside the compact bar")
        expect(
            snap * 2 < width,
            "the snap zone is narrower than the panel, so it can't swallow every drop")
        expect(topFraction > 0 && topFraction < 1, "the top margin is a real fraction of the screen")
    }

    // MARK: - 各种 Interface Size 下的一致规则

    /// 最大的面板也必须能落在 GearMac 支持的最小显示器上。
    static let smallest = CGRect(x: 0, y: 0, width: 1440, height: 875)

    /// 对每个 Interface Size 重跑摆放与边缘还原规则。
    static func everyInterfaceSize() {
        for size in InterfaceSize.allCases {
            let metrics = size.metrics
            let width = metrics.size.panelWidth
            let label = "at \(size.rawValue)"

            for screen in [laptop, external, smallest] {
                let anchor = PalettePlacement.defaultAnchor(
                    in: screen, width: width, topMarginFraction: topFraction)
                expect(anchor.x, screen.midX - width / 2, "the panel stays centred \(label)")
                expect(
                    anchor.y - metrics.size.panelHeight > screen.minY,
                    "an expanded palette clears the bottom of a \(Int(screen.width))pt display \(label)"
                )
            }

            // 更宽的面板需要在屏上露出更多自身，因此靠边的保存位置可能失效。
            let graspable = CGSize(width: width, height: metrics.size.compactHeight)
            let sliver = CGPoint(x: laptop.maxX - minimumVisible, y: 900)
            expect(
                PalettePlacement.restored(
                    sliver, graspable: graspable, visibleFrame: laptop,
                    minimumVisible: minimumVisible) != nil,
                "the minimum sliver is still grabbable \(label)")
            expect(
                PalettePlacement.restored(
                    CGPoint(x: laptop.maxX, y: 900), graspable: graspable,
                    visibleFrame: laptop, minimumVisible: minimumVisible) == nil,
                "a bar dragged fully past the right edge is dropped \(label)")

            // 停靠横条在每个尺寸下也必须整宽贴底地落在最小的显示器上。
            let docked = PalettePlacement.bottomBarFrame(
                in: smallest, height: metrics.size.clipboardBarHeight)
            expect(
                docked.minX == smallest.minX && docked.maxX == smallest.maxX,
                "the docked clipboard bar spans the full width of a 1440pt display \(label)")
            expect(
                docked.minY == smallest.minY,
                "the docked clipboard bar hugs the bottom \(label)")
            expect(
                docked.maxY < smallest.midY,
                "the docked clipboard bar stays below the middle \(label)")
        }
    }
}
