// 文件职责：SettingsBackupCoverage（设置备份覆盖清单）的独立测试 harness，验证每个 AppSettings key 要么被备份、要么被有意排除且有合理理由，并确保敏感能力不被写进备份。
// 分层：测试 harness；纯清单断言，不读写文件。
import Foundation

/// 独立运行的测试入口：逐项断言后以失败数决定退出码。
@main
struct SettingsBackupTest {
    static func main() {
        var failures = 0

        /// 断言：条件为真则打印 PASS，否则打印 FAIL 并计数。
        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // 把违规项写进描述，这样失败信息能直接点名是哪个 key，而不只是哪条规则。
        func naming(_ rule: String, _ offenders: [String]) -> String {
            offenders.isEmpty ? rule : "\(rule) — \(offenders.sorted().joined(separator: ", "))"
        }

        let mirrored = SettingsBackupCoverage.mirrored
        let excluded = SettingsBackupCoverage.deliberatelyExcluded
        let external = SettingsBackupCoverage.externallySourced
        let allKeys = AppSettingsKey.allCases.map(\.rawValue)
        let mirroredKeys = mirrored.values.map(\.rawValue)

        let uncovered = allKeys.filter { !mirroredKeys.contains($0) && excluded[$0] == nil }
        check(
            naming("every AppSettings key is backed up or deliberately excluded", uncovered),
            uncovered.isEmpty)

        let bothWays = mirroredKeys.filter { excluded[$0] != nil }
        check(naming("no key is both backed up and excluded", bothWays), bothWays.isEmpty)

        let unknownExclusions = excluded.keys.filter { AppSettingsKey(rawValue: $0) == nil }
        check(
            naming("every excluded key names a real AppSettings key", Array(unknownExclusions)),
            unknownExclusions.isEmpty)

        let doubleClaimed = Dictionary(grouping: mirroredKeys, by: { $0 })
            .filter { $0.value.count > 1 }.keys
        check(
            naming("no two backup fields claim the same key", Array(doubleClaimed)),
            doubleClaimed.isEmpty)
        check(
            "fileSearchEnabled rides the settings backup",
            mirrored["fileSearchEnabled"] == .fileSearchEnabled)
        check(
            "file search scopes ride the settings backup",
            mirrored["fileSearchScopes"] == .fileSearchScopes)
        check(
            "user ignore patterns ride the settings backup",
            mirrored["fileSearchIgnorePatterns"] == .fileSearchIgnorePatterns)
        check("notes enablement rides the settings backup", mirrored["notesEnabled"] == .notesEnabled)
        check(
            "Markdown rendering rides the settings backup",
            mirrored["notesRendersMarkdown"] == .notesRendersMarkdown)
        check(
            "the formatting bar rides the settings backup",
            mirrored["notesShowsFormattingBar"] == .notesShowsFormattingBar)
        check(
            "clipboard enablement rides the settings backup",
            mirrored["clipboardEnabled"] == .clipboardEnabled)
        check(
            "emoji grid density rides the settings backup",
            mirrored["emojiGridColumns"] == .emojiGridColumns)

        // 逐个点名：备份现在会携带内容，因此远比以前更容易被转发出去。
        for key: AppSettingsKey in [
            .snippetsEnabled, .extensionsEnabled, .calendarEnabled, .autoJoinMeetings,
            .cameraPreview, .quickActionsEnabled
        ] {
            check(
                "\(key.rawValue) stays out of a backup",
                excluded[key.rawValue] != nil && mirrored.values.allSatisfy { $0 != key })
        }

        // 只重复 key 名称的理由等于没有解释，因此与缺失理由一样判定为失败。
        let emptyReasons = excluded.filter { key, reason in
            let trimmed = reason.trimmingCharacters(in: .whitespaces)
            return trimmed.count <= key.count || !trimmed.contains(" ")
        }.keys
        check(
            naming("every exclusion carries a real reason", Array(emptyReasons)),
            emptyReasons.isEmpty)

        // 整个 harness 存在的目的就是保护这一隐私属性。
        check(
            "snippetsEnabled stays out of a backup",
            excluded[AppSettingsKey.snippetsEnabled.rawValue] != nil)
        check(
            "snippetsEnabled is not backed up under another field",
            !mirroredKeys.contains(AppSettingsKey.snippetsEnabled.rawValue))

        let claimedTwice = external.keys.filter { mirrored[$0] != nil }
        check(
            naming("no field is both mirrored and externally sourced", Array(claimedTwice)),
            claimedTwice.isEmpty)

        let notActuallyExternal = external.keys.filter { AppSettingsKey(rawValue: $0) != nil }
        check(
            naming("externally sourced fields have no AppSettings key", Array(notActuallyExternal)),
            notActuallyExternal.isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
