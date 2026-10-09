// 文件职责：封装 Raycast 后台刷新策略的各类判定（解析 interval、退避、抖动、调度与刷新拒绝、状态指示）。
// 分层：Model；无状态、不读时钟，所有时刻以参数传入，不 import AppKit/SwiftUI。
import Foundation

/// Raycast 的后台刷新策略，归结为若干判定逻辑。无状态、不读时钟：每个时刻都以参数传入，
/// 因此测试可直接驱动它。
enum ExtensionRefreshPolicy {
    /// manifest 可要求的下限；更短会为重绘副标题而耗电。
    static let minimumInterval: TimeInterval = 60
    /// 菜单栏项就地重绘，因此可以比启动器副标题刷新得快得多。
    static let menuBarMinimumInterval: TimeInterval = 10
    /// 出错的命令最多退避到这个间隔，以保证它永远不会占住循环。
    static let maximumInterval: TimeInterval = 24 * 3600
    /// 同一时刻到期的命令，若落在此窗口内则合并为一批运行。
    static let coalescingWindow: TimeInterval = 30
    /// 空闲唤醒保持如此稀疏；日期运算是廉价的，但一次唤醒从不廉价。
    static let idleHeartbeat: TimeInterval = 300

    /// `"90s"`、`"1m"`、`"12h"`、`"1d"` → 秒数，并不低于下限。其他写法均视为无调度。
    static func parse(_ raw: String?, floor: TimeInterval = minimumInterval) -> TimeInterval? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count >= 2, let unit = text.last, let amount = Double(text.dropLast()),
            amount.isFinite, amount > 0
        else { return nil }
        let multiplier: Double
        switch unit {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        default: return nil
        }
        let seconds = amount * multiplier
        // 过大的数值会溢出为无穷，从而排出一个永远不会到来的 tick。
        return seconds.isFinite ? max(seconds, floor) : nil
    }

    /// 菜单栏刷新由它自己的调度器负责。
    static func isSchedulable(mode: ExtensionCommandMode, interval: TimeInterval?) -> Bool {
        mode == .noView && interval != nil
    }

    /// 失败按指数退避，使出错的命令不再每分钟都耗费一次启动。
    static func effectiveInterval(_ base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        min(base * pow(2, Double(max(consecutiveFailures, 0))), maximumInterval)
    }

    /// 按命令确定性的相位偏移，使安装后不会在睡眠后集体同时重发。
    static func jitter(entryID: String, interval: TimeInterval) -> TimeInterval {
        let bound = min(interval * 0.1, 300)
        guard bound >= 1 else { return 0 }
        return Double(stableHash(entryID) % UInt64(Int(bound)))
    }

    /// 计算某命令下一次应执行的时刻（基于上次运行时间、有效间隔与抖动）。
    static func nextDue(
        lastRun: Date?, now: Date, interval: TimeInterval, consecutiveFailures: Int, entryID: String
    ) -> Date {
        guard let lastRun else { return now }
        return lastRun.addingTimeInterval(
            effectiveInterval(interval, consecutiveFailures: consecutiveFailures)
                + jitter(entryID: entryID, interval: interval))
    }

    /// Refresh Now 无法启动的原因；可以启动时返回 nil。运行时同时只跑一个命令。
    static func refreshNowRefusal(
        foregroundRunning: Bool, refreshingCommand: String?, command: String
    ) -> String? {
        if refreshingCommand == command { return "Already refreshing." }
        guard foregroundRunning || refreshingCommand != nil else { return nil }
        return "Another extension command is running. Try again when it finishes."
    }

    /// 卡住的后台运行会在下一个运行到期前被终止，否则 tick 会堆积。
    static func timeout(interval: TimeInterval) -> TimeInterval {
        min(max(interval, 15), 120)
    }

    /// 可调度命令的启动器圆点状态：正在刷新、关闭时的暗色版本，或最近一次后台错误。
    /// 不可调度的命令则什么都不显示。
    static func indicator(
        schedulable: Bool, backgroundEnabled: Bool, lastError: String?
    ) -> ExtensionRefreshState? {
        guard schedulable else { return nil }
        // 失败信息带有 JS 堆栈；行视图会对其做哈希与差异比对，因此只保留首行。
        if let lastError { return .failed(headline(lastError)) }
        return backgroundEnabled ? .active : .idle
    }

    /// 提取错误信息的第一行作为标题（无内容时给出默认文案）。
    static func headline(_ message: String) -> String {
        String(message.split(separator: "\n").first ?? "Background refresh failed.")
    }

    /// `subtitle: null` 会清空并回退到 manifest；否则已存的覆盖值优先。若副标题只是重述所属扩展名
    /// 则被丢弃——行视图右侧已经展示了它。
    static func displaySubtitle(manifest: String?, override: String?, ownerTitle: String) -> String? {
        let resolved = (override ?? manifest)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved, !resolved.isEmpty else { return nil }
        return resolved.compare(ownerTitle, options: .caseInsensitive) == .orderedSame
            ? nil : resolved
    }

    /// `String.hashValue` 每次启动都会重新播种；相位稳定性需要自己的哈希函数。
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }
}
