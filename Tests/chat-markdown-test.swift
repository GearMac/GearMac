// 文件职责：聊天区可选文本的渲染测试 harness，校验 Markdown 渲染、find 高亮、引用编号、公式排版与链接白名单。
// 分层：测试 harness；引入 AppKit / SwiftUI 与真实 ChatMarkdownRenderer、ChatFindIndex、MathLayoutEngine 等，断言失败时以非零退出码结束。
import AppKit
import SwiftUI

/// 聊天区的可选文本：一条 attributed string，其 find 标记落在索引声明的位置上。
@main
@MainActor
struct ChatMarkdownTests {
    static var failures = 0
    static var passes = 0

    /// 布尔断言辅助：条件成立则通过数加一。
    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 覆盖标题、列表、代码块、表格、引用与公式的固定回复文本。
    static let reply = """
        # Apple notes

        An apple a day, says [the guide](https://example.com/guide). Another apple follows.

        - First apple
          - Nested apple
        - Second item

        3. Numbered apple

        > Quoted apple

        ```swift
        let apple = 1
        ```

        | Fruit | Apple? |
        | - | - |
        | One | apple |
        | Two | apple |

        ## Second section

        A final paragraph.
        """

    /// 测试入口：依次运行全部用例，打印通过/失败数，失败时以退出码 1 结束。
    static func main() {
        everyMatchLandsOnItsWord()
        textReadsAsTheReplyDoes()
        onlyWebAndMailLinksOpen()
        formulasAreOneCharacterEach()
        findSkipsFormulasButLandsAroundThem()
        formulasTypesetByTheirStructure()
        wideFormulasShrinkToTheLine()
        equationsStillArrivingHoldTheirPlace()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 把一条聊天消息渲染为可选文本，可指定当前 find 命中项与引用编号映射。
    static func render(
        _ message: ChatMessage, current: ChatFindOccurrence?, citations: [String: Int] = [:]
    ) -> ChatRenderedText {
        guard case .text(let text)? = message.segments.first else { fatalError("a text segment") }
        return ChatMarkdownRenderer(
            ChatMarkdownSource(
                blocks: MarkdownBlock.parse(text, midStream: message.isArriving(segmentAt: 0, of: 1)),
                highlight: ChatTextHighlight(query: "apple", current: current),
                citations: citations, prefix: [0], failed: false, metrics: .standard)
        ).render()
    }

    /// 索引给出的路径就是渲染器逐叶构建的那些路径。
    static func everyMatchLandsOnItsWord() {
        let message = ChatMessage(role: .assistant, text: reply)
        let found = ChatFindIndex.occurrences(of: "apple", in: [message])
        expect(found.count == 11, "every apple in the reply is a stop of its own, got \(found.count)")
        let citations = ["https://example.com/guide": 1]
        for occurrence in found {
            let rendered = render(message, current: occurrence, citations: citations)
            guard let range = rendered.current else {
                expect(false, "the match at \(occurrence.leaf) #\(occurrence.index) is drawn as current")
                continue
            }
            let word = (rendered.string.string as NSString).substring(with: range)
            expect(
                word.lowercased() == "apple",
                "the current mark at \(occurrence.leaf) #\(occurrence.index) sits on its word, got \(word)")
        }
        let marks = render(message, current: nil)
        var tinted = 0
        marks.string.enumerateAttribute(
            .backgroundColor, in: NSRange(location: 0, length: marks.string.length)
        ) { value, range, _ in
            let word = (marks.string.string as NSString).substring(with: range)
            if value != nil, word.lowercased() == "apple" {
                tinted += 1
            }
        }
        expect(tinted == found.count, "every match takes the find tint, got \(tinted) of \(found.count)")
    }

    /// 渲染出的纯文本与回复原文的读法一致。
    static func textReadsAsTheReplyDoes() {
        let rendered = render(
            ChatMessage(role: .assistant, text: reply), current: nil,
            citations: ["https://example.com/guide": 1])
        let text = rendered.string.string
        expect(text.hasPrefix("Apple notes\n"), "a heading is its own line")
        expect(text.contains("Second section\nA final paragraph"), "both sections share one rendered string")
        expect(
            text.contains("says the guide. [1]Another") || text.contains("says the guide.[1] Another"),
            "the citation closes the sentence that cited it: \(text.debugDescription)")
        expect(
            text.contains("•\tFirst apple\n•\tNested apple"), "bullets read as bullets, nested ones too")
        expect(text.contains("3.\tNumbered apple"), "a numbered list keeps its own start")
        expect(text.contains("let apple = 1"), "code is part of the selectable text")
        expect(!text.hasSuffix("\n"), "no empty line is left under the reply")
        expect(
            rendered.codeBlocks.map(\.code) == ["let apple = 1"]
                && rendered.codeBlocks.first?.language == "swift",
            "each code block is known, for its Copy button")
    }

    /// 收集指定 attributed string 中的所有附件（公式）及其单元格。
    static func attachments(in string: NSAttributedString) -> [(range: NSRange, cell: NSTextAttachmentCell?)]
    {
        var found: [(NSRange, NSTextAttachmentCell?)] = []
        let whole = NSRange(location: 0, length: string.length)
        string.enumerateAttribute(.attachment, in: whole) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            found.append((range, attachment.attachmentCell as? NSTextAttachmentCell))
        }
        return found
    }

