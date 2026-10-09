// 文件职责：识别「双击单个修饰键」手势：跟踪按下与抬起的时序，在第二次抬起时上报完成的修饰键。
// 分层：Model；纯状态机，时间戳由调用方传入。
import Foundation

/// 识别被双击的单个修饰键。参见 docs/features/hotkeys.md#double-tap-modifiers。
struct DoubleTapDetector {
    /// 一次按下仍算作「轻点」的最长时长；与 `HyperKeyTap.quickPressWindow` 保持一致。
    static let maxHold: TimeInterval = 0.25
    /// 第一次轻点的抬起与第二次轻点的按下之间的最长间隔。
    static let maxGap: TimeInterval = 0.30

    /// 检测器的输入事件。
    enum Input: Sendable {
        /// 当前按住的四个候选修饰键，以及 `fn` 是否也同时按下。
        case modifiers(Set<DoubleTapModifier>, hasOtherModifiers: Bool)
        /// 键盘按键或鼠标点击：它会把进行中的单键按下变成组合键。
        case otherInput
    }

    private var held: Set<DoubleTapModifier> = []
    private var press: (modifier: DoubleTapModifier, startedAt: TimeInterval)?
    private var pendingTap: (modifier: DoubleTapModifier, releasedAt: TimeInterval)?

    /// 完成双击的那个修饰键；在第二次抬起时触发，绝不在按下时触发。
    mutating func handle(_ input: Input, at now: TimeInterval) -> DoubleTapModifier? {
        switch input {
        case .otherInput:
            invalidate()
            return nil
        case .modifiers(let modifiers, let hasOtherModifiers):
            return handle(modifiers, hasOtherModifiers: hasOtherModifiers, at: now)
        }
    }

    /// 清空按住状态并作废进行中的轻点。
    mutating func reset() {
        held = []
        invalidate()
    }

    /// 根据当前按住的修饰键集合推进状态机。
    private mutating func handle(
        _ modifiers: Set<DoubleTapModifier>, hasOtherModifiers: Bool, at now: TimeInterval
    ) -> DoubleTapModifier? {
        let previous = held
        held = modifiers

        guard !hasOtherModifiers else {
            invalidate()
            return nil
        }
        if modifiers.isEmpty { return completeTap(at: now) }

        // 轻点只能从没有任何键被按住的状态开始，因此正在散开的组合键不会被当作新的一次按下。
        guard previous.isEmpty, modifiers.count == 1, let modifier = modifiers.first else {
            invalidate()
            return nil
        }
        press = (modifier, now)
        return nil
    }

    /// 在一次按下被释放时判定是否构成（或完成）双击。
    private mutating func completeTap(at now: TimeInterval) -> DoubleTapModifier? {
        guard let press, now - press.startedAt <= Self.maxHold else {
            invalidate()
            return nil
        }
        self.press = nil

        guard let pending = pendingTap, pending.modifier == press.modifier,
            press.startedAt - pending.releasedAt <= Self.maxGap
        else {
            pendingTap = (press.modifier, now)
            return nil
        }
        pendingTap = nil
        return press.modifier
    }

    /// 作废进行中的按下与待匹配的轻点。
    private mutating func invalidate() {
        press = nil
        pendingTap = nil
    }
}
