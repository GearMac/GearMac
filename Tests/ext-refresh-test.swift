// 文件职责：验证 ExtensionRefreshPolicy 的间隔解析、可调度判定、到期时间与退避抖动、超时上限，以及副标题/状态指示与手动刷新拒绝原因。
// 分层：测试 harness；纯策略函数断言，不启动运行时或网络。

import Foundation

@main
@MainActor
struct ExtensionRefreshTests {
    static var failures = 0

    /// 断言：条件为假时累计失败并打印 FAIL，否则打印 PASS。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    /// 用 JSON 字典构造 ExtensionCommand，失败返回 nil。
    static func command(json: [String: Any]) -> ExtensionCommand? {
        ExtensionCommand(json: json)
    }

    /// 构造一个 no-view 命令的 JSON，可选带上 interval 字段。
    static func baseJSON(interval: Any?) -> [String: Any] {
        var json: [String: Any] = [
            "name": "status", "title": "Status", "mode": "no-view"
        ]
        if let interval { json["interval"] = interval }
        return json
    }

    // MARK: - Interval parsing

    /// 校验 s/m/h/d 各时间单位均可解析。
    static func parseAcceptsAllUnits() {
        expect(ExtensionRefreshPolicy.parse("90s") == 90, "seconds parse")
        expect(ExtensionRefreshPolicy.parse("1m") == 60, "minutes parse")
        expect(ExtensionRefreshPolicy.parse("12h") == 12 * 3600, "hours parse")
        expect(ExtensionRefreshPolicy.parse("1d") == 86400, "days parse")
    }

    /// 校验低于下限的间隔被钳制到一分钟。
    static func parseClampsToTheFloor() {
        expect(ExtensionRefreshPolicy.parse("10s") == 60, "a 10s manifest clamps to a minute")
        expect(ExtensionRefreshPolicy.parse("30s") == 60, "a 30s manifest clamps to a minute")
    }

    /// 校验缺失、非数字、未知单位与非法数值都被拒绝。
    static func parseRejectsGarbage() {
        expect(ExtensionRefreshPolicy.parse(nil) == nil, "a missing interval is no schedule")
        expect(ExtensionRefreshPolicy.parse("soon") == nil, "words are rejected")
        expect(ExtensionRefreshPolicy.parse("1w") == nil, "weeks are rejected")
        expect(ExtensionRefreshPolicy.parse("m") == nil, "a bare unit is rejected")
        expect(ExtensionRefreshPolicy.parse("0m") == nil, "zero is rejected")
        expect(ExtensionRefreshPolicy.parse("-5m") == nil, "negatives are rejected")
    }

    /// 校验清单中的 interval 解析结果与原始文本保留，且不同模式使用不同下限。
    static func manifestCarriesTheInterval() {
        let parsed = command(json: baseJSON(interval: "1m"))
        expect(parsed?.interval == 60, "the manifest interval parses")
        expect(parsed?.intervalRaw == "1m", "the raw text survives for Settings")
        expect(command(json: baseJSON(interval: nil))?.interval == nil, "no key means no schedule")
        expect(
            command(json: baseJSON(interval: "weekly"))?.interval == nil,
            "garbage means no schedule, not a crash")
        let frequent = baseJSON(interval: "10s")
        expect(command(json: frequent)?.interval == 60, "no-view manifests keep the minute floor")
        var menu = frequent
        menu["mode"] = "menu-bar"
        expect(command(json: menu)?.interval == 10, "menu-bar manifests keep the ten-second floor")
        expect(command(json: menu)?.intervalRaw == "10s", "menu-bar Settings retain the requested interval")
    }

    // MARK: - Schedulability