    /// 每个公式都是一个附件字符，并携带复制时还原的源文本。
    static func formulasAreOneCharacterEach() {
        let text = "Roots \\(x^2\\) and $y$.\n\n$$\\frac{a}{b}$$\n\nAt $5 or $10, $\\foo$."
        let rendered = render(ChatMessage(role: .assistant, text: text), current: nil).string
        let found = attachments(in: rendered)
        expect(found.count == 3, "two inline formulas and one display formula, got \(found.count)")
        expect(
            found.allSatisfy { $0.range.length == 1 && $0.cell is MathAttachmentCell }, "each draws one cell")
        expect(
            found.map { $0.cell?.accessibilityRole() } == Array(repeating: .image, count: found.count)
                && found.first?.cell?.accessibilityLabel() == "\\(x^2\\)",
            "VoiceOver meets each formula as an image named by its source")
        let sources = found.map {
            rendered.attribute(ChatMarkdownRenderer.mathSource, at: $0.range.location, effectiveRange: nil)
                as? String
        }
        expect(
            sources == ["\\(x^2\\)", "$y$", "$$\\frac{a}{b}$$"],
            "each formula carries its source as written, got \(sources)")
        let plain = rendered.string
        expect(
            plain.contains("At $5 or $10, $\\foo$."),
            "prices and a formula outside the subset read as the reply wrote them")
        let display = found[2].range.location
        let style = rendered.attribute(.paragraphStyle, at: display, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.alignment == .center, "a display formula is centred on its own line")
    }

    /// find 跳过公式源码，但能正确落在公式前后的词上。
    static func findSkipsFormulasButLandsAroundThem() {
        let message = ChatMessage(
            role: .assistant, text: "An apple $\\alpha_{apple}$ then apple \\(x\\) apple.")
        let found = ChatFindIndex.occurrences(of: "apple", in: [message])
        expect(found.count == 3, "the formula's source is not searched, got \(found.count)")
        for occurrence in found {
            guard let range = render(message, current: occurrence).current else {
                expect(false, "match \(occurrence.index) is drawn")
                continue
            }
            let rendered = render(message, current: occurrence).string.string as NSString
            expect(
                rendered.substring(with: range).lowercased() == "apple",
                "match \(occurrence.index) lands on its word past the formulas")
        }
    }

