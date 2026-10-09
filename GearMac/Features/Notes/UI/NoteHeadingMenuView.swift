// 文件职责：提供笔记标题层级选择菜单的 SwiftUI 视图及其行样式。
// 分层：UI 视图层；通过 NotesCoordinator 环境对象读取当前层级并派发选择。
import SwiftUI

/// 仿照 `PopoverMenuRow` 的外观：`PopoverMenu` 需要读取 Notes 不具备的调色板状态，因此在此重写。
struct NoteHeadingMenuView: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings

    /// 菜单中单个标题选项的描述。
    private struct Row {
        let level: Int
        let key: NotesKey
        let shortcut: String
    }

    private static let rows = [
        Row(level: 1, key: .headingLevel1, shortcut: "⌥⌘1"),
        Row(level: 2, key: .headingLevel2, shortcut: "⌥⌘2"),
        Row(level: 3, key: .headingLevel3, shortcut: "⌥⌘3"),
        Row(level: 0, key: .formatText, shortcut: "⌥⌘0")
    ]

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        VStack(spacing: Theme.Size.menuRowSpacing) {
            ForEach(Self.rows, id: \.level) { row in
                NoteHeadingMenuRow(
                    title: settings.text(row.key), shortcut: row.shortcut,
                    isCurrent: notes.formatting.headingLevel == row.level
                ) {
                    notes.chooseHeading(row.level)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassSurface(in: surface)
        .clipShape(surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.text(NotesKey.headingMenuAccessibility))
    }
}

/// 标题菜单中的一行：图标、标题、快捷键，并在悬停时高亮。
private struct NoteHeadingMenuRow: View {
    let title: String
    let shortcut: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark")
                    .font(
                        .system(
                            size: Theme.Typography.menuSymbolSize, weight: Theme.Typography.menuSymbolWeight)
                    )
                    .foregroundStyle(Theme.Colors.menuSymbol)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                Text(title)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                        KeyCapChip(text: String(glyph), style: .outline)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
