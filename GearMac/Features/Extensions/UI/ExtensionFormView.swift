// 文件职责：把 `ExtensionScreen` 描述的表单字段绘制为 SwiftUI 控件，并把编辑、提交与焦点变化派发回调色板。
// 分层：UI；字段值由 React 侧持有，本视图只负责绘制与派发编辑事件，不直接改写源数据。
import SwiftUI

/// 值由 React 侧持有；每次编辑都派发回去，再由重新渲染绘制出来。
struct ExtensionFormView: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let screen: ExtensionScreen
    let assetsPath: String?
    /// 当前聚焦字段，用调色板导航所使用的扁平索引表示。
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    /// 当某个控件接管键盘时会被通知，使单独的退格键用于编辑而非退出。
    @Environment(PaletteState.self) private var palette
    @FocusState private var focused: Int?

    private var labelWidth: CGFloat {
        form.labelWidth(for: metrics.size.panelWidth, gap: metrics.spacing.md)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: form.rowSpacing) {
                    ForEach(screen.fields) { field in
                        row(field)
                    }
                }
                // 整体作为一块居中；标签列与控件各自保持自身宽度。
                .frame(maxWidth: .infinity)
                .padding(.vertical, form.formVerticalPadding)
                // 置于字段之后，因此在空白表单区域按下时，会像菜单一样关闭已展开的列表。
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { palette.dismissControlList() }
                        .onRightClick { palette.dismissControlList() }
                }
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: focusedRowID, atOrigin: selection == 0, proxy: proxy)
        }
        // 表单出现时会继承上一个界面遗留的选中行，因此这里自行声明自己的聚焦字段。
        .onAppear { focus(screen.autoFocusedField) }
        .onDisappear { palette.noteEditingField(false) }
        // 调色板用 ↑/↓ 与 ⇥ 移动选中项；焦点随之移动，点击也会带动选中项。
        .onChange(of: selection) { focus(selection) }
        .onChange(of: focused) { _, field in
            palette.noteEditingField(field != nil)
            if let field, field != selection { onSelect(field) }
        }
    }

    private func focus(_ index: Int) {
        guard screen.items.indices.contains(index) else { return }
        focused = index
        if index != selection { onSelect(index) }
    }

    /// 聚焦字段的滚动 id；当表单没有可聚焦的字段时为 nil。
    private var focusedRowID: String? {
        screen.items.indices.contains(selection) ? screen.items[selection].id : nil
    }

    /// 单个绘制出的字段，接入 `ExtensionScreen` 决定的焦点顺序。
    @ViewBuilder
    private func row(_ field: RenderNode) -> some View {
        if let item = screen.focusItem(for: field) {
            fieldView(field, index: item.index)
                .id(item.id)
                .selectionFrame(item.index == selection)
        } else {
            fieldView(field, index: nil)
        }
    }

    /// 对于不可聚焦的字段（分隔线、说明文字、附件控件），`index` 为 nil。
    @ViewBuilder
    private func fieldView(_ field: RenderNode, index: Int?) -> some View {
        switch field.type {
        case "Form.Separator":
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .padding(.vertical, form.separatorSpacing)

        case "Form.Description":
            labelled(field, showTitle: field.string("title") != nil) {
                Text(field.string("text") ?? "")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    // 纯文本仍占用一个控件的高度，使其标签与控件对齐。
                    .padding(.vertical, form.verticalInset)
                    .frame(minHeight: form.controlHeight, alignment: .leading)
            }

        case "Form.TextField", "Form.PasswordField":
            labelled(field) {
                ExtensionTextField(
                    node: field, secure: field.type == "Form.PasswordField", index: index,
                    focus: $focused, onChange: onChange, onSubmit: onSubmit)
            }

        case "Form.TextArea":
            labelled(field) {
                ExtensionTextArea(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.Checkbox":
            labelled(field, showTitle: field.string("title") != nil) {
                ExtensionCheckbox(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.Dropdown":
            labelled(field) {
                ExtensionPickerField(
                    items: ExtensionPickerItem.items(in: field),
                    chosen: [field.string("value") ?? ""].filter { !$0.isEmpty },
                    placeholder: field.string("placeholder") ?? "Select…",
                    title: field.string("title") ?? "Dropdown",
                    info: field.string("info"),
                    error: field.string("error"),
                    assetsPath: assetsPath,
                    allowsMultipleSelection: false,
                    index: index, focus: $focused,
                    onChange: { onChange(field, $0.first ?? "") }, onSubmit: onSubmit)
            }

        case "Form.TagPicker":
            labelled(field) {
                ExtensionPickerField(
                    items: ExtensionPickerItem.items(in: field),
                    chosen: field.array("value").compactMap(\.stringValue),
                    placeholder: field.string("placeholder") ?? "Select…",
                    title: field.string("title") ?? "Tags",
                    info: field.string("info"),
                    error: field.string("error"),
                    assetsPath: assetsPath,
                    allowsMultipleSelection: true,
                    index: index, focus: $focused,
                    onChange: { onChange(field, $0) }, onSubmit: onSubmit)
            }

        case "Form.DatePicker":
            labelled(field) {
                ExtensionDateField(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.FilePicker":
            labelled(field) {
                ExtensionFilePicker(
                    node: field, index: index, focus: $focused, onChange: onChange,
                    onSubmit: onSubmit)
            }

        case "Form.LinkAccessory":
            EmptyView()

        default:
            labelled(field) {
                Text("\(field.type) isn't supported yet")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 标签位于控件左侧，同时不让控件偏离调色板中心。
    @ViewBuilder
    private func labelled<Content: View>(
        _ field: RenderNode, showTitle: Bool = true, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: metrics.spacing.md) {
            HStack(spacing: metrics.spacing.xxs) {
                Spacer(minLength: 0)
                Text(showTitle ? (field.string("title") ?? "") : "")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                // Raycast 在带有 info 的标签旁绘制的信息标记。
                if let info = field.string("info"), !info.isEmpty {
                    Image(systemName: "info.circle")
                        .font(metrics.typography.disclosure)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .help(info)
                        // 该文本已作为控件的提示，因此此图标仅作装饰。
                        .accessibilityHidden(true)
                }
            }
            .frame(width: labelWidth, alignment: .trailing)
            // 以控件高度居中，但允许增高，从而让长标签换行。
            .frame(minHeight: form.controlHeight)

            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                content()
                if let error = field.string("error"), !error.isEmpty {
                    Text(error)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.red)
                        // 由所属控件朗读，因此这段文字只是它的回声（避免重复朗读）。
                        .accessibilityHidden(true)
                }
            }
        }
        // 左对齐，使窄于控件的内容不会把标签拉向中心。
        .frame(
            width: labelWidth + metrics.spacing.md
                + form.controlWidth,
            alignment: .leading
        )
        .frame(maxWidth: .infinity)
        .offset(x: -(labelWidth + metrics.spacing.md) / 2)
    }
}

/// 本地状态吸收输入以避免光标跳动；程序化重置优先。
private struct ExtensionTextField: View {
    @Environment(\.metrics) private var metrics
    let node: RenderNode
    let secure: Bool
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    @State private var text: String = ""
    /// 最近一次派发的编辑内容，使较旧编辑的回声无法覆盖更新的输入。
    @State private var sent: String?
    @State private var hovered = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .font(metrics.typography.rowTitle)
        .focused($focus, equals: index)
        .extensionFieldChrome(focused: focus == index, hovered: hovered)
        .onHover { hovered = $0 }
        .modifier(ExtensionFormKeys(field: .text, onActivate: {}, onSubmit: onSubmit))
        // 可见标签是旁侧行中的一个 Text，输入框自身无法将其据为自己的标签。
        .accessibilityLabel(Text(node.string("title") ?? node.string("placeholder") ?? "Text"))
        .extensionFieldHint(node.string("info"), error: node.string("error"))
        .onAppear { text = node.string("value") ?? "" }
        .onChange(of: node.string("value") ?? "") { _, incoming in
            adopt(incoming)
        }
        .onChange(of: text) { _, outgoing in
            guard outgoing != (node.string("value") ?? "") else { return }
            sent = outgoing
            onChange(node, outgoing)
        }
    }

    /// React 的渲染应答有延迟，因此词中间的回声比其后输入的内容更旧。
    private func adopt(_ incoming: String) {
        if let sent {
            guard incoming == sent else { return }
            self.sent = nil
            return
        }
        if incoming != text { text = incoming }
    }

    private var prompt: Text {
        Text(node.string("placeholder") ?? "").foregroundStyle(Theme.Colors.textTertiary)
    }
}

/// 多行文本输入控件，同样以本地状态吸收输入并派发编辑事件。
private struct ExtensionTextArea: View {

    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }

    @Environment(\.metrics) private var metrics
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    @State private var text: String = ""
    /// 最近一次派发的编辑；回声为何可能过期见 `ExtensionTextField.adopt`。
    @State private var sent: String?
    @State private var hovered = false

    var body: some View {
        TextEditor(text: $text)
            .font(metrics.typography.rowTitle)
            .scrollContentBackground(.hidden)
            // 文本系统会给自身的行片段加内边距，边框的内边距会与之重复。
            .padding(.horizontal, -form.textViewGutter)
            .focused($focus, equals: index)
            .extensionFieldChrome(focused: focus == index, hovered: hovered, multiline: true)
            .onHover { hovered = $0 }
            .modifier(ExtensionFormKeys(field: .textArea, onActivate: {}, onSubmit: onSubmit))
            .accessibilityLabel(Text(node.string("title") ?? "Text area"))
            .extensionFieldHint(node.string("info"), error: node.string("error"))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(node.string("placeholder") ?? "")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, form.textInset)
                        .padding(.vertical, form.verticalInset)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { text = node.string("value") ?? "" }
            .onChange(of: node.string("value") ?? "") { _, incoming in
                if let sent {
                    guard incoming == sent else { return }
                    self.sent = nil
                    return
                }
                if incoming != text { text = incoming }
            }
            .onChange(of: text) { _, outgoing in
                guard outgoing != (node.string("value") ?? "") else { return }
                sent = outgoing
                onChange(node, outgoing)
            }
    }
}

/// 使用自绘控件而非 `Toggle`：`Toggle` 仅在「全键盘控制」下才能获得焦点。
private struct ExtensionCheckbox: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void
    @State private var hovered = false

    private var isOn: Bool { node.bool("value") ?? false }

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            box
            Text(node.string("label") ?? "")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: form.controlWidth, alignment: .leading)
        .frame(height: form.controlHeight)
        .contentShape(Rectangle())
        .focusable()
        .focused($focus, equals: index)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("label") ?? node.string("title") ?? "Checkbox"))
        // 开关会播报自身的类型与状态，而不仅仅是「可按下」。
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .extensionFieldHint(node.string("info"), error: node.string("error"))
        .accessibilityAction { toggle() }
        .modifier(ExtensionFormKeys(field: .checkbox, onActivate: toggle, onSubmit: onSubmit))
    }

    /// 自绘而非使用一对 SF Symbol：后者在勾选切换时字重不一致且会抖动。
    private var box: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn ? Color.accentColor : ExtensionColors.fieldFill)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(
                width: form.checkboxSize,
                height: form.checkboxSize)
    }

    private var borderColor: Color {
        if focus == index { return ExtensionColors.fieldFocusStroke }
        if isOn { return .clear }
        return hovered ? ExtensionColors.fieldFocusStroke : ExtensionColors.checkboxStroke
    }

    /// 点击也会取得焦点，使键盘操作从指针离开处继续。
    private func toggle() {
        focus = index
        onChange(node, !isOn)
    }
}

