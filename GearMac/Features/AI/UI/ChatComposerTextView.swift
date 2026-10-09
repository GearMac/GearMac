// 文件职责：窗口输入框的 AppKit 文本视图（NSViewRepresentable）及其拖放、焦点与高度自适应逻辑。
// 分层：UI（AppKit + SwiftUI 桥接）；不直接发起网络/持久化，仅通过闭包把事件交给上层。
import AppKit
import SwiftUI

/// 窗口的输入框：回车发送，⇧↩ 与 ⌥↩ 换行，输入框高度增长直到上限。
struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    /// 值变化会把焦点拉进输入框：切换会话就意味着你马上要开始输入。
    let focusKey: UUID
    let maximumTextHeight: CGFloat
    let handle: ComposerTextViewHandle
    @Binding var isFileDragTargeted: Bool
    let onDropFiles: ([URL]) -> Void
    let onInvalidate: (ComposerTextView) -> Void
    let onSubmit: () -> Void

    private static var font: NSFont { .preferredFont(forTextStyle: .body) }

    /// 单行行高（向上取整），供高度计算与测量使用。
    static var lineHeight: CGFloat {
        (font.ascender - font.descender + font.leading).rounded(.up)
    }

    /// 依据可用高度算出输入框的最大高度：按可用高度比例取行数，并夹在最大行数内。
    static func maximumHeight(in availableHeight: CGFloat) -> CGFloat {
        let lines = (availableHeight * Theme.Size.aiChatComposerHeightFraction / lineHeight).rounded(.down)
        return max(1, min(Theme.Size.aiChatComposerMaxLines, lines)) * lineHeight
    }

    /// 按给定宽度测量文本高度，并夹在单行行高与最大高度之间。
    static func textHeight(_ text: String, width: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let measured = (text.hasSuffix("\n") ? text + " " : text) as NSString
        let height = measured.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height.rounded(.up)
        return min(max(lineHeight, height), maximumHeight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onInvalidate: onInvalidate, onSubmit: onSubmit)
    }

    /// 创建可滚动的 ComposerTextView，并配置为纯文本、可撤销、可拖入文件。
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ComposerTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? ComposerTextView else { return scroll }
        handle.textView = textView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setAccessibilityLabel("Message")
        return scroll
    }

    /// 同步回调与外部文本，并在 focusKey 变化时把焦点移入输入框。
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? ComposerTextView else { return }
        if context.coordinator.focusedKey != focusKey { onInvalidate(textView) }
        context.coordinator.text = $text
        context.coordinator.onInvalidate = onInvalidate
        context.coordinator.onSubmit = onSubmit
        textView.onDropFiles = onDropFiles
        textView.onFileDragTargeted = { [$isFileDragTargeted] in $isFileDragTargeted.wrappedValue = $0 }
        // 只有来自外部的写入会在此落地；把视图自身的文本回写会重置光标位置。
        if textView.string != text { textView.string = text }
        guard context.coordinator.focusedKey != focusKey else { return }
        context.coordinator.focusedKey = focusKey
        // 延到下一轮：首次挂载时视图还没有窗口，无法成为第一响应者。
        Task { @MainActor [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    /// 拆解时通知失效并解除 delegate 与拖放回调，避免悬空引用。
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let textView = scroll.documentView as? ComposerTextView else { return }
        coordinator.onInvalidate(textView)
        textView.isEditable = false
        textView.delegate = nil
        textView.onDropFiles = nil
        textView.onFileDragTargeted = nil
    }

    /// 根据文本而非 text view 来测量，因为 text view 的宽度会比提案晚一个布局周期才更新。
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSScrollView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(
            width: width,
            height: Self.textHeight(text, width: width, maximumHeight: maximumTextHeight))
    }

    /// 桥接 NSTextView 的代理回调：文本变化回写绑定，回车触发提交。
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onInvalidate: (ComposerTextView) -> Void
        var onSubmit: () -> Void
        var focusedKey: UUID?

        init(
            text: Binding<String>, onInvalidate: @escaping (ComposerTextView) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.onInvalidate = onInvalidate
            self.onSubmit = onSubmit
        }

        /// 把 text view 的当前文本回写到绑定。
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// 输入法组合过程中不会被调用，因此回车确认输入法候选文本的行为仍归输入法自己处理。
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit()
            }
            return true
        }
    }
}

/// GearMac 自有的编辑器，使听写、代码片段与 Quick Actions 能在同一进程内写入它。
final class ComposerTextView: NSTextView, InjectableTextView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragTargeted: ((Bool) -> Void)?

    /// 拖入的文件会被作为附件处理（与面板其他区域一致），而不是让 text view 输入它的路径。
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard carriesFiles(sender) else { return super.draggingEntered(sender) }
        onFileDragTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        carriesFiles(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDragTargeted?(false)
        super.draggingExited(sender)
    }

    /// 拖放结束时把文件交给上层处理并结束拖拽高亮。
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let files = PasteboardFiles.urls(on: sender.draggingPasteboard)
        guard !files.isEmpty, let onDropFiles else { return super.performDragOperation(sender) }
        onFileDragTargeted?(false)
        onDropFiles(files)
        return true
    }

    /// 判断拖拽内容是否包含可读取的文件 URL。
    private func carriesFiles(_ sender: any NSDraggingInfo) -> Bool {
        onDropFiles != nil
            && sender.draggingPasteboard.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
}

/// 说明输入框旁的控制如何拿到 representable 创建的那个 text view。
@MainActor
final class ComposerTextViewHandle {
    weak var textView: ComposerTextView?
}
