// 文件职责：测试调色板悬停高亮的武装（arming）状态机：何时解除、何时重新武装以及已点亮行的清除。
// 分层：测试 harness；直接操作 PaletteState，不涉及真实鼠标事件。

import CoreGraphics
import Foundation

/// 调色板绝不点亮指针未真正选择的行，指针漂移也不例外。
@main
@MainActor
struct HoverArmingTests {
    static var failures = 0
    static var passes = 0

    /// 下面多数用例中指针的静止位置；具体取值不影响断言。
    static let rest = CGPoint(x: 400, y: 300)

    /// 断言辅助：条件不成立时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 指针已停在某一行上时显示的调色板：未武装，并以该位置为锚点。
    static func shown() -> PaletteState {
        let state = PaletteState()
        state.disarmHoverHighlight(pointerAt: rest)
        return state
    }

    /// 把指针移动得足够远以计数，这是下面所有已武装用例的武装方式。
    static func armed() -> PaletteState {
        let state = shown()
        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        return state
    }

    /// harness 入口：依次运行全部用例，打印统计并在失败时以退出码 1 结束。
    static func main() {
        openingDisarmed()
        deliberateMovementArms()
        scrollingDisarms()
        driftDoesNotRearm()
        theDisarmTokenClearsLitRows()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Opening

    /// 验证刚显示的调色板处于未武装状态，切换模式会再次解除武装。
    static func openingDisarmed() {
        let state = shown()
        expect(!state.hoverHighlightArmed, "a palette just shown is disarmed")
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "a mouse-moved event that has not moved arms nothing")
        let state2 = armed()
        state2.prepare(mode: .clipboard)
        expect(!state2.hoverHighlightArmed, "switching mode disarms the highlight again")
    }

    // MARK: - Arming

    /// 验证指针移动按距离累积判定，且位移锚点保持不变。
    static func deliberateMovementArms() {
        expect(armed().hoverHighlightArmed, "a pointer moved across the panel arms the highlight")

        let diagonal = shown()
        diagonal.notePointerMoved(to: CGPoint(x: rest.x + 3, y: rest.y + 3))
        expect(diagonal.hoverHighlightArmed, "movement is measured as a distance, not per axis")

        let creeping = shown()
        for step in 1...4 {
            creeping.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(creeping.hoverHighlightArmed, "and it accumulates: the anchor holds while it moves")
    }

    // MARK: - Scrolling and keys

    /// 验证滚动始终会解除武装，滚轮每格微移指针也不会重新武装。
    static func scrollingDisarms() {
        let scrolled = armed()
        scrolled.disarmHoverHighlight(pointerAt: rest)
        expect(!scrolled.hoverHighlightArmed, "a scroll drops the highlight")

        let stillScrolling = armed()
        // 手势中的每个事件都会重新锚定，因此手在滚轮上的拖移永远不会累积。
        for step in 1...20 {
            stillScrolling.disarmHoverHighlight(
                pointerAt: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
            stillScrolling.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(
            !stillScrolling.hoverHighlightArmed,
            "a wheel nudging the mouse a point per click stays disarmed for the whole gesture")
    }

    /// 验证手势结束后的漂移不会重新武装，只有真实移动才会。
    static func driftDoesNotRearm() {
        let state = armed()
        state.disarmHoverHighlight(pointerAt: rest)
        // 手势结束时 AppKit 送来的 mouse-moved 携带的是指针原有的位置。
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "the gesture's own trailing mouse-moved re-arms nothing")
        state.notePointerMoved(to: CGPoint(x: rest.x + 2, y: rest.y + 1))
        expect(!state.hoverHighlightArmed, "nor does a hand resting on the mouse jogging it a point")
        state.notePointerMoved(to: CGPoint(x: rest.x + 12, y: rest.y))
        expect(state.hoverHighlightArmed, "a real move afterwards brings the highlight back")
    }

    // MARK: - Clearing what is already lit

    /// 验证解除武装会递增 token 以清除已点亮行，而已解除时保持静默。
    static func theDisarmTokenClearsLitRows() {
        let state = armed()
        let token = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        expect(state.hoverDisarmToken != token, "disarming bumps the token that clears lit rows")

        let quiet = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        state.notePointerMoved(to: rest)
        expect(
            state.hoverDisarmToken == quiet,
            "an already-disarmed palette bumps nothing, so a scroll re-renders no rows")

        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        expect(
            state.hoverDisarmToken == quiet, "and arming is silent: pointer movement never rebuilds")
    }
}
