// 文件职责：以精确块序列断言 TextDiffEngine.diff 在 Unicode、并列选择、打包边界与上限处的行为。
// 分层：测试 harness；纯 Foundation，用 precondition 直接断言，失败即崩溃。

import Foundation

/// 文本差异引擎的独立契约测试 harness（直接运行，不依赖 XCTest）。
@main
enum TextDiffTests {
    /// 入口：覆盖空输入/插入/删除、Unicode、组合数边界、超上限快速路径与并列选择的断言。
    static func main() {
        precondition(TextDiffEngine.maxTokens <= Int(UInt16.max), "LCS cells are UInt16")

        precondition(TextDiffEngine.diff(original: "", modified: "") == [])
        precondition(TextDiffEngine.diff(original: "", modified: "new") == [.inserted("new")])
        precondition(TextDiffEngine.diff(original: "old", modified: "") == [.deleted("old")])
        precondition(
            TextDiffEngine.diff(original: "a b", modified: "b a")
                == [.deleted("a "), .equal("b"), .inserted(" a")])
        precondition(
            TextDiffEngine.diff(original: "café 👩🏽‍💻\n", modified: "cafe 👩🏽‍💻\n")
                == [.deleted("café"), .inserted("cafe"), .equal(" 👩🏽‍💻\n")])

        for count in Array(1...33) + [127, 128, 129] {
            let original = (0..<count).map { $0.isMultiple(of: 2) ? "old" : " " }.joined()
            let modified = (0..<count).map { $0.isMultiple(of: 2) ? "new" : " " }.joined()
            let expected: [TextDiffEngine.Chunk] = (0..<count).flatMap { index in
                index.isMultiple(of: 2)
                    ? [.deleted("old"), .inserted("new")] : [.equal(" ")]
            }
            precondition(TextDiffEngine.diff(original: original, modified: modified) == expected)
            precondition(
                TextDiffEngine.diff(original: "start " + original, modified: original)
                    == [.deleted("start "), .equal(original)])
            precondition(
                TextDiffEngine.diff(original: original, modified: "start " + original)
                    == [.inserted("start "), .equal(original)])
        }

        for count in [TextDiffEngine.maxTokens - 1, TextDiffEngine.maxTokens] {
            let original = (0..<count).map { $0.isMultiple(of: 2) ? "word" : " " }.joined()
            let suffix = String(original.dropFirst(4))
            let modified = "ward" + suffix
            precondition(
                TextDiffEngine.diff(original: original, modified: modified)
                    == [.deleted("word"), .inserted("ward"), .equal(suffix)])
        }

        let overCap = String(repeating: "word ", count: TextDiffEngine.maxTokens / 2) + "word"
        for (original, modified) in [(overCap, "short"), ("short", overCap)] {
            precondition(
                TextDiffEngine.diff(original: original, modified: modified)
                    == [.deleted(original), .inserted(modified)])
        }
        precondition(TextDiffEngine.diff(original: overCap, modified: overCap) == [.equal(overCap)])
        precondition(TextDiffEngine.diff(original: "", modified: overCap) == [.inserted(overCap)])
        precondition(TextDiffEngine.diff(original: overCap, modified: "") == [.deleted(overCap)])
        print("Exact chunks, Unicode, ties, packed boundaries, high LCS values and fast paths passed")
    }
}
