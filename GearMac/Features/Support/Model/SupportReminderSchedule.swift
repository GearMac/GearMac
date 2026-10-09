// 文件职责：支持提醒的纯计算调度：根据上次询问时间和当前时间，算出距下次询问还有多少秒。
// 分层：Model；纯函数、无副作用，所有日期都由调用方传入。
import Foundation

/// 支持窗口下次可以询问的时机。纯函数：所有日期都由外部传入。
enum SupportReminderSchedule {
    /// 两次询问之间的间隔：30 天。
    static let interval: TimeInterval = 30 * 24 * 3600

    /// 距下次询问的秒数；`0` 表示现在就该询问。以最近一次询问为基准，没有则用首次运行时间。
    static func wait(since anchor: Date, now: Date) -> TimeInterval {
        // 双向截断：系统时钟回拨时，也不能把询问推迟到超过一个完整间隔。
        let elapsed = min(max(0, now.timeIntervalSince(anchor)), interval)
        return interval - elapsed
    }
}
