// 文件职责：将 NoteTextView 封装为 SwiftUI 的 NSViewRepresentable，负责编辑器视图的创建、更新与协调。
// 分层：UI 桥接层；通过 Coordinator 在 AppKit 与 SwiftUI 之间传递状态，不直接持有业务数据。
import AppKit
import SwiftUI

/// SwiftUI 包装的笔记编辑器视图，把文本变更、格式变化和就绪事件回传给上层。
struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    let rendersMarkdown: Bool
    /// 空文本时显示的占位提示，随界面语言变化；缺省时（如测试脚手架）不绘制占位。
    var placeholder: String = ""
    let onSourceChange: (String) -> Void
    let onCharacterCountChange: (NoteEditorInput, Int) -> Void
    let onFormattingChange: (NoteEditorInput, NoteFormatting) -> Void
    let onReady: (NoteTextView) -> Void

    /// 创建并持有该视图的 Coordinator。
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 构建承载 NoteTextView 的滚动视图并完成初始化绑定。
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // `NotesView` 自行布局顶部标题栏区域，因此 AppKit 不得再内缩一次。
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = NoteTextView(usingTextLayoutManager: true)
        Self.configure(textView)
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.editorUndoManager = context.coordinator.editorUndoManager
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.install(input, resetUndo: false)
        onReady(textView)
        return scrollView
    }

    /// 将新的输入与 Markdown 渲染开关同步给底层文本视图。
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(input)
        context.coordinator.setRendersMarkdown(rendersMarkdown)
        context.coordinator.textView?.placeholder = placeholder
        context.coordinator.textView?.needsDisplay = true
    }

    @MainActor
    /// 桥接 NSTextView 事件与 SwiftUI 上层回调的协调器。
    final class Coordinator: NSObject, NSTextViewDelegate, NoteTextViewEditing {
        var parent: NoteEditorView
        weak var textView: NoteTextView? {
            didSet { attach() }
        }
        let editorUndoManager = UndoManager()
        let renderer: NoteMarkdownRenderer
        /// 由测试脚手架替换：只记录链接而不打开浏览器。
        var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

        private var input: NoteEditorInput
        private var isInstalling = false
        /// 仅 init 赋值一次、deinit 读取一次，无并发写；`nonisolated(unsafe)` 绕开 deinit
        /// 的隔离检查（NSObjectProtocol 非 Sendable，无法在 nonisolated deinit 中直接访问）。
        nonisolated(unsafe) private var undoObservers: [NSObjectProtocol] = []
        /// 在此持有，因为布局管理器对 delegate 只做弱引用。
        private let fragmentProvider = NoteLayoutFragmentProvider()

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
            renderer = NoteMarkdownRenderer(isEnabled: parent.rendersMarkdown)
            super.init()
            // 用 `forName` 老 API 而非 26 的 `addObserver(of:for:using:)`：didUndo/didRedo 通知
            // 在两个系统上语义一致，无需维护可用性分支；queue: .main 保证回调在主线程。
            let center = NotificationCenter.default
            undoObservers = [
                center.addObserver(
                    forName: NSNotification.Name.NSUndoManagerDidUndoChange, object: editorUndoManager, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sourceDidChange() }
                },
                center.addObserver(
                    forName: NSNotification.Name.NSUndoManagerDidRedoChange, object: editorUndoManager, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sourceDidChange() }
                }
            ]
        }

        deinit {
            for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        }

        /// 将渲染器、编辑回调与布局代理绑定到新的文本视图。
        private func attach() {
            renderer.textView = textView
            textView?.editing = self
            textView?.textLayoutManager?.delegate = fragmentProvider
        }

        /// 载入指定输入到文本视图，可选择清空撤销栈。
        func install(_ input: NoteEditorInput, resetUndo: Bool) {
            guard let textView else { return }
            let wasEmpty = textView.textStorage?.length == 0
            self.input = input
            let selectionLocation = min(
                textView.selectedRange().location,
                (input.source as NSString).length)
            isInstalling = true
            textView.string = input.source
            if wasEmpty != input.source.isEmpty { textView.needsDisplay = true }
            textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            renderer.reset()
            isInstalling = false
            if resetUndo { editorUndoManager.removeAllActions() }
            reportCharacterCount()
            reportFormatting()
        }

        /// 若输入代表外部权威变更（如切换笔记或重新载入）则重新安装，否则忽略。
        func update(_ next: NoteEditorInput) {
            guard next != input else { return }
            let authoritative =
                next.id != input.id || next.epoch != input.epoch
                || next.source != textView?.string
            input = next
            guard authoritative else { return }
            install(next, resetUndo: true)
        }

        /// 切换 Markdown 渲染开关，并在变化时重置渲染器与格式上报。
        func setRendersMarkdown(_ rendersMarkdown: Bool) {
            guard rendersMarkdown != renderer.isEnabled else { return }
            renderer.isEnabled = rendersMarkdown
            renderer.reset()
            reportFormatting()
        }

        func textDidChange(_ notification: Notification) {
            sourceDidChange()
        }

        /// 将用户编辑产生的源文本变化同步给渲染器与上层。
        private func sourceDidChange() {
            guard !isInstalling, let textView else { return }
            renderer.sourceDidChange()
            reportFormatting()
            let source = textView.string
            guard source != input.source else { return }
            if input.source.isEmpty != source.isEmpty { textView.needsDisplay = true }
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            parent.onSourceChange(source)
            reportCharacterCount()
        }

        /// 选区变化时刷新渲染与格式状态。
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInstalling else { return }
            renderer.selectionDidChange()
            reportFormatting()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any],
            toAttributes newTypingAttributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            renderer.isEnabled ? NoteMarkdownStyler.literal : newTypingAttributes
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = link as? URL ?? (link as? String).flatMap { URL(string: $0) }
            guard let url, let scheme = url.scheme?.lowercased(),
                NoteMarkdownStyler.openableSchemes.contains(scheme)
            else {
                return true
            }
            if let noteView = textView as? NoteTextView, let event = NSApp.currentEvent,
                let edge = noteView.linkEdge(
                    ofLinkAt: charIndex, clickedAt: noteView.containerPoint(for: event))
            {
                textView.setSelectedRange(NSRange(location: edge, length: 0))
                return true
            }
            openURL(url)
            return true
        }

        var rendersMarkdown: Bool { renderer.isEnabled }

        var markdown: NoteMarkdown { renderer.syncedMarkdown() }

        func focusChanged() {
            renderer.selectionDidChange()
        }

        func appearanceChanged() {
            renderer.reset()
        }

        func dragSelectionEnded() {
            renderer.selectionDidChange()
        }

        /// `NSTextStorage.length` 由 TextKit 维护，因此统计字数无需逐次编辑开销。
        private func reportCharacterCount() {
            parent.onCharacterCountChange(input, textView?.textStorage?.length ?? 0)
        }

        /// 关闭渲染时无解析结果可读，且格式栏本就隐藏。
        private func reportFormatting() {
            guard let textView else { return }
            let formatting =
                renderer.isEnabled
                ? NoteMarkdownEditing.formatting(
                    source: textView.string, selection: textView.selectedRange(), markdown: markdown)
                : .plain
            parent.onFormattingChange(input, formatting)
        }
    }

    /// 配置文本视图的通用行为与外观（富文本、滚动、插入点、撤销等）。
    static func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(
            width: Theme.Size.noteEditorInset,
            height: Theme.Size.noteEditorTopInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NoteMarkdownTypography.body
        textView.textColor = NSColor(Theme.Colors.noteText)
        textView.insertionPointColor = NSColor(Theme.Colors.noteText)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.Colors.selection),
            .foregroundColor: NSColor(Theme.Colors.noteText)
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        textView.typingAttributes = NoteMarkdownStyler.literal
    }
}
