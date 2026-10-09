// 文件职责：渲染扩展 Form 中的下拉选择控件（Dropdown / TagPicker），把输入框、查询过滤与列表面板收在控件内部。
// 分层：UI；只做展示与交互编排，选中结果通过 onChange 回调交回上层，不持有扩展状态。
import SwiftUI

/// `Form.Dropdown` 与 `Form.TagPicker` 共用的控件：输入与光标都发生在字段自身内部。
struct ExtensionPickerField: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let items: [ExtensionPickerItem]
    /// 当前持有的全部值；下拉控件只有一个，标签选择器可以有任意多个。
    let chosen: [String]
    let placeholder: String
    /// 字段自身的标题，使控件向外播报自己是什么，而不是只被读作一个展开箭头。
    let title: String
    /// 字段自身的说明，在状态之后播报，让两者都能被听到。
    let info: String?
    /// 扩展针对该字段报告的错误，优先于其他内容播报。
    let error: String?
    let assetsPath: String?
    let allowsMultipleSelection: Bool
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: ([String]) -> Void
    let onSubmit: () -> Void

    @State private var open = false
    @State private var query = ""
    /// 查询最近一次变更的时刻，光标闪烁从此处重新计时。
    @State private var typedAt = Date()
    @State private var highlighted = 0
    @State private var hovered = false
    /// 面板完成自身定位后回传，供指向面板方向的展开箭头使用。
    @State private var flipped = false
    /// 从视图环境读取，使界面外观切换时已解析的图标能够重绘。
    @Environment(\.isDarkAppearance) private var isDark
    /// 列表弹出期间被通知，使调色板把全部导航按键让给该列表。
    @Environment(PaletteState.self) private var palette

    /// 该字段当前是否持有焦点。
    private var isFocused: Bool { focus == index }

    /// 屏幕阅读器听到的内容：搜索中播报查询，否则播报当前持有的值。
    private var announcedValue: String {
        guard open, !query.isEmpty else { return chosen.isEmpty ? placeholder : label }
        return chosen.isEmpty ? query : "\(label), searching \(query)"
    }

    /// 先说明控件做什么，再说明扩展对该字段的解释。
    private var hint: String {
        let state = open ? "Showing choices" : "Opens a list of choices"
        let parts = [error, info].compactMap { $0 }.filter { !$0.isEmpty }
        return ([state] + parts).joined(separator: ". ")
    }

    /// 控件收起时读取的内容：已选条目的标题，或占位文案。
    private var label: String {
        let titles = chosen.compactMap { value in items.first { $0.value == value }?.title }
        return titles.isEmpty ? placeholder : titles.joined(separator: ", ")
    }

    /// 单选时按当前值解析出的前置图标；多选或无值时为空。
    private var leadingIcon: ExtensionImage.Resolved? {
        guard !allowsMultipleSelection, let value = chosen.first else { return nil }
        let icon = items.first { $0.value == value }?.iconValue
        return ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark)
    }

    /// 按当前查询过滤后的候选条目；查询为空时返回全部。
    private var matches: [ExtensionPickerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let needle = FuzzyMatch.Query(trimmed)
        return items.filter { FuzzyMatch.score(needle, candidate: $0.title) != nil }
    }

    /// 展开列表绘制的分组标题数量，列表高度与是否翻转的判断都会计入。
    private var sectionCount: Int {
        let matches = matches
        return matches.indices.reduce(into: 0) { total, index in
            guard let section = matches[index].section else { return }
            if index == 0 || matches[index - 1].section != section { total += 1 }
        }
    }

    /// 控件主体：组合可视控件、键盘处理与列表面板的挂载。
    var body: some View {
        control
            .focusable()
            .focused($focus, equals: index)
            // 焦点描边由外壳绘制，AppKit 自带的蓝色焦点环会成为重复的一层。
            .focusEffectDisabled()
            .extensionListPanel(
                open: open, height: listHeight, revision: revision, flipped: $flipped
            ) {
                ExtensionPickerList(
                    items: matches, selection: highlighted, chosen: Set(chosen),
                    assetsPath: assetsPath, onSelect: { choose(at: $0) },
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
                    choose(at: highlighted)
                    return .handled
                case .dismiss:
                    close()
                    return .handled
                case .append(let characters):
                    query += characters
                    highlighted = 0
                    return .handled
                case .deleteBackward:
                    guard !query.isEmpty else { return .handled }
                    query.removeLast()
                    highlighted = 0
                    return .handled
                case .stepValue(let delta): return step(delta)
                case .ignored: return .ignored
                }
            }
            .modifier(
                ExtensionFormKeys(
                    field: allowsMultipleSelection ? .tagPicker : .dropdown,
                    onActivate: {
                        if open { choose(at: highlighted) } else { _ = openList() }
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
                // 焦点离开该字段时，随之弹出的列表也一并关闭。
                if focus != index { close() }
            }
    }

    /// 控件的可视主体：前置图标、已选值或查询文本，以及展开箭头。
    private var control: some View {
        HStack(spacing: metrics.spacing.sm) {
            if let leadingIcon, query.isEmpty {
                ExtensionIconView(resolved: leadingIcon, size: 14)
            }
            // 列表展开时，控件本身就是搜索框，光标也在其中。
            if open {
                // 多选时，输入查询期间仍保持已选值可见。
                if allowsMultipleSelection, !chosen.isEmpty {
                    Text(label)
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Text("·")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                ExtensionQueryText(query: query, prompt: "Search…", phase: typedAt)
            } else {
                Text(label)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(
                        chosen.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.sm)
            ExtensionDisclosureChevron(open: open, flipped: flipped)
        }
        .extensionFieldChrome(focused: isFocused, open: open, hovered: hovered)
        .contentShape(Rectangle())
        // 缺少这一行时，控件只会被读作一个展开箭头：没有名称、没有值、没有角色。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        // 展开时控件是搜索框，因此播报正在输入的内容。
        .accessibilityValue(Text(announcedValue))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .onHover { hovered = $0 }
        .onTapGesture {
            focus = index
            if open { close() } else { _ = openList() }
        }
    }

    /// 面板自身的高度，定位规则据此把面板放在控件的上方或下方。
    private var listHeight: CGFloat {
        form.popoverHeight(
            rows: matches.count, hasSearchField: false, headers: sectionCount)
    }

    /// 托管列表所绘制的内容；其中任一项变化都会重新推入面板的视图树。
    private struct Revision: Equatable {
        let query: String
        let highlighted: Int
        let isDark: Bool
        let chosen: [String]
        let items: [ExtensionPickerItem]
        let assetsPath: String?
    }

    /// 当前列表绘制所依赖的快照，用于驱动面板刷新。
    private var revision: Revision {
        Revision(
            query: query, highlighted: highlighted, isDark: isDark,
            chosen: chosen, items: matches, assetsPath: assetsPath)
    }

    /// 展开列表：清空查询，并把高亮定位到已选项。
    private func openList() -> KeyPress.Result {
        guard !open else { return .handled }
        query = ""
        highlighted = items.firstIndex { chosen.contains($0.value) } ?? 0
        open = true
        return .handled
    }

    /// 关闭列表并清空查询。
    private func close() {
        guard open else { return }
        open = false
        query = ""
    }

    /// 在当前候选条目范围内上下移动高亮。
    private func move(_ delta: Int) -> KeyPress.Result {
        let count = matches.count
        guard count > 0 else { return .handled }
        highlighted = min(max(highlighted + delta, 0), count - 1)
        return .handled
    }

    /// 采用截断而非循环，使长按方向键会像其他列表一样停在端点。
    private func step(_ delta: Int) -> KeyPress.Result {
        guard !allowsMultipleSelection, !items.isEmpty else { return .ignored }
        let current = items.firstIndex { chosen.contains($0.value) } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard next != current else { return .handled }
        onChange([items[next].value])
        return .handled
    }

    /// 选中指定下标的候选条目；单选选中后关闭控件，多选则切换并保持展开。
    private func choose(at index: Int) {
        let matches = matches
        guard matches.indices.contains(index) else { return }
        let value = matches[index].value
        guard allowsMultipleSelection else {
            onChange([value])
            close()
            focus = self.index
            return
        }
        // 多选保持展开，符合从列表中逐个勾选标签的使用习惯。
        var next = chosen
        if let existing = next.firstIndex(of: value) {
            next.remove(at: existing)
        } else {
            next.append(value)
        }
        onChange(next)
    }
}
