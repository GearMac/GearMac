// 文件职责：CalloutPlacement 的独立测试 harness，校验弹出提示的定位、翻转、水平夹取与尖角跟随。
// 分层：测试 harness；引入真实 CalloutPlacement 与 Theme.swift，令牌被重新调整时此处会失败。
import CoreGraphics
import Foundation

/// 用真实 `Theme` 驱动 `CalloutPlacement`，因此令牌被重新调整时会在这里失败。
@main
@MainActor
struct CalloutPlacementTests {
    static var failures = 0
    static var passes = 0

    // 与 `ShortcutRecorderPopoverHost` 实际传入的参数完全一致。
    static let size = Theme.Size.shortcutPopover
    static let gap = Theme.Spacing.sm
    static let inset = Theme.Spacing.xs
    static let cornerRadius = Theme.Radius.menuPanel
    static let caretWidth = Theme.Size.calloutCaretWidth

    /// 面板 `xxl` 内边距 + 行 `xl` 内边距，再加上字段宽度的一半。
    static let fieldInsetFromPaneEdge =
        Theme.Spacing.xxl + Theme.Spacing.xl + Theme.Size.shortcutRecorder / 2
    /// 尖角距边缘的最近距离：再近就会伸出圆角弧线之外。
    static var caretLimit: CGFloat { cornerRadius + caretWidth / 2 }

