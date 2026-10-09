// 文件职责：定义会议自动加入的判定策略，从候选事件中选出唯一应当自动打开的会议。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 会议是否应自动打开、以及应打开哪一场：从可加入的事件中按卡片规则选出。
struct AutoJoinPolicy: Sendable {
    /// 只有开始时间不早于该时刻的会议才符合条件，因此通话进行中才布防不会立即触发。
    let armedAt: Date
    /// 是否仅限已知提供商（非 generic）的会议链接。
    let namedProvidersOnly: Bool

    /// 从事件列表中选出应自动加入的会议，无符合项时返回 nil。
    func meeting(
        from events: [MeetingEvent], now: Date, window: UpcomingWindow,
        joined: Set<MeetingEvent.ID>
    ) -> MeetingEvent? {
        // 先过滤再挑选，使被跳过的链接不会遮蔽与它时间重叠的通话。
        let candidates =
            namedProvidersOnly ? events.filter { $0.link?.provider != .generic } : events
        guard let carded = window.carded(from: candidates, now: now) else { return nil }
        // 绝不提前、绝不选已经开始过的会议、也绝不重复加入同一场。
        guard carded.start >= armedAt, now >= carded.start, !joined.contains(carded.id) else {
            return nil
        }
        return carded
    }
}
