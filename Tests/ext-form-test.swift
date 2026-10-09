// 文件职责：验证扩展表单的两条纯规则：选择器弹层的几何测量与排布，以及日期输入表达式的解析与建议。
// 分层：测试 harness；固定 UTC 日历与 2026-09-04 基准时间，保证结果与运行月份无关。

import Foundation
import SwiftUI

/// 表单的两条纯规则：选择器的弹层从哪里展开，以及用户输入的日期文本代表什么。
@main
@MainActor
struct ExtensionFormTests {
    static var failures = 0
    static var passes = 0

    /// 固定日历，使 12 月与 6 月运行的测试结果一致。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// 2026 年 9 月 4 日（周五）09:30 UTC。
    static let now = ExtensionFormTests.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 4, hour: 9, minute: 30))!

    /// 依次运行全部检查，并输出汇总结果。
    static func main() {
        popoverGeometry()
        labelGeometry()
        popoverPlacement()
        datePresets()
        dateParsing()
        dateSuggestions()
        ExtensionListKeyTests.run(check: check)
        formActivation()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// 校验各类控件下 Enter/Space 的按键动作解析。
    static func formActivation() {
        let controls: [ExtensionFormField] = [
            .text, .textArea, .checkbox, .dropdown, .tagPicker, .datePicker, .filePicker
        ]
        for field in controls {
            for key in ExtensionFormKey.enterKeys {
                let expected: ExtensionFormKey.Action =
                    field == .text ? .consume : field == .textArea ? .ignored : .activate
                check(
                    "Enter operates \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: []) == expected)
                check(
                    "Cmd-Enter submits from \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: .command) == .submit)
                check(
                    "holding Cmd-Enter never resubmits from \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: .command, repeating: true) == .consume)
                check(
                    "holding Enter cannot toggle or select twice in \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: [], repeating: true)
                        == (field == .textArea ? .ignored : .consume))
                check(
                    "Actions menu retains Enter over \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: [], menuOpen: true) == .ignored)
                check(
                    "IME retains Enter over \(field)",
                    ExtensionFormKey.resolve(
                        field: field, key: key, modifiers: [], composing: true) == .ignored)
                for modifiers: EventModifiers in [.shift, .option, .control, [.command, .shift]] {
                    check(
                        "modified Enter stays available for shortcuts in \(field)",
                        ExtensionFormKey.resolve(
                            field: field, key: key, modifiers: modifiers) == .ignored)
                }
            }
            let space: ExtensionFormKey.Action =
                field == .checkbox || field == .filePicker ? .activate : .ignored
            check(
                "Space activates button-like controls in \(field)",
                ExtensionFormKey.resolve(
                    field: field, key: .space, modifiers: []) == space)
            check(
                "Ctrl-Space remains an input source shortcut in \(field)",
                ExtensionFormKey.resolve(
                    field: field, key: .space, modifiers: .control) == .ignored)
        }
        check(
            "descriptions and separators never activate",
            ExtensionFormKey.resolve(
                field: .inert, key: .return, modifiers: []) == .ignored)
    }

    // MARK: - Geometry

    /// 校验标签宽度的测量与窄面板下的钳制。
    static func labelGeometry() {
        let form = ExtensionFormMetrics.base
        check(
            "label reaches the panel edge beside its centred control",
            form.labelWidth(for: 750, gap: 12) == 183)
        check(
            "label width clamps when the panel cannot fit the control",
            form.labelWidth(for: 360, gap: 12) == 0)
    }

    /// 校验弹层行高、可见行上限与搜索框带来的额外高度。
    static func popoverGeometry() {
        print("\n# popover geometry")

        let pitch = ExtensionFormMetrics.base.popoverRowHeight + ExtensionFormMetrics.base.popoverRowSpacing
        check(
            "three rows measure exactly three rows",
            ExtensionFormMetrics.base.popoverListHeight(rows: 3)
                == pitch * 3 - ExtensionFormMetrics.base.popoverRowSpacing)
        check("no rows measure nothing", ExtensionFormMetrics.base.popoverListHeight(rows: 0) == 0)
        check(
            "a long list caps at the visible rows",
            ExtensionFormMetrics.base.popoverListHeight(rows: 40)
                == ExtensionFormMetrics.base.popoverRowsMaxHeight)
        check(
            "the uncapped height reports that a long list can bounce",
            ExtensionFormMetrics.base.popoverListContentHeight(rows: 40)
                > ExtensionFormMetrics.base.popoverRowsMaxHeight)
        check(
            "the cap is a half row, so it reads as scrollable",
            ExtensionFormMetrics.base.popoverVisibleRows
                != ExtensionFormMetrics.base.popoverVisibleRows
                .rounded())
        check(
            "a search row adds its own height",
            ExtensionFormMetrics.base.popoverHeight(rows: 3, hasSearchField: true)
                - ExtensionFormMetrics.base.popoverHeight(rows: 3, hasSearchField: false)
                == ExtensionFormMetrics.base.popoverSearchHeight)
        check(
            "a section heading takes room of its own",
            ExtensionFormMetrics.base.popoverListHeight(rows: 4, headers: 2)
                - ExtensionFormMetrics.base.popoverListHeight(rows: 4)
                == (ExtensionFormMetrics.base.popoverSectionHeaderHeight
                    + ExtensionFormMetrics.base.popoverRowSpacing) * 2)
        check(
            "and a headed list still caps at the visible rows",
            ExtensionFormMetrics.base.popoverListHeight(rows: 40, headers: 6)
                == ExtensionFormMetrics.base.popoverRowsMaxHeight)
        check(
            "an empty list still measures the row it draws, since the panel is sized to this",
            ExtensionFormMetrics.base.popoverHeight(rows: 0, hasSearchField: false)
                == ExtensionFormMetrics.base.popoverRowHeight + ExtensionFormMetrics.base.popoverPadding * 2)
    }

    /// 校验弹层相对锚点的向下/向上排布与边界钳制。
    static func popoverPlacement() {
        print("\n# popover placement")

        let control = CGRect(x: 0, y: 100, width: 360, height: 32)

        let below = ExtensionFormMetrics.base.placement(
            anchor: control, popoverHeight: 200, containerHeight: 600)
        check("it opens downward when there is room", !below.flipped)
        check(
            "and sits one gap under the control",
            below.y == control.maxY + ExtensionFormMetrics.base.popoverGap)

        // 位于高表单底部的控件：下方没有空间，上方空间充足。
        let low = CGRect(x: 0, y: 500, width: 360, height: 32)
        let above = ExtensionFormMetrics.base.placement(
            anchor: low, popoverHeight: 200, containerHeight: 600)
        check("it flips up when the bottom would cut it off", above.flipped)
        check(
            "and sits one gap over the control",
            above.y == low.minY - ExtensionFormMetrics.base.popoverGap - 200)

        // 无论朝哪边都比容器高：显示列表开头比显示中段更有用。
        let cramped = ExtensionFormMetrics.base.placement(
            anchor: low, popoverHeight: 500, containerHeight: 300)
        check("a list taller than the form still starts on screen", cramped.y >= 0)
        check("and does not claim to have flipped", !cramped.flipped)

        // 下方刚好放得下也算有空间：并列情形下规则不得翻转。
        let exact = ExtensionFormMetrics.base.placement(
            anchor: control, popoverHeight: 100, containerHeight: 238)
        check("a list that exactly fits opens downward", !exact.flipped)
    }

    // MARK: - Dates

    /// 校验预设日期行（无日期/今天/明天/昨天/后续星期）的顺序与取值。
    static func datePresets() {
        print("\n# date presets")

        let rows = ExtensionDateExpression.presets(
            now: now, calendar: calendar, includesTime: false)
        check("the first row clears the field", rows.first?.title == "No Date")
        check("and carries no date to clear it with", rows.first?.date == nil)
        check("today, tomorrow and yesterday follow", rows[1].title == "Today")
        check("tomorrow is second", rows[2].title == "Tomorrow")
        check("yesterday is third", rows[3].title == "Yesterday")
        check(
            "tomorrow really is the next day",
            rows[2].date == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        check("the week that follows is named", rows[4].title == "Sunday", rows[4].title)
        check("every dated row states its day", rows.dropFirst().allSatisfy { $0.detail != nil })
    }

    /// 校验各类日期表达式文本的解析结果。
    static func dateParsing() {
        print("\n# date expressions")

        let today = calendar.startOfDay(for: now)
        check("today parses", parse("today") == today)
        check(
            "tomorrow parses",
            parse("tomorrow") == calendar.date(byAdding: .day, value: 1, to: today))
        check(
            "yesterday parses",
            parse("yesterday") == calendar.date(byAdding: .day, value: -1, to: today))
        check(
            "in 3 days parses",
            parse("in 3 days") == calendar.date(byAdding: .day, value: 3, to: today))
        check(
            "3 days parses without the preposition",
            parse("3 days") == calendar.date(byAdding: .day, value: 3, to: today))
        check(
            "in 2 weeks parses",
            parse("in 2 weeks") == calendar.date(byAdding: .weekOfYear, value: 2, to: today))

        // 2026 年 9 月 4 日是周五，因此周一是 9 月 7 日。
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))
        check("a weekday name means the coming one", parse("monday") == monday)
        check("next monday means the same", parse("next monday") == monday)
        check("a weekday never points backwards", parse("thursday")! > today)

        check(
            "a day and month parse",
            parse("25 dec") == calendar.date(from: DateComponents(year: 2026, month: 12, day: 25)))
        check(
            "and the other way round",
            parse("dec 25") == calendar.date(from: DateComponents(year: 2026, month: 12, day: 25)))
        check(
            "a date already past means next year",
            parse("1 jan") == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let tomorrowTen = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 5, hour: 10, minute: 0))
        check("tomorrow at 10am parses whole", parse("tomorrow at 10am") == tomorrowTen)
        check("and without the at", parse("tomorrow 10am") == tomorrowTen)
        check(
            "pm is afternoon",
            parse("today at 7pm")
                == calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 19)))
        check(
            "24-hour times parse",
            parse("today at 22:15")
                == calendar.date(
                    from: DateComponents(year: 2026, month: 9, day: 4, hour: 22, minute: 15)))
        check(
            "midnight is not noon",
            parse("today at 12am")
                == calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 0)))

        check("nonsense parses to nothing", parse("wibble") == nil)
        check("an empty expression parses to nothing", parse("") == nil)
        // 裸数字是没有单位的计数，把它当小时读入属于猜测。
        check("a bare number is not a time", parse("10") == nil)
    }

    /// 校验日期输入建议：空查询、已输入表达式、部分词与无法解析的输入。
    static func dateSuggestions() {
        print("\n# date suggestions")

        let empty = ExtensionDateExpression.suggestions(
            query: "", now: now, calendar: calendar, includesTime: false)
        check("an empty query offers the presets", empty.first?.title == "No Date")

        let typed = ExtensionDateExpression.suggestions(
            query: "in 3 days", now: now, calendar: calendar, includesTime: false)
        check("what was typed leads the list", typed.first?.title == "in 3 days")
        check(
            "and resolves to the day it names",
            typed.first?.date
                == calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now)))

        let partial = ExtensionDateExpression.suggestions(
            query: "tom", now: now, calendar: calendar, includesTime: false)
        check("a partial word still finds its preset", partial.contains { $0.title == "Tomorrow" })

        let nonsense = ExtensionDateExpression.suggestions(
            query: "zzz", now: now, calendar: calendar, includesTime: false)
        check("an unparsable query offers nothing", nonsense.isEmpty)
    }

    // MARK: - Helpers

    /// 用固定的 now 与 calendar 解析日期表达式。
    static func parse(_ expression: String) -> Date? {
        ExtensionDateExpression.parse(expression, now: now, calendar: calendar)
    }

    /// 记录断言结果：通过则累加 passes，否则累加 failures 并打印失败详情。
    static func check(_ description: String, _ condition: Bool, _ detail: String? = nil) {
        if condition {
            passes += 1
            print("PASS  \(description)")
        } else {
            failures += 1
            print("FAIL  \(description)" + (detail.map { " — \($0)" } ?? ""))
        }
    }
}
