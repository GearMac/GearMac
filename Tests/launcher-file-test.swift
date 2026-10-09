// 文件职责：验证 LauncherFileFormat 对 settings.json 中启动器记录（Launcher items）的读写往返、缺失字段与非法记录的处理。
// 分层：测试 harness；覆盖 Record 的编解码与容错，不触碰真实用户配置。

import Foundation

@main
@MainActor
struct LauncherFileTest {
    static var failures = 0

    /// harness 入口：运行全部用例并以失败数决定退出码。
    static func main() {
        testRoundTrip()
        testHandEdits()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private typealias Record = LauncherFileFormat.Record

    /// 校验记录能完整写入并读回，包括 null 字段与默认空记录。
    private static func testRoundTrip() {
        let safari = Record(shortcut: "hyper+s", alias: "web", showInLauncher: true)
        let hidden = Record(shortcut: nil, alias: nil, showInLauncher: false)
        let json = LauncherFileFormat.json([("com.apple.Safari", safari), ("com.example.hidden", hidden)])
        check(
            "records keep the order given",
            json.members?.map(\.key) == ["com.apple.Safari", "com.example.hidden"])
        check(
            "every field is written, none as null",
            json["com.example.hidden"]?.members?.map(\.key) == ["shortcut", "alias", "showInLauncher"]
                && json["com.example.hidden"]?["shortcut"] == .null)

        let decoded = LauncherFileFormat.records(from: json) { _ in Record() }
        check(
            "the records read back",
            decoded?.records == ["com.apple.Safari": safari, "com.example.hidden": hidden])
        check("with nothing to report", decoded?.problems == [])

        check("a default record is empty", Record().isEmpty)
        check("a hidden one is not", !hidden.isEmpty)
    }

    /// 校验手工编辑 settings.json 时缺失字段、类型错误与 null 的容错行为。
    private static func testHandEdits() {
        let current = Record(shortcut: "hyper+l", alias: "old", showInLauncher: false)
        let decoded = LauncherFileFormat.records(
            from: .object([
                "lock-screen": .object(["alias": "lock"]),
                "sleep": .object(["shortcut": 5, "alias": true, "showInLauncher": "no"]),
                "log-out": .object(["shortcut": .null, "alias": .null, "showInLauncher": true]),
                "restart": "cmd+r"
            ])
        ) { _ in current }
        check(
            "a field left out keeps its value",
            decoded?.records["lock-screen"]
                == Record(shortcut: "hyper+l", alias: "lock", showInLauncher: false))
        check("a field of the wrong type keeps its value", decoded?.records["sleep"] == current)
        check("null clears", decoded?.records["log-out"] == Record())
        check("a record that isn't an object keeps its value", decoded?.records["restart"] == current)
        check("each mistake is reported", decoded?.problems.count == 4)
        let list = LauncherFileFormat.records(from: .array([])) { _ in Record() }
        check("a list is not an object", list == nil)
    }

    /// 断言辅助：成立则打印 PASS，否则打印 FAIL 并累加失败计数。
    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