    /// 公式按自身结构排版：分式、上标、围栏与空格各自产生预期尺寸。
    static func formulasTypesetByTheirStructure() {
        guard let engine = MathLayoutEngine(size: 20),
            let fraction = MathFormula(tex: #"\frac{a}{b}"#, source: "", display: true),
            let letter = MathFormula(tex: "a", source: "", display: true),
            let squared = MathFormula(tex: "a^2", source: "", display: false),
            let fenced = MathFormula(
                tex: #"\left( \frac{\frac{a}{b}}{c} \right)"#, source: "", display: true),
            let spaced = MathFormula(tex: "a+b", source: "", display: false),
            let unary = MathFormula(tex: "-b", source: "", display: false)
        else {
            expect(false, "STIX Two Math and the formulas load")
            return
        }
        let a = engine.layout(letter)
        let over = engine.layout(fraction)
        expect(
            over.ascent > a.ascent && over.descent > a.descent, "a fraction stands above and below the line")
        let power = engine.layout(squared)
        expect(power.ascent > a.ascent && power.width > a.width, "a superscript rides up and to the right")
        let parens = engine.layout(fenced)
        expect(parens.height > engine.layout(fraction).height, "\\left( grows to hold what it fences")
        expect(
            engine.layout(spaced).width > engine.layout(unary).width,
            "a binary plus takes medium spaces, a leading minus none")
        expect(
            MathFormula(tex: #"\left( a \\ b \right)"#, source: "", display: true) == nil,
            "a row break inside \\left is refused rather than half-drawn")
    }

    /// Quick AI 的窄列会把长公式缩小，而不是让它溢出边缘。
    static func wideFormulasShrinkToTheLine() {
        guard let engine = MathLayoutEngine(size: 20),
            let formula = MathFormula(
                tex: String(repeating: "a + ", count: 40) + "a", source: "", display: true)
        else {
            expect(false, "a long formula typesets")
            return
        }
        let box = engine.layout(formula)
        let cell = MathAttachmentCell(box: box, color: .labelColor, label: "")
        let container = NSTextContainer(size: CGSize(width: 200, height: 1000))
        container.lineFragmentPadding = 0
        let frame = cell.cellFrame(
            for: container, proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 20),
            glyphPosition: .zero, characterIndex: 0)
        expect(
            box.width > 200 && abs(frame.width - 200) < 0.5, "the formula fits the line, got \(frame.width)")
        expect(
            abs(frame.height / frame.width - box.height / box.width) < 0.001, "it shrinks without distorting")
    }

    /// 流式输出中：未完成的块级公式画居中占位符，行内公式则先不显示。
    static func equationsStillArrivingHoldTheirPlace() {
        let text = "An apple \\(y\\) then apple.\n\n$$\n\\frac{apple}{b"
        let streaming = ChatMessage(role: .assistant, text: text, state: .streaming)
        let rendered = render(streaming, current: nil).string
        expect(
            rendered.string.hasSuffix("then apple.\n…") && !rendered.string.contains("frac"),
            "the unfinished equation draws as a placeholder, got \(rendered.string.debugDescription)")
        let dots = (rendered.string as NSString).range(of: "…")
        let style =
            rendered.attribute(.paragraphStyle, at: dots.location, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.alignment == .center, "the placeholder sits where the equation will, centred")
        let found = ChatFindIndex.occurrences(of: "apple", in: [streaming])
        expect(found.count == 2, "find sees what is drawn mid-stream, got \(found.count)")
        for occurrence in found {
            let drawn = render(streaming, current: occurrence)
            guard let range = drawn.current else {
                expect(false, "match \(occurrence.index) is drawn mid-stream")
                continue
            }
            expect(
                (drawn.string.string as NSString).substring(with: range).lowercased() == "apple",
                "match \(occurrence.index) lands on its word mid-stream")
        }
        let inline = render(
            ChatMessage(role: .assistant, text: "Roots are \\(x = \\frac{1}{", state: .streaming),
            current: nil)
        expect(inline.string.string == "Roots are ", "an inline equation still arriving is withheld")
    }

    /// 回复不可信：对 `file:` 或 App scheme 链接的一次点击不得启动任何东西。
    static func onlyWebAndMailLinksOpen() {
        let text = """
            [web](https://example.com) [mail](mailto:a@example.com) \
            [file](file:///Applications/Calculator.app) [app](x-apple.systempreferences:security)
            """
        let rendered = render(ChatMessage(role: .assistant, text: text), current: nil).string
        var links: [String] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let url = value as? URL { links.append(url.absoluteString) }
        }
        expect(
            links == ["https://example.com", "mailto:a@example.com"],
            "only web and mail links stay clickable, got \(links)")
    }
}
