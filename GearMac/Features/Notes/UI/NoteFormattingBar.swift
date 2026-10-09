// 文件职责：实现笔记编辑器的底部格式工具条，为各项 Markdown 编辑操作提供按钮。
// 分层：UI 视图层；通过 NotesCoordinator 环境对象触发格式操作，不直接修改文本。
import SwiftUI

/// 标题栏胶囊底部的工具条，每个按钮对应一种 Markdown 编辑操作。
struct NoteFormattingBar: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings

    /// 单个格式按钮的描述：图标、本地化键、快捷键、动作与高亮判定。
    private struct Control: Sendable {
        let symbol: String
        let key: NotesKey
        let shortcut: String
        let action: NoteEditAction
        let isLit: @Sendable (NoteFormatting) -> Bool
    }

    private static let styles = [
        Control(symbol: "bold", key: .formatBold, shortcut: "⌘B", action: .toggleInline(.bold)) {
            $0.inlineStyles.contains(.bold)
        },
        Control(symbol: "italic", key: .formatItalic, shortcut: "⌘I", action: .toggleInline(.italic)) {
            $0.inlineStyles.contains(.italic)
        },
        Control(
            symbol: "strikethrough", key: .formatStrikethrough, shortcut: "⇧⌘X",
            action: .toggleInline(.strikethrough)
        ) { $0.inlineStyles.contains(.strikethrough) },
        Control(
            symbol: "chevron.left.forwardslash.chevron.right", key: .formatInlineCode, shortcut: "⌘E",
            action: .toggleInline(.code)
        ) { $0.inlineStyles.contains(.code) },
        Control(symbol: "link", key: .formatLink, shortcut: "⌘K", action: .toggleLink) { $0.isLink }
    ]

    private static let blocks = [
        Control(
            symbol: "curlybraces", key: .formatCodeBlock, shortcut: "⌥⌘C", action: .toggleCodeBlock
        ) {
            $0.isCodeBlock
        },
        Control(symbol: "text.quote", key: .formatQuote, shortcut: "⇧⌘B", action: .toggleQuote) {
            $0.isQuote
        }
    ]

    private static let lists = [
        Control(
            symbol: "list.number", key: .formatNumberedList, shortcut: "⇧⌘7",
            action: .toggleList(.ordered)
        ) {
            $0.list == .ordered
        },
        Control(
            symbol: "list.bullet", key: .formatBulletList, shortcut: "⇧⌘8", action: .toggleList(.bullet)
        ) {
            $0.list == .bullet
        },
        Control(symbol: "checklist", key: .formatTaskList, shortcut: "⇧⌘9", action: .toggleList(.task)) {
            $0.list == .task
        }
    ]

    var body: some View {
        let formatting = notes.formatting
        let isExpanded = notes.isFormattingBarExpanded
        HStack(spacing: Theme.Spacing.sm) {
            if isExpanded {
                HStack(spacing: Theme.Spacing.sm) {
                    NoteHeadingButton(
                        level: formatting.headingLevel, isOpen: notes.isHeadingMenuPresented,
                        action: notes.toggleHeadingMenu
                    ) { notes.headingButtonFrame = $0 }
                    group(Self.styles, formatting)
                    group(Self.blocks, formatting)
                    group(Self.lists, formatting)
                }
                // 从圆形按钮处展开；内容不会超出胶囊，因此无需裁剪。
                .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            NoteFormattingToggle(isExpanded: isExpanded, action: notes.toggleFormattingBar)
                // 绘制在按钮上方，因此它们从其后方向外展开。
                .zIndex(1)
        }
        .padding(Theme.Spacing.xs)
        // 在按钮背后而非周围：毛玻璃会裁剪内容，而悬浮提示绘制在它之外。
        .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.text(NotesKey.formatAccessibility))
    }

    /// 渲染一组按钮，并根据当前格式状态决定是否高亮。
    private func group(_ controls: [Control], _ formatting: NoteFormatting) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(controls, id: \.key) { control in
                let lit = control.isLit(formatting)
                BarButton(isSelected: lit, isCompact: true, action: { notes.format(control.action) }) {
                    NoteBarGlyph(name: control.symbol)
                }
                .focusable(false)
                .accessibilityLabel(settings.text(control.key))
                .accessibilityAddTraits(lit ? .isSelected : [])
                .tooltip("\(settings.text(control.key))  \(control.shortcut)")
            }
        }
    }
}

/// 工具条的把手：一个圆形按钮，用于展开和收起其余所有控件。
private struct NoteFormattingToggle: View {
    let isExpanded: Bool
    let action: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        BarButton(isSelected: isExpanded, isCompact: true, action: action) {
            NoteBarGlyph(name: "paintbrush")
        }
        .focusable(false)
        .accessibilityLabel(settings.text(NotesKey.formatAccessibility))
        .accessibilityValue(
            isExpanded
                ? settings.text(NotesKey.formatExpanded)
                : settings.text(NotesKey.formatCollapsed)
        )
        // 靠窗口尾侧边缘，居中对齐的标签会被挤出边界。
        .tooltip(settings.text(NotesKey.formatToggleHelp), alignment: .trailing)
    }
}

/// 各图标宽度不一，用固定尺寸保证每个按钮都是相同正方形。
private struct NoteBarGlyph: View {
    let name: String

    var body: some View {
        SymbolImage(name: name, size: Theme.Size.noteGlyph)
            .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
    }
}

/// 标题层级菜单的触发按钮。
private struct NoteHeadingButton: View {
    let level: Int?
    let isOpen: Bool
    let action: () -> Void
    let onFrameChange: (CGRect) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings

    private var isHeading: Bool { (1...6).contains(level ?? 0) }

    var body: some View {
        BarButton(isSelected: isHeading || isOpen, isCompact: true, action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                NoteBarGlyph(name: "textformat.size")
                // 旋转而非替换图标，因此展开菜单不会使工具条发生位移。
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
        }
        // 菜单挂靠在这个 frame 上，而只有完成布局的视图才知道它。
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            onFrameChange($0)
        }
        .focusable(false)
        .accessibilityLabel(settings.text(NotesKey.formatHeading))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isHeading ? .isSelected : [])
        // 展开胶囊的首端，窄窗口下会被推到边缘。
        .tooltip(isOpen ? nil : settings.text(NotesKey.formatHeading), alignment: .leading)
    }

    /// 供无障碍朗读的当前标题层级描述。
    private var accessibilityValue: String {
        switch level {
        case nil: ""
        case 0: settings.text(NotesKey.formatText)
        case let level?: String(format: settings.text(NotesKey.formatHeadingLevel), level)
        }
    }
}
