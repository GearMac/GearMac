// 文件职责：从回复文本中解析 ```choices 围栏（及其无围栏变体），拆出正文与候选项按钮。
// 分层：Model；纯文本解析，不得 import AppKit/SwiftUI。
import Foundation

/// 回复可以用 ```choices 围栏结尾；其中每一行会变成替读者作答的按钮。
enum ChatChoices {
    static let maxCount = 6
    /// 超过该长度的行属于误入围栏的正文，而非可选项。
    static let maxLength = 160

    /// 返回围栏之外的正文与其选项；围栏尚未闭合时（流式输出中）依然会被隐藏。
    static func split(_ text: String) -> (text: String, choices: [String]) {
        guard let open = text.range(of: "```choices", options: .backwards),
            open.lowerBound == text.startIndex || text[text.index(before: open.lowerBound)] == "\n"
        else { return labelled(text) ?? (text, []) }
        let body = text[open.upperBound...]
        let close = body.range(of: "```")
        let fenced = close.map { body[..<$0.lowerBound] } ?? body
        let after = close.map { String(body[$0.upperBound...]) } ?? ""
        let choices = fenced.split(whereSeparator: \.isNewline)
            .map { option(String($0)) }
            .filter { !$0.isEmpty && $0.count <= maxLength }
        let prose = [String(text[..<open.lowerBound]), after]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return (prose, Array(choices.prefix(maxCount)))
    }

    /// 端侧模型的无围栏形式：单独一行 `choices`，其后到结尾只能是列表项。
    private static func labelled(_ text: String) -> (text: String, choices: [String])? {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let label = lines.lastIndex(where: isLabel), label < lines.count - 1 else { return nil }
        let items = lines[(label + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty, items.allSatisfy(isListItem) else { return nil }
        let choices = items.map(option).filter { !$0.isEmpty && $0.count <= maxLength }
        guard !choices.isEmpty else { return nil }
        let prose = lines[..<label].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, Array(choices.prefix(maxCount)))
    }

    /// 识别 `choices` 行可能的各种写法：加粗、作为标题、带结尾冒号。
    private static func isLabel(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: #/(?i)(?:#{1,6}\s*)?(?:\*\*|__)?choices:?(?:\*\*|__)?:?/#) != nil
    }

    private static func isListItem(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).firstMatch(of: #/^(?:[-*•]|\d+[.)])\s+\S/#) != nil
    }

    /// 模型会像列普通条目那样列出选项，因此项目符号或编号并不属于选项内容。
    private static func option(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if let marker = trimmed.firstMatch(of: #/^(?:[-*•]|\d+[.)])\s+/#) {
            trimmed.removeSubrange(marker.range)
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}
