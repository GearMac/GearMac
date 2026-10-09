// 文件职责：定义词典查询结果的数据模型，把释义拆分为辞典页面的区块（词头、词性、义项、注记、段落等）。
// 分层：Model；纯值类型，不依赖 AppKit/SwiftUI，也不做网络或磁盘访问。
import Foundation

/// 一次查询的词条，按辞典页面的阅读顺序排列为多个区块。
struct DictionaryEntry: Equatable, Identifiable, Sendable {
    let term: String
    let blocks: [Block]

    var id: String { term }

    /// 词条页面中的一个区块。
    enum Block: Equatable, Sendable {
        case headword(String, homograph: String?, pronunciation: String?)
        /// 词性及其变形：`noun (plural mangoes)`。
        case partOfSpeech([Run])
        /// 带编号的义项；若单词只有一个含义则不编号。
        case sense(number: String?, [Run])
        /// 上一义项下以 `•` 标出的细分义项。
        case subsense([Run])
        /// 科学或用法上的旁注，与它紧随的定义分开排版。
        case note([Run])
        /// 义项之后的带标题部分：`ORIGIN`、`PHRASES`、`DERIVATIVES`。
        case section(String)
        /// 段落内部的短语或派生词标题。
        case phrase([Run])
        case paragraph([Run])
    }

    /// 一段带有排版样式的文本。
    struct Run: Equatable, Sendable {
        var text: String
        let style: Style
    }

    /// 文本片段的排版样式。
    enum Style: Equatable, Sendable {
        case plain
        case example
        /// 语法、语域与地区标签：`[with object]`、`informal`。
        case label
        /// 词条列举的形式：屈折变化、异体、短语。
        case strong
        /// 分类学或外来词。
        case italic
    }

    /// 拷贝时携带的文本：每个区块一行，使粘贴结果保留页面的行结构。
    var text: String {
        blocks.map(\.text).joined(separator: "\n")
    }
}

extension DictionaryEntry {
    /// 从公开 API 的纯文本构造：`headword | pronunciation | body`，多个义项以 `•` 分隔。
    init(term: String, plainText: String) {
        let pipes = plainText.ranges(of: "|").prefix(2)
        var pronunciation: String?
        var body = plainText[...]
        if pipes.count == 2 {
            let spoken = plainText[pipes[0].upperBound..<pipes[1].lowerBound]
                .trimmingCharacters(in: .whitespaces)
            pronunciation = spoken.isEmpty ? nil : spoken
            body = plainText[pipes[1].upperBound...]
        }
        let senses = body.split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Block.paragraph([Run(text: $0, style: .plain)]) }
        self.init(
            term: term,
            blocks: [.headword(term, homograph: nil, pronunciation: pronunciation)] + senses)
    }
}

extension DictionaryEntry.Block {
    /// 该区块的纯文本形式，供拼接与拷贝使用。
    var text: String {
        switch self {
        case .headword(let word, let homograph, let pronunciation):
            return [word, homograph, pronunciation.map { "| \($0) |" }]
                .compactMap { $0 }.joined(separator: " ")
        case .sense(let number, let runs):
            return [number, runs.text].compactMap { $0 }.joined(separator: " ")
        case .subsense(let runs): return "• " + runs.text
        case .section(let title): return "\n" + title
        case .partOfSpeech(let runs), .note(let runs), .phrase(let runs), .paragraph(let runs):
            return runs.text
        }
    }
}

extension [DictionaryEntry.Run] {
    /// 把多个片段拼成连续文本。
    var text: String { map(\.text).joined() }
}
