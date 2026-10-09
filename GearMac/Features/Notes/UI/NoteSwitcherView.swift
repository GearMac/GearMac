// 文件职责：实现笔记切换器（搜索与选择笔记）的 SwiftUI 视图及其列表行。
// 分层：UI 视图层；通过 NotesCoordinator 环境对象读取笔记列表并派发激活、重命名、删除等操作。
import SwiftUI

/// 笔记切换器的根视图：搜索栏加结果列表。
struct NoteSwitcherView: View {
    let onContentHeight: (CGFloat) -> Void
    @Environment(NotesCoordinator.self) private var notes
    @Environment(AppSettings.self) private var settings
    @FocusState private var searchFocused: Bool

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    /// 搜索输入框与结果列表的组合，并绑定键盘导航快捷键。
    var body: some View {
        VStack(spacing: 0) {
            searchField
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassSurface(in: surface)
        .clipShape(surface)
        .onAppear(perform: focusSearch)
        .onChange(of: notes.switcherFocusRevision) { _, _ in focusSearch() }
        .onChange(of: notes.visibleNotes) { _, _ in
            notes.reconcileSwitcherSelection()
        }
        .onKeyPress(.downArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.moveSwitcherSelection(by: -1)
            return .handled
        }
        .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")]) { _ in
            guard !notes.isRenamingSwitcherNote else { return .ignored }
            notes.selectSwitcherNote()
            return .handled
        }
    }

    /// 顶部搜索输入框，包含清空按钮。
    private var searchField: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(settings.text(NotesKey.switcherSearchPlaceholder), text: notes.searchQueryBinding)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { notes.closeSwitcher() }
                .accessibilityLabel(settings.text(NotesKey.switcherSearchLabel))
            if !notes.searchQueryBinding.wrappedValue.isEmpty {
                Button {
                    notes.searchQueryBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.text(NotesKey.switcherClearSearch))
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.noteSearchHeight)
    }

    /// 搜索结果：无结果时显示空状态，否则显示可滚动的笔记列表。
    @ViewBuilder
    private var results: some View {
        if notes.visibleNotes.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                SymbolImage(
                    name: notes.isSearching ? "clock" : "text.page",
                    size: Theme.Size.noteGlyph
                )
                .foregroundStyle(Theme.Colors.textSecondary)
                Text(
                    notes.isSearching
                        ? settings.text(NotesKey.switcherSearching)
                        : settings.text(NotesKey.switcherNoResults)
                )
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.noteSwitcherEmptyHeight)
            .measuredHeight(onContentHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes.visibleNotes) { summary in
                            NoteSwitcherRow(
                                summary: summary,
                                selected: notes.switcherSelection == summary.id,
                                editing: notes.switcherEditingID == summary.id,
                                titleDraft: notes.switcherTitleDraftBinding,
                                onActivate: { notes.activateSwitcherNote(summary.id) },
                                onBeginRename: {
                                    notes.beginSwitcherRename(summary)
                                    searchFocused = false
                                },
                                onCommitRename: notes.commitSwitcherRename,
                                onCancelRename: notes.cancelSwitcherRename,
                                onTrash: { notes.trash(summary.id) }
                            )
                            .id(summary.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .measuredHeight(onContentHeight)
                }
                // 搜索行为是同级视图而非悬浮条，因此只有底边会渐变淡出。
                .overflowFade()
                .onChange(of: notes.switcherSelection) { _, selected in
                    if let selected { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }

    /// 将焦点移到搜索输入框（延后一拍以确保视图已就位）。
    private func focusSearch() {
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }
}

extension View {
    /// 测量视图实际高度并将结果回调出去。
    fileprivate func measuredHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            report($0)
        }
    }
}

/// 切换器中的单条笔记行，支持选中、悬停与行内重命名。
private struct NoteSwitcherRow: View {
    let summary: NoteSummary
    let selected: Bool
    let editing: Bool
    @Binding var titleDraft: String
    let onActivate: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onTrash: () -> Void
    @State private var hovered = false
    @FocusState private var titleFocused: Bool
    @Environment(AppSettings.self) private var settings

    /// 行的背景色：选中优先，其次悬停，否则透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: "text.page", size: Theme.Size.noteGlyph)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            if editing {
                TextField(settings.text(NotesKey.switcherTitlePlaceholder), text: $titleDraft)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit(onCommitRename)
                    .onExitCommand(perform: onCancelRename)
            } else {
                Text(summary.displayTitle)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            if !editing, selected || hovered {
                rowButton(
                    title: String(format: settings.text(NotesKey.switcherRename), summary.displayTitle),
                    symbol: "pencil", action: onBeginRename)
                rowButton(
                    title: String(format: settings.text(NotesKey.switcherTrash), summary.displayTitle),
                    symbol: "trash", action: onTrash
                )
                .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            onActivate()
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction {
            guard !editing else { return }
            onActivate()
        }
        .accessibilityAction(
            named: String(format: settings.text(NotesKey.switcherRename), summary.displayTitle)
        ) {
            guard !editing else { return }
            onBeginRename()
        }
        .accessibilityAction(
            named: String(format: settings.text(NotesKey.switcherTrash), summary.displayTitle)
        ) {
            guard !editing else { return }
            onTrash()
        }
        .onChange(of: editing) { _, editing in
            if editing {
                Task { @MainActor in
                    await Task.yield()
                    titleFocused = true
                }
            }
        }
    }

    /// 构建一个行内小图标按钮。
    private func rowButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
        }
        .buttonStyle(.plain)
        .help(title)
        // 该行已将两者发布为无障碍操作，因此这些按钮不再进入无障碍树。
        .accessibilityHidden(true)
    }
}