/// 文件/目录选择控件，点击后弹出 `NSOpenPanel` 并把所选路径派发出去。
private struct ExtensionFilePicker: View {

    @Environment(\.metrics) private var metrics
    let node: RenderNode
    let index: Int?
    @FocusState.Binding var focus: Int?
    let onChange: (RenderNode, Any) -> Void
    let onSubmit: () -> Void

    private var paths: [String] { node.array("value").compactMap(\.stringValue) }
    @State private var hovered = false

    private var label: String {
        guard !paths.isEmpty else { return "Choose…" }
        return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: "doc")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(label)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(paths.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .extensionFieldChrome(focused: focus == index, hovered: hovered)
        .contentShape(Rectangle())
        .focusable()
        .focused($focus, equals: index)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .onTapGesture { choose() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(node.string("title") ?? "File"))
        .accessibilityValue(Text(label))
        .accessibilityAddTraits(.isButton)
        .extensionFieldHint(node.string("info"), error: node.string("error"))
        .accessibilityAction { choose() }
        .modifier(ExtensionFormKeys(field: .filePicker, onActivate: choose, onSubmit: onSubmit))
    }

    private func choose() {
        focus = index
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = node.bool("allowMultipleSelection") ?? true
        panel.canChooseDirectories = node.bool("canChooseDirectories") ?? false
        panel.canChooseFiles = node.bool("canChooseFiles") ?? true
        // 没有这一步，附件类应用的打开面板会出现在最前应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        onChange(node, panel.urls.map(\.path))
    }
}
