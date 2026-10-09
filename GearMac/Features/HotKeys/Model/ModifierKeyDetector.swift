// 文件职责：根据修饰键集合的变化判定单击、长按、双击与取消事件。
// 分层：Model；纯状态机，时间戳由调用方传入。
import Foundation

/// 修饰键单击/长按/双击检测器。
struct ModifierKeyDetector: Sendable {
    /// 检测器上报的修饰键事件。
    enum Event: Equatable {
        case pressed(ModifierKey)
        case released(ModifierKey, doubleTap: Bool, held: Bool)
        case cancelled
    }

    /// 等待第二次轻点完成所需的最长时长（含少量余量）。
    static let resolutionWindow: Duration = .seconds(
        DoubleTapDetector.maxGap + DoubleTapDetector.maxHold + 0.02)

    private(set) var held: Set<ModifierKey> = []
    private var press: (key: ModifierKey, startedAt: TimeInterval)?
    private var pendingTap: (key: ModifierKey, releasedAt: TimeInterval)?

    /// 根据新的按住集合推进状态机，返回产生的事件（无变化时返回 nil）。
    mutating func handle(_ keys: Set<ModifierKey>, at now: TimeInterval) -> Event? {
        let previous = held
        held = keys
        guard keys != previous else { return nil }
        if keys.isEmpty {
            guard let press else { return nil }
            self.press = nil
            let isHeld = now - press.startedAt > DoubleTapDetector.maxHold
            let isDouble =
                !isHeld && pendingTap?.key == press.key
                && press.startedAt - (pendingTap?.releasedAt ?? 0) <= DoubleTapDetector.maxGap
            pendingTap = isHeld || isDouble ? nil : (press.key, now)
            return .released(press.key, doubleTap: isDouble, held: isHeld)
        }
        guard previous.isEmpty, keys.count == 1, let key = keys.first else {
            cancel()
            return .cancelled
        }
        if pendingTap?.key != key { pendingTap = nil }
        press = (key, now)
        return .pressed(key)
    }

    /// 作废进行中的按下与待匹配的轻点。
    mutating func cancel() {
        press = nil
        pendingTap = nil
    }

    /// 清空按住状态并重置检测器。
    mutating func reset() {
        held = []
        cancel()
    }
}