    /// 校验只有带 interval 的 no-view 命令可被调度。
    static func onlyNoViewSchedules() {
        expect(
            ExtensionRefreshPolicy.isSchedulable(mode: .noView, interval: 60),
            "no-view with an interval schedules")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .noView, interval: nil),
            "no-view without an interval never wakes the loop")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .view, interval: 60),
            "a view interval never schedules")
        expect(
            !ExtensionRefreshPolicy.isSchedulable(mode: .menuBar, interval: 60),
            "the no-view scheduler excludes menu-bar commands")
    }

    // MARK: - Due dates and backoff

    /// 校验从未运行过的命令立即到期。
    static func firstRunIsImmediatelyDue() {
        let now = Date()
        let due = ExtensionRefreshPolicy.nextDue(
            lastRun: nil, now: now, interval: 60, consecutiveFailures: 0, entryID: "extension:a/b")
        expect(due == now, "a command that never ran is due now")
    }

    /// 校验下次到期时间等于上次运行加一个间隔（含相位偏移）。
    static func dueFollowsTheInterval() {
        let now = Date()
        let lastRun = now.addingTimeInterval(-120)
        let due = ExtensionRefreshPolicy.nextDue(
            lastRun: lastRun, now: now, interval: 60, consecutiveFailures: 0,
            entryID: "extension:a/b")
        expect(
            due.timeIntervalSince(lastRun) >= 60 && due.timeIntervalSince(lastRun) <= 66,
            "due is one interval past the run, plus phase")
    }

    /// 校验连续失败按指数延长等待，并封顶在最大间隔。
    static func failuresBackOffExponentially() {
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 0) == 60,
            "no failures means the bare interval")
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 3) == 480,
            "three failures octuple the wait")
        expect(
            ExtensionRefreshPolicy.effectiveInterval(60, consecutiveFailures: 99)
                == ExtensionRefreshPolicy.maximumInterval,
            "backoff caps at a day")
    }

    /// 校验相位抖动对同一命令稳定且不超过上限。
    static func jitterIsStableAndBounded() {
        let first = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 60)
        let second = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 60)
        expect(first == second, "the phase is stable across launches")
        expect(first >= 0 && first < 6, "a minute interval phases within six seconds")
        let hourly = ExtensionRefreshPolicy.jitter(entryID: "extension:coffee/status", interval: 3600)
        expect(hourly >= 0 && hourly <= 300, "the phase caps at five minutes")
    }

    /// 校验命令超时小于间隔，且不低于最短等待。
    static func timeoutStaysInsideTheInterval() {
        let minute = ExtensionRefreshPolicy.timeout(interval: 60)
        expect(minute <= 60, "a hung minute command dies before its successor is due")
        expect(minute >= 15, "even a tight command gets fifteen seconds")
        expect(ExtensionRefreshPolicy.timeout(interval: 3600) == 120, "long intervals cap the wait")
    }

    // MARK: - Subtitles and launch types

    /// 校验运行时副标题覆盖清单值，清除后回退到清单值。
    static func overrideWinsOverManifest() {
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: "✔ Caffeinated", ownerTitle: "Coffee")
                == "✔ Caffeinated",
            "the live subtitle wins")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: nil, ownerTitle: "Something Else") == "Coffee",
            "clearing falls back to the manifest")
    }

    /// 校验与扩展名重复的副标题会被丢弃，且比较忽略大小写。
    static func ownerRestatementIsDropped() {
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "Coffee", override: nil, ownerTitle: "Coffee") == nil,
            "a subtitle restating the extension is dropped")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(
                manifest: "coffee", override: nil, ownerTitle: "Coffee") == nil,
            "the comparison ignores case")
        expect(
            ExtensionRefreshPolicy.displaySubtitle(manifest: nil, override: nil, ownerTitle: "Coffee")
                == nil,
            "no subtitle stays no subtitle")
    }

    /// 校验状态指示点随可调度/启用/错误状态变化。
    static func indicatorNamesTheState() {
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: false, backgroundEnabled: false, lastError: nil) == nil,
            "an unschedulable command shows nothing")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true, lastError: nil) == .active,
            "an enabled schedule shows the active dot")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: false, lastError: nil) == .idle,
            "a switched-off schedule shows the dimmed dot")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true, lastError: "Timed out.")
                == .failed("Timed out."),
            "an error replaces the dot until the next success")
        expect(
            ExtensionRefreshPolicy.indicator(
                schedulable: true, backgroundEnabled: true,
                lastError: "TypeError: x\n    at foo\n    at bar") == .failed("TypeError: x"),
            "a JS stack is cut to its headline before it reaches the row")
    }

    /// 校验启动类型原始值与 @raycast/api 的 LaunchType 一致。
    static func launchTypesMatchTheJSContract() {
        expect(
            ExtensionLaunchType.background.rawValue == "background",
            "background matches @raycast/api LaunchType.Background")
        expect(
            ExtensionLaunchType.userInitiated.rawValue == "userInitiated",
            "userInitiated matches LaunchType.UserInitiated")
    }

    /// 校验手动刷新的拒绝原因：空闲放行，正在刷新/其他命令/前台运行时给出原因。
    static func refreshNowExplainsARefusal() {
        let mine = "extension:coffee/status"
        expect(
            ExtensionRefreshPolicy.refreshNowRefusal(
                foregroundRunning: false, refreshingCommand: nil, command: mine) == nil,
            "an idle runtime refreshes now")
        expect(
            ExtensionRefreshPolicy.refreshNowRefusal(
                foregroundRunning: false, refreshingCommand: mine, command: mine)
                == "Already refreshing.",
            "the same command mid-refresh says so")
        expect(
            ExtensionRefreshPolicy.refreshNowRefusal(
                foregroundRunning: false, refreshingCommand: "extension:other/tick", command: mine)
                != nil,
            "another command's tick refuses with a reason")
        expect(
            ExtensionRefreshPolicy.refreshNowRefusal(
                foregroundRunning: true, refreshingCommand: nil, command: mine) != nil,
            "an open foreground command refuses with a reason")
    }

    /// 依次运行全部检查，最后按失败数决定退出码。
    static func main() {
        parseAcceptsAllUnits()
        parseClampsToTheFloor()
        parseRejectsGarbage()
        manifestCarriesTheInterval()
        onlyNoViewSchedules()
        firstRunIsImmediatelyDue()
        dueFollowsTheInterval()
        failuresBackOffExponentially()
        jitterIsStableAndBounded()
        timeoutStaysInsideTheInterval()
        overrideWinsOverManifest()
        ownerRestatementIsDropped()
        indicatorNamesTheState()
        launchTypesMatchTheJSContract()
        refreshNowExplainsARefusal()

        print(failures == 0 ? "Extension refresh tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
