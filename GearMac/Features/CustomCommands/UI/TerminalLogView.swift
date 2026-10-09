// 文件职责：命令输出的终端日志视图：用 NSTextView 增量追加日志，并解析 ANSI 控制序列以渲染颜色与覆盖行。
// 分层：UI；内部区分「流式追加」与「整体重绘」两种更新路径，日志被裁剪时整体重绘。
import AppKit
import SwiftUI

/// 使用 `NSTextView` 而非 `Text`：只有文本系统能在追加时不重新排版。
struct TerminalLogView: NSViewRepresentable {
    let run: CommandRun

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let inset = CGSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xs)
    /// 距底部在此范围内即视为跟随滚动，与聊天记录的判定带一致。
    private static let tailSlack = Theme.Spacing.chatFollowTailSlack

    /// 创建协调器，用于在多次更新间保留渲染状态。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 存放跨次更新状态的协调器。
    final class Coordinator {
        /// 新一次运行或日志被裁剪都会让已绘制文本失配，而这在 revision 上不可见。
        var runID: UUID?
        var generation = -1
        var revision = 0
        var interpreter = ANSIInterpreter()
    }

    /// 构建只读、无背景的滚动文本视图。
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        // 置零后左边界仅由 inset 决定，使日志与头部文字对齐。
        textView.textContainer?.lineFragmentPadding = 0
        return scrollView
    }

    /// 根据运行状态选择追加或整体重绘，并在原本跟随底部时继续跟随。
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }
        let coordinator = context.coordinator
        let following = isAtBottom(scrollView)

        let isSameRun = coordinator.runID == run.id && coordinator.generation == run.generation
        guard !isSameRun || run.revision != coordinator.revision else { return }

        // 只前进一步表示流式追加，代价仅为新增文本；其余情况都整体重绘。
        let isAppend = isSameRun && run.revision == coordinator.revision + 1
        if !isAppend {
            coordinator.interpreter = ANSIInterpreter()
            storage.setAttributedString(NSAttributedString())
        }
        coordinator.runID = run.id
        coordinator.generation = run.generation
        coordinator.revision = run.revision
        coordinator.interpreter.render(isAppend ? run.delta : run.log, into: storage, font: Self.font)
        if following { textView.scrollToEndOfDocument(nil) }
    }

    /// 已经向上滚动的读者不被打扰；重新回到末尾时恢复跟随。
    private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        return visible.maxY >= documentView.frame.height - Self.tailSlack
    }
}

/// 解析 ANSI 序列：跨块的 SGR 颜色被保留，回车符回退当前行，其余序列一律丢弃。
struct ANSIInterpreter {
    private var colour: NSColor = .labelColor
    private var isBold = false
    private var isDim = false
    /// 控制序列可能被拆到多次读取中，未完整的部分先留待后续拼接。
    private var partial = ""

    /// 解析文本中的 ANSI 序列，并按当前样式渲染进文本存储。
    mutating func render(_ text: String, into storage: NSTextStorage, font: NSFont) {
        var run = ""
        var characters = Array(partial + text)[...]
        partial = ""

        func flush() {
            guard !run.isEmpty else { return }
            storage.append(NSAttributedString(string: run, attributes: attributes(font)))
            run = ""
        }

        while let character = characters.first {
            characters = characters.dropFirst()
            switch character {
            case "\u{1B}":
                guard let sequence = Self.take(&characters) else {
                    // 序列被截断：先保留下来，而不是把转义符原样打印出来。
                    partial = "\u{1B}" + String(characters)
                    characters = characters.prefix(0)
                    continue
                }
                flush()
                apply(sequence)
            case "\r":
                // 进度条是在原行位置重绘；若逐帧追加会把所有帧堆叠起来。
                flush()
                rewindLine(in: storage)
            default:
                run.append(character)
            }
        }
        flush()
    }

    /// 依据当前粗体/暗淡状态生成文本属性。
    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        let face = isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        return [.font: face, .foregroundColor: isDim ? colour.withAlphaComponent(0.6) : colour]
    }

    /// 读取一段 CSI/OSC 序列体；序列尚未完整到达时返回 nil。
    private static func take(_ characters: inout ArraySlice<Character>) -> String? {
        guard let introducer = characters.first else { return nil }
        characters = characters.dropFirst()
        guard introducer == "[" else {
            // OSC 及其他序列在这里没有意义；一路吞到其终止符为止。
            while let character = characters.first, character != "\u{07}", character != "\u{1B}" {
                characters = characters.dropFirst()
            }
            return ""
        }
        var body = ""
        while let character = characters.first {
            characters = characters.dropFirst()
            body.append(character)
            if character.isLetter { return body }
        }
        return nil
    }

    /// 应用一段以 `m` 结尾的 SGR 序列（其他序列不产生视觉效果）。
    private mutating func apply(_ sequence: String) {
        // 只渲染 SGR；在文档中光标移动与擦除都无意义。
        guard sequence.hasSuffix("m") else { return }
        let codes = sequence.dropLast().split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var index = 0
        while index < max(codes.count, 1) {
            let code = codes.isEmpty ? 0 : codes[index]
            switch code {
            case 0: colour = .labelColor; isBold = false; isDim = false
            case 1: isBold = true
            case 2: isDim = true
            case 22: isBold = false; isDim = false
            case 30...37: colour = Self.palette[code - 30]
            case 90...97: colour = Self.palette[code - 90]
            case 39: colour = .labelColor
            // 扩展颜色自带参数；跳过它们才能让后续参数对位正确。
            case 38, 48: index += codes.count > index + 1 && codes[index + 1] == 5 ? 2 : 4
            default: break
            }
            index += 1
        }
    }

    /// 删除至最后一行的行首，这正是单独一个回车符的含义。
    private func rewindLine(in storage: NSTextStorage) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let lineStart = text.range(
            of: "\n", options: .backwards, range: NSRange(location: 0, length: text.length))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        guard start < text.length else { return }
        storage.deleteCharacters(in: NSRange(location: start, length: text.length - start))
    }

    /// 使用系统颜色，使日志在浅色与深色外观下都可读；黄色以橙色替代。
    private static let palette: [NSColor] = [
        .secondaryLabelColor, .systemRed, .systemGreen, .systemOrange,
        .systemBlue, .systemPurple, .systemTeal, .labelColor
    ]
}
