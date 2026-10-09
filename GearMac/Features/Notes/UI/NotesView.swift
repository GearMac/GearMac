// 文件职责：实现笔记面板的主视图：自定义标题栏、编辑器区域、底栏与空状态。
// 分层：UI 视图层；通过 NotesCoordinator 环境对象读取当前笔记与编辑状态。
import SwiftUI

/// 笔记面板的主视图。
struct NotesView: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings

    /// 标题栏与内容区域的竖向组合，并绑定格式栏显隐联动。
    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // 上方区域即为标题栏；AppKit 不得再对内容做一次内缩。
        .ignoresSafeArea()
        .onChange(of: notes.showsFormattingBar && notes.hasActiveNote) { _, shown in
            if !shown { notes.closeHeadingMenu() }
        }
    }

    /// 宿主视图隐藏了真正的标题栏，因此这条区域自行负责拖动窗口。
    private var titleBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .overlay { NoteTitlebarDragRegion(onDoubleClick: notes.moveToTopRight) }
            NoteTitlebarActions()
        }
        .frame(height: Theme.Size.noteTitlebar)
        .overlay { title }
    }

    /// 居中显示的当前笔记标题。
    private var title: some View {
        Text(notes.hasActiveNote ? notes.activeTitle : settings.text(NotesKey.windowTitle))
            .font(Theme.Typography.noteTitle)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Size.noteTitleInset)
            .allowsHitTesting(false)
    }

    /// 有活动笔记时显示编辑器，否则显示空状态。
    @ViewBuilder
    private var content: some View {
        if notes.hasActiveNote {
            editorSurface
        } else {
            emptyState
        }
    }

    /// 编辑器及其底部格式栏或页脚的组合。
    private var editorSurface: some View {
        VStack(spacing: 0) {
            NoteEditorView(
                input: notes.editorInput,
                rendersMarkdown: notes.rendersMarkdown,
                placeholder: settings.text(NotesKey.editorPlaceholder),
                onSourceChange: notes.updateSource,
                onCharacterCountChange: notes.updateCharacterCount,
                onFormattingChange: notes.updateFormatting,
                onReady: notes.editorReady
            )
            if notes.showsFormattingBar {
                formattingBand
            } else {
                footer
            }
        }
    }

    /// 字数统计会优先隐藏，而该区域保留既定宽度，使格式栏永远不会把笔记撑宽。
    private var formattingBand: some View {
        HStack(spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                characterCount
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NoteFormattingBar()
                .fixedSize()
        }
        .padding(.leading, Theme.Size.noteEditorInset)
        .padding(.trailing, Theme.Spacing.md)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        .frame(height: Theme.Size.bottomBarHeight)
    }

    /// 无活动笔记时显示的空状态与创建入口。
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "text.page", size: Theme.Size.noteEmptyGlyph)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(settings.text(NotesKey.emptyTitle))
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(settings.text(NotesKey.actionCreate), action: notes.createNote)
                .buttonStyle(.plain)
                .font(Theme.Typography.bar)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.barButtonHeight)
                .frosted(in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 未展开格式栏时显示的底部页脚（仅字数统计）。
    private var footer: some View {
        characterCount
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteFooterHeight)
    }

    /// 当前笔记的字数标签。
    private var characterCount: some View {
        Text(notes.characterCountLabel)
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
            .accessibilityLabel(
                String(
                    format: settings.text(NotesKey.characterCountAccessibility),
                    notes.characterCountLabel))
    }
}

/// 将标题栏拖动区域封装为 SwiftUI 视图。
private struct NoteTitlebarDragRegion: NSViewRepresentable {
    let onDoubleClick: () -> Void

    /// 创建拖动视图并绑定双击回调。
    func makeNSView(context: Context) -> NoteTitlebarDragView {
        let view = NoteTitlebarDragView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    /// 同步双击回调到已有视图。
    func updateNSView(_ view: NoteTitlebarDragView, context: Context) {
        view.onDoubleClick = onDoubleClick
    }
}

/// 处理标题栏拖动与双击的 AppKit 视图。
private final class NoteTitlebarDragView: NSView {
    var onDoubleClick: (() -> Void)?

    /// 双击时触发回调，否则拖动窗口。
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }
}

/// 标题栏尾部的控制按钮：沿用启动器页脚胶囊的样式，但以图标代替文字按钮。
private struct NoteTitlebarActions: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            action(
                "plus", settings.text(NotesKey.actionCreate),
                settings.text(NotesKey.actionCreateHelp), notes.createNote)
            action(
                "rectangle.stack", settings.text(NotesKey.actionBrowse),
                settings.text(NotesKey.actionBrowseHelp), notes.searchNotes)
            action(
                "folder", settings.text(NotesKey.actionOpenFolder),
                settings.text(NotesKey.actionOpenFolderHelp), notes.openNotesFolder)
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
        .padding(.trailing, Theme.Spacing.md)
    }

    /// 构建一个标题栏图标按钮。
    private func action(
        _ symbol: String,
        _ label: String,
        _ help: String,
        _ perform: @escaping () -> Void
    ) -> some View {
        BarButton(action: perform) {
            SymbolImage(name: symbol, size: Theme.Size.noteGlyph)
        }
        .accessibilityLabel(label)
        .help(help)
    }
}