    /// 用当前的容器尺寸与令牌，把字段位置解析为提示的摆放位置。
    static func resolve(field: CGRect, container: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: container, size: size, gap: gap, inset: inset,
            cornerRadius: cornerRadius, caretWidth: caretWidth)
    }

    /// 布尔断言辅助：条件成立则通过数加一。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 浮点断言辅助：两者相差小于 0.001 即视为相等。
    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    /// 测试入口：依次运行全部用例，打印通过/失败数，失败时以退出码 1 结束。
    static func main() {
        centredOnARealRow()
        flipping()
        horizontalClamping()
        caretTracking()
        degenerateContainers()
        rowGrammar()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - 实际发布使用的情形

    /// 仅当提示宽度足够窄、能放在字段旁边时才成立。
    static func centredOnARealRow() {
        for paneWidth in [Theme.Size.settingsSidebar + 320, 720, 1100] as [CGFloat] {
            let field = CGRect(
                x: paneWidth - fieldInsetFromPaneEdge - Theme.Size.shortcutRecorder / 2,
                y: 400, width: Theme.Size.shortcutRecorder, height: 24)
            let placement = resolve(field: field, container: CGSize(width: paneWidth, height: 800))

            expect(
                placement.center.x, field.midX,
                "pane \(Int(paneWidth)): the callout centres on the recorder")
            expect(
                placement.caretX, size.width / 2,
                "pane \(Int(paneWidth)): the caret sits dead centre")
        }

        expect(
            size.width / 2 + inset <= fieldInsetFromPaneEdge,
            "the callout is narrow enough to centre on a trailing-edge recorder — widen it and the caret skews"
        )
    }

    // MARK: - 上方还是下方

    /// 上方空间充足时提示在字段上方，贴近面板顶部时翻转到下方。
    static func flipping() {
        let container = CGSize(width: 600, height: 800)
        let roomy = CGRect(x: 400, y: 400, width: 80, height: 24)
        let above = resolve(field: roomy, container: container)
        expect(above.caretEdge == .bottom, "a field with room above gets the callout above it")
        expect(
            above.center.y, roomy.minY - gap - size.height / 2,
            "the callout's bottom edge sits one gap above the field")

        // 提示的下边缘必须让开字段，绝不能与其重叠。
        expect(
            above.center.y + size.height / 2 <= roomy.minY,
            "the callout never overlaps the field it points at")

        let tight = CGRect(x: 400, y: 40, width: 80, height: 24)
        let below = resolve(field: tight, container: container)
        expect(below.caretEdge == .top, "a field near the pane's top flips the callout below it")
        expect(
            below.center.y, tight.maxY + gap + size.height / 2,
            "the flipped callout's top edge sits one gap below the field")

        // 刚好够高也算够：边界情况不应翻转。
        let exact = CGRect(x: 400, y: size.height + gap, width: 80, height: 24)
        expect(
            resolve(field: exact, container: container).caretEdge == .bottom,
            "a field with exactly enough room above does not flip")
        let onePointShort = CGRect(x: 400, y: size.height + gap - 1, width: 80, height: 24)
        expect(
            resolve(field: onePointShort, container: container).caretEdge == .top,
            "one point short of the room it needs does flip")
    }

    // MARK: - 保持在面板内

    /// 靠近面板边缘的字段会把提示水平夹回面板内部并保持内边距。
    static func horizontalClamping() {
        let container = CGSize(width: 600, height: 800)

        let centered = resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: container)
        expect(centered.center.x, 300, "a field mid-pane centres the callout on it")

        // 录制器位于设置行的尾部边缘，这是实际会发生的情况。
        let trailing = resolve(
            field: CGRect(x: 500, y: 400, width: 80, height: 24), container: container)
        expect(
            trailing.center.x, container.width - size.width / 2 - inset,
            "a trailing-edge field slides the callout back inside the pane")
        expect(
            trailing.center.x + size.width / 2 <= container.width - inset + 0.001,
            "the clamped callout keeps its inset from the trailing edge")

        let leading = resolve(
            field: CGRect(x: 0, y: 400, width: 80, height: 24), container: container)
        expect(leading.center.x, size.width / 2 + inset, "a leading-edge field clamps the same way")
        expect(
            leading.center.x - size.width / 2 >= inset - 0.001,
            "the clamped callout keeps its inset from the leading edge")
    }

    // MARK: - 指针落点

    /// 尖角（指针）始终指向字段中心，并在主体被夹取后向边缘偏移。
    static func caretTracking() {
        let container = CGSize(width: 600, height: 800)

        let centered = resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: container)
        expect(centered.caretX, size.width / 2, "an unclamped callout points from its middle")

        // 一旦主体被夹取，尖角会向边缘移动以保持指向。
        let trailing = CGRect(x: 500, y: 400, width: 80, height: 24)
        let clamped = resolve(field: trailing, container: container)
        expect(
            clamped.center.x - size.width / 2 + clamped.caretX, trailing.midX,
            "the pointer still lands on the field's centre after the body is clamped")
        expect(clamped.caretX > size.width / 2, "and it does that by sitting past the middle")

        // 字段远离提示时，尖角最多只被拖到圆角弧线允许的位置。
        let extreme = resolve(
            field: CGRect(x: 596, y: 400, width: 80, height: 24), container: container)
        expect(
            extreme.caretX <= size.width - caretLimit + 0.001,
            "the pointer stops clear of the trailing corner arc")
        let farLeading = resolve(
            field: CGRect(x: -200, y: 400, width: 80, height: 24), container: container)
        expect(
            farLeading.caretX >= caretLimit - 0.001,
            "the pointer stops clear of the leading corner arc")
    }

    // MARK: - 共享行语法
    // 放在此处是因为它是唯一编译 `Theme.swift` 的 harness：只有一个 `rowIcon` 槽位。

    /// 校验卸载复选框能放进共享的行首图标槽位。
    static func rowGrammar() {
        expect(
            Theme.Size.checkbox <= Theme.Size.rowIcon,
            "the uninstall checkbox fits inside the shared leading slot")
        expect(Theme.Size.checkbox > 0, "and is a real size")
    }

    // MARK: - 比提示还小的容器

    /// 容器小于提示时的退化情况：必须仍能解出有限值而不会崩溃。
    static func degenerateContainers() {
        // 比提示更窄的面板没有合法的内边距区间，此时必须由 `max` 兜底。
        let narrow = resolve(
            field: CGRect(x: 10, y: 400, width: 80, height: 24),
            container: CGSize(width: 200, height: 800))
        expect(narrow.center.x, size.width / 2 + inset, "a too-narrow pane still resolves finitely")
        expect(narrow.caretX.isFinite, "and its pointer stays a real number")

        let short = resolve(
            field: CGRect(x: 100, y: 4, width: 80, height: 24),
            container: CGSize(width: 600, height: 60))
        expect(short.caretEdge == .top, "a pane with no room above flips below even when cramped")
        expect(short.center.y.isFinite, "and still resolves finitely")
    }
}
