// 文件职责：把转录文本按插入位置上下文做首字母大小写与空格适配。
// 分层：Model/纯函数；不访问 UI 或系统 API。
import Foundation

enum DictationTextFormatter {
    /// 插入点上下文：光标前后字符，用于判断大小写与空格。
    struct Context: Sendable {
        let trailing: Character?
        let lastNonWhitespace: Character?
        let newParagraph: Bool
        let following: Character?

        /// 从光标前的文本（逆序扫描）与光标后的文本提取首尾字符与是否新段落。
        init(before: Substring, after: Substring) {
            trailing = before.last
            following = after.first
            var last: Character?
            var paragraph = false
            for character in before.reversed() {
                if !character.isWhitespace {
                    last = character
                    break
                }
                if character.isNewline { paragraph = true }
            }
            lastNonWhitespace = last
            newParagraph = paragraph
        }
    }

    /// 裁剪空白后按上下文适配首字母大小写，并在必要时补一个前导/尾随空格。
    static func format(_ transcription: String, context: Context?, adaptCapitalization: Bool = true) -> String
    {
        var text = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let context else { return text }
        if adaptCapitalization, let first = text.first, first.isLetter {
            let replacement: String
            if context.lastNonWhitespace == nil || context.newParagraph
                || context.lastNonWhitespace.map({ ".!?".contains($0) }) == true
            {
                replacement = String(first).uppercased()
            } else {
                replacement = String(first).lowercased()
            }
            text.replaceSubrange(text.startIndex...text.startIndex, with: replacement)
        }
        if let trailing = context.trailing, !trailing.isWhitespace,
            !"([{/\"'‘’“—-".contains(trailing),
            let leading = text.first, !".,!?;:)]}/\"'”".contains(leading)
        {
            text = " " + text
        }
        if let leading = context.following, !leading.isWhitespace,
            let trailing = text.last, !trailing.isWhitespace,
            !".,!?;:)]}/\"'”".contains(leading)
        {
            text += " "
        }
        return text
    }
}
