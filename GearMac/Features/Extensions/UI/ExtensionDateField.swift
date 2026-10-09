// 文件职责：渲染 `Form.DatePicker` 字段：以自绘控件搭配表达式输入与日期预设列表，供扩展表单选择日期/时间。
// 分层：UI；值通过 onChange 回传，列表打开时将所有导航键让给列表。
import SwiftUI

/// `Form.DatePicker`：预设选项加上表达式，直接在控件内输入。
struct ExtensionDateField: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    /// 查询最后一次变化的时间，插入符闪烁从此重新计时。
    @State private var typedAt = Date()
    @State private var highlighted = 0
    @State private var hovered = false
    /// 面板完成自身定位后回报，供指向其展开方向的 chevron 使用。
    @State private var flipped = false
    /// 列表弹出期间被通知，使 Palette 把所有导航键都让给它。
    @Environment(PaletteState.self) private var palette

    /// `date` 类型只包含日期；其他类型还包含时间。
    private var includesTime: Bool { node.string("type") != "date" }
    private var value: Date? { node.date("value") }
    private var isFocused: Bool { focus == index }

    /// 控件的显示文本：有值则格式化日期，无值则显示 “No Date”。
    private var label: String {
        guard let value else { return "No Date" }
        return ExtensionDateExpression.detail(
            for: value, calendar: .current, includesTime: includesTime)
    }

    /// 按当前查询生成日期表达式预设。
    private var suggestions: [ExtensionDateExpression.Suggestion] {
        ExtensionDateExpression.suggestions(
            query: query, now: Date(), calendar: .current, includesTime: includesTime)
    }

    /// 先说明控件当前行为，再附上扩展对该字段的解释。
    private var hint: String {
        let state = open ? "Showing dates" : "Opens a list of dates"
        let parts = [node.string("error"), node.string("info")]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return ([state] + parts).joined(separator: ". ")
    }

    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            .focusEffectDisabled()
            .extensionListPanel(
                open: open, height: listHeight, revision: revision, flipped: $flipped
            ) {
                let rows = suggestions
                ExtensionPickerList(
                    items: rows.map {
                        ExtensionPickerItem(value: $0.title, title: $0.title, detail: $0.detail)
                    },
                    selection: highlighted, chosen: [], assetsPath: nil,
                    onSelect: { choose(rows, at: $0) },
                    onHighlight: { highlighted = $0 })
            }
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard !palette.menuOpen, !ExtensionFormKey.enterKeys.contains(press.key)
                else { return .ignored }
                switch ExtensionListKey(press: press, listOpen: open) {
                case .openList: return openList()
                case .moveUp: return move(-1)
                case .moveDown: return move(1)
                case .commit:
                    choose(suggestions, at: highlighted)
                    return .handled
                case .dismiss:
                    close()
                    return .handled
                case .append(let characters): return typed(characters)
                case .deleteBackward:
                    guard !query.isEmpty else { return .handled }
                    query.removeLast()
                    highlighted = 0
                    return .handled
                // 日期没有可步进的值：方向键要么属于列表，要么不属于任何人。
                case .stepValue, .ignored: return .ignored
                }
            }
            .modifier(
                ExtensionFormKeys(
                    field: .datePicker,
                    onActivate: {
                        if open { choose(suggestions, at: highlighted) } else { _ = openList() }
                    },
                    onSubmit: {
                        close(); onSubmit()
                    })
            )
            .onChange(of: open) { palette.noteControlListOpen(open) }
            .onChange(of: query) { typedAt = Date() }
            .onScrollVisibilityChange { if !$0 { close() } }
            .onChange(of: palette.controlListDismissToken) { close() }
            .onDisappear { if open { palette.noteControlListOpen(false) } }
            .onChange(of: focus) { _, focus in
                if focus != index { close() }
            }
    }

    /// 控件主体：日历图标、显示文本/表达式输入与 disclosure chevron。
    private var control: some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: "calendar")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            // 列表打开时，控件本身就是表达式输入框，含插入符。
            if open {
                ExtensionQueryText(query: query, prompt: "tomorrow at 10am", phase: typedAt)
            } else {
                Text(label)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(
                        value == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.sm)
            ExtensionDisclosureChevron(open: open, flipped: flipped)
        }
        .extensionFieldChrome(focused: isFocused, open: open, hovered: hovered)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("title") ?? "Date"))
        // 打开时控件即表达式输入框，因此朗读用户输入的内容。
        .accessibilityValue(Text(open && !query.isEmpty ? query : label))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .onHover { hovered = $0 }
        .onTapGesture {
            focus = index
            if open { close() } else { _ = openList() }
        }
    }

    /// 面板自身高度，定位规则据此将其放在控件上方或下方。
    private var listHeight: CGFloat {
        form.popoverHeight(rows: suggestions.count, hasSearchField: false)
    }

    /// 面板视图树的修订标识：查询、高亮与预设列表任一变化都会触发重建。
    private struct Revision: Equatable {
        let query: String
        let highlighted: Int
        let suggestions: [ExtensionDateExpression.Suggestion]
    }

    private var revision: Revision {
        Revision(query: query, highlighted: highlighted, suggestions: suggestions)
    }

    /// 追加输入字符并重置高亮。
    private func typed(_ characters: String) -> KeyPress.Result {
        query += characters
        highlighted = 0
        return .handled
    }

    /// 打开预设列表并清空查询。
    private func openList() -> KeyPress.Result {
        guard !open else { return .handled }
        query = ""
        highlighted = 0
        open = true
        return .handled
    }

    /// 关闭列表并清空查询。
    private func close() {
        guard open else { return }
        open = false
        query = ""
    }

    /// 在预设列表中上/下移动高亮。
    private func move(_ delta: Int) -> KeyPress.Result {
        let rows = suggestions.count
        guard rows > 0 else { return .handled }
        highlighted = min(max(highlighted + delta, 0), rows - 1)
        return .handled
    }

    /// 选中某条预设：无日期的项回传 null，有日期的项以 ISO8601 字符串回传。
    private func choose(_ rows: [ExtensionDateExpression.Suggestion], at index: Int) {
        guard rows.indices.contains(index) else { return }
        guard let date = rows[index].date else {
            onChange(node, NSNull())
            close()
            focus = self.index
            return
        }
        onChange(node, ["$date": ISO8601DateFormatter().string(from: date)])
        close()
        focus = self.index
    }
}
