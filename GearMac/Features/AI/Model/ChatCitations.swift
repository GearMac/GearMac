// 文件职责：计算回复中来源编号的落点——像论文一样插在引用该来源的那句之后。
// 分层：Model；纯文本与 AttributedString 计算，不得 import AppKit/SwiftUI。
import Foundation

/// 回复中来源编号的落点：像论文一样，插在引用该来源的那句之后。
enum ChatCitations {
    /// 一处引用锚点：插入位置、来源编号与来源 URL。
    struct Anchor: Equatable {
        /// 相对绘制文本的字符偏移，标记插入在此处。
        let offset: Int
        let number: Int
        let url: URL
    }

    /// 每个来源每句一个锚点，按阅读顺序排列；同句内两个来源共用句末位置。
    static func anchors(in text: AttributedString, numbers: [String: Int]) -> [Anchor] {
        guard !numbers.isEmpty else { return [] }
        let plain = Array(String(text.characters))
        var anchors: [Anchor] = []
        var seen = Set<[Int]>()
        func add(url: URL, endingAt end: Int) {
            guard let number = numbers[ChatReferences.key(url)] else { return }
            let offset = sentenceEnd(after: end, in: plain)
            guard seen.insert([offset, number]).inserted else { return }
            anchors.append(Anchor(offset: offset, number: number, url: url))
        }
        for run in text.runs {
            guard let url = run.link, url.scheme?.hasPrefix("http") == true else { continue }
            let end = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            add(url: url, endingAt: end)
        }
        let string = String(plain)
        for match in string.matches(of: #/https?://[^\s<>"'`)\]]+/#) {
            let offset = string.distance(from: string.startIndex, to: match.range.lowerBound)
            let start = text.characters.index(text.startIndex, offsetBy: offset)
            // Markdown 链接已包含的 URL 视为通过链接完成引用。
            guard text.runs[start].link == nil else { continue }
            var raw = String(match.output)
            while let last = raw.last, ".,;:!?*_".contains(last) { raw.removeLast() }
            guard let url = URL(string: raw) else { continue }
            add(url: url, endingAt: offset + raw.count)
        }
        return anchors.sorted { ($0.offset, $0.number) < ($1.offset, $1.number) }
    }

    /// `offset` 所在句子的结尾：越过其句末标点，或到达该行/全文末尾。
    static func sentenceEnd(after offset: Int, in plain: [Character]) -> Int {
        var index = offset
        while index < plain.count {
            let character = plain[index]
            if character.isNewline { return index }
            if ".!?".contains(character), index + 1 == plain.count || plain[index + 1].isWhitespace {
                return index + 1
            }
            index += 1
        }
        return plain.count
    }

}
