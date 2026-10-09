// 文件职责：SupportReminderSchedule 提醒等待计算的独立契约测试 harness，覆盖间隔内倒计时、到期判定与时钟回拨边界。
// 分层：测试 harness；仅 import Foundation，不依赖 AppKit/SwiftUI，通过进程退出码报告失败。
import Foundation

@main
@MainActor
struct SupportTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件为假时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次运行全部用例，并按失败数决定退出码。
    static func main() {
        waitsOutTheWholeInterval()
        comesDueOnlyOnceTheIntervalHasPassed()
        survivesAClockThatMovedBackwards()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 被测的提醒间隔长度。
    private static let interval = SupportReminderSchedule.interval
    /// 固定锚点时间，避免用例依赖当前时钟。
    private static let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 验证等待时长在间隔内随时间线性递减。
    static func waitsOutTheWholeInterval() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor) == interval,
            "a fresh anchor waits a full interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval / 2)
                == interval / 2,
            "half an interval in, half an interval is left")
    }

    /// 验证只有走满整个间隔才算到期，且逾期后等待值为零而非负数。
    static func comesDueOnlyOnceTheIntervalHasPassed() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval - 1) == 1,
            "one second short is not yet due")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval) == 0,
            "due exactly at the interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor + interval * 10) == 0,
            "long overdue is due now, never a negative wait")
    }

    /// 时钟被回拨时，无论回拨多远，等待时间都不得超过一个间隔。
    static func survivesAClockThatMovedBackwards() {
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor - 1) == interval,
            "a second before the anchor still waits exactly one interval")
        expect(
            SupportReminderSchedule.wait(since: anchor, now: anchor - interval * 10) == interval,
            "a decade before the anchor waits one interval, not eleven")
    }
}
