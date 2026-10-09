// 文件职责：按分钟发布当前时间：仅在有人监听时运行，每个分钟边界更新 `now` 并触发 `onTick` 回调。
// 分层：Service；@MainActor 隔离，循环在休眠唤醒后自行重新对齐分钟边界。
import Foundation

/// 发布当前分钟，且仅在有人监听时才运行。
@MainActor
@Observable
final class MeetingClock {
    private(set) var now = Date()

    /// 每个分钟边界后触发；由 coordinator 决定新的一分钟意味着什么。
    @ObservationIgnored var onTick: (@MainActor () -> Void)?

    @ObservationIgnored private var tick: Task<Void, Never>?

    /// 时钟是否正在运行。
    var isRunning: Bool { tick != nil }

    /// 幂等：`applyClock` 会为每个监听者调用一次，重启会破坏对齐。
    func start() {
        guard tick == nil else { return }
        now = Date()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                // 每轮重新计算，使休眠的 Mac 唤醒后重新对齐而不是逐渐偏移。
                try? await Task.sleep(for: .seconds(Self.secondsToNextMinute()))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
                self.onTick?()
            }
        }
    }

    /// 停止时钟并释放后台任务。
    func stop() {
        tick?.cancel()
        tick = nil
    }

    /// 释放时取后台任务。
    isolated deinit {
        tick?.cancel()
    }

    /// 参考日期本身就是分钟边界，因此余数就是在当前分钟内的偏移。
    private static func secondsToNextMinute() -> TimeInterval {
        60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    }
}
