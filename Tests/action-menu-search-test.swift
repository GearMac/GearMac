// 文件职责：验证动作菜单搜索查询 ActionMenuSearchQuery 的独立测试 harness（不使用 XCTest），覆盖空查询、模糊匹配、大小写/变音符号折叠与首尾空白处理。
// 分层：测试 harness；仅依赖 Foundation，通过进程退出码报告失败，不得 import AppKit/SwiftUI。
import Foundation

/// 动作菜单搜索的独立测试入口：按 @main 执行，逐条断言 ActionMenuSearchQuery 的匹配行为。
@main
@MainActor
struct ActionMenuSearchTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件为真则计入通过数，否则打印失败信息并计入失败数。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次执行本 harness 的全部断言，最后打印统计结果并以退出码反映成败。
    static func main() {
        let empty = ActionMenuSearchQuery("  \n")
        expect(empty.isEmpty, "a whitespace-only query is empty")
        expect(empty.score("Paste as Plain Text") != nil, "a blank query keeps every action")

        let plainText = ActionMenuSearchQuery("ptxt")
        expect(!plainText.isEmpty, "a meaningful query is not empty")
        expect(
            plainText.score("Paste as Plain Text") != nil,
            "a non-contiguous query uses the launcher's fuzzy matcher")
        expect(plainText.score("Copy to Clipboard") == nil, "unmatched actions are removed")
        let ranked = ActionMenuSearchQuery("paste")
        expect(
            ranked.score("Paste")! > ranked.score("Paste as Plain Text")!,
            "the strongest fuzzy result can drive the menu highlight")

        let folded = ActionMenuSearchQuery("resume")
        expect(folded.score("Résumé") != nil, "matching stays case- and diacritic-insensitive")

        let preserved = ActionMenuSearchQuery("  paste  ")
        expect(preserved.score("Paste to Finder") != nil, "outer whitespace does not affect matching")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
