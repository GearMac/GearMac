// 文件职责：汇集多个设置面板与编辑器共用的少量组件，包括行/字段包装、面板与输入框外观修饰器、筛选框、开关区块及别名输入框。
// 分层：UI（DesignSystem）；组件依赖 `Theme`、`SettingsAnchor` 与 `AliasStore` 等外部状态，自身不实现业务逻辑。
import AppKit
import SwiftUI

// 这里只放多个设置面板或编辑器共用的少数组件；其余组件仍归各自功能模块所有。

/// 设置侧边栏的图标方块，同一功能的开关处也复用它。
struct SettingsTabIcon: View {
    let systemImage: String
    let tint: Color
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(tint)
            .padding(Theme.Spacing.xs * scale)
            .background(
                tint.opacity(0.1),
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous))
    }
}

/// 功能总开关的标签：侧边栏图标 + 标题 + 副标题。
struct SettingsFeatureToggleLabel: View {
    let anchor: SettingsAnchor
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SettingsTabIcon(
                systemImage: anchor.tab.systemImage, tint: .accentColor,
                size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                SettingsRowTitle(anchor, title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 不使用 `LabeledContent`：其可选中的文本字段会吞掉 `ShortcutRecorder` 需要的点击事件。
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleLineLimit = 1
    var alignment: VerticalAlignment = .center
    var labelOpacity = 1.0
    /// 当搜索结果指向本行时设置，使标题可以显示高亮脉冲。
    var anchor: SettingsAnchor?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.lg) {
            icon.opacity(labelOpacity)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Group {
                    if let anchor {
                        SettingsRowTitle(anchor, title)
                    } else {
                        Text(title)
                    }
                }
                .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            .opacity(labelOpacity)
            Spacer(minLength: Theme.Spacing.lg)
            trailing
        }
    }
}

/// 设置列表统一使用的度量常量。
enum SettingsListMetrics {
    static let iconSize = Theme.Size.settingsRowIcon + Theme.Spacing.xs
}

/// 无图标版本的 `SettingsRow` 便捷初始化器。
extension SettingsRow where Icon == EmptyView {
    init(
        title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1,
        alignment: VerticalAlignment = .center,
        labelOpacity: Double = 1, anchor: SettingsAnchor? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit,
            alignment: alignment, labelOpacity: labelOpacity,
            anchor: anchor, icon: { EmptyView() },
            trailing: trailing)
    }
}

/// 设置中的扫描范围行：显示路径图标与名称，并支持移除。
struct SettingsScopeRow: View {
    let scope: String
    let path: String
    let isMissing: Bool
    let onRemove: () -> Void

    /// 按扩展名判断该路径是否为文件夹（`.app` 之外均视为文件夹）。
    private var isFolder: Bool { (path as NSString).pathExtension != "app" }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("This location no longer exists.")
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(scope)")
            }
        } label: {
            HStack {
                Image(nsImage: IconCache.icon(forFile: path))
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .id(IconCache.style.generation)
                    .frame(
                        width: SettingsListMetrics.iconSize
                            - (isFolder ? Theme.Spacing.xxs + 1 : 0),
                        height: SettingsListMetrics.iconSize - (isFolder ? 1 : 0)
                    )
                    .frame(
                        width: SettingsListMetrics.iconSize,
                        height: SettingsListMetrics.iconSize
                    )
                    .accessibilityHidden(true)
                Text(scope)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isMissing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            }
        }
    }
}

extension View {
    /// 为选项分段应用方形底：选中时填充控件底色。
    func settingsOptionSegment(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return
            self
            .frame(
                width: Theme.Size.settingsControlHeight,
                height: Theme.Size.settingsControlHeight
            )
            .contentShape(shape)
            .background {
                shape.fill(isSelected ? Theme.Colors.controlSurface : Color.clear)
            }
    }

    /// 同时降低透明度并禁用；仅用 `.disabled` 时标题仍保持全亮。
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }

    /// 应用设置编辑器的单行输入框外观。
    func settingsEditorTextField() -> some View {
        modifier(SettingsEditorTextField())
    }

    /// 应用设置编辑器的多行文本区域外观，高度由调用方给定。
    func settingsEditorTextArea(height: CGFloat) -> some View {
        modifier(SettingsEditorTextArea(height: height))
    }

    /// `controlsOnGlass: false` 时把玻璃背景绘制在内容之后，使控件保留自身强调色。
    func settingsEditorPanelSurface(controlsOnGlass: Bool = true) -> some View {
        modifier(SettingsEditorPanelSurface(controlsOnGlass: controlsOnGlass))
    }

    /// 唯一说明「从启动器隐藏某行并不会解绑其快捷键」的地方。
    func launcherVisibilityHelp() -> some View {
        help("Show in launcher. Its shortcut works either way.")
    }
}

/// 设置编辑页的标题与可选副标题。
struct SettingsEditorHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.panelTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 带标签的设置表单字段：标签在左，内容右对齐。
struct SettingsEditorField<Content: View>: View {
    let title: String
    var labelFont: Font?
    @ViewBuilder var content: Content

    init(
        _ title: String, labelFont: Font? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelFont = labelFont
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(labelFont)
        }
    }
}

/// 单行输入框的样式修饰器。
private struct SettingsEditorTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

/// 多行文本区域的样式修饰器。
private struct SettingsEditorTextArea: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(Theme.Spacing.sm)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

/// 面板背景修饰器：叠加窗口拖拽层与玻璃材质。
private struct SettingsEditorPanelSurface: ViewModifier {
    let controlsOnGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        // 放在玻璃之前：玻璃填充可参与命中测试，会把其后的拖拽手柄挡住。
        let draggable = content.background(WindowDragBackground())
        if controlsOnGlass {
            draggable
                .background(Theme.Colors.panelScrim, in: shape)
                .glassSurface(in: shape)
        } else {
            draggable.background {
                shape.fill(Theme.Colors.panelScrim).glassSurface(in: shape)
            }
        }
    }
}

/// 功能面板的开头区块：总开关，以及与之配套的「在启动器中显示」开关。
struct FeatureSwitchSection: View {
    let anchor: SettingsAnchor
    let enableTitle: String
    var enableSubtitle: String?
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool
    var showsIcon = false
    var showsHeader = true

    var body: some View {
        if showsHeader {
            section
        } else {
            section.settingsAnchor(anchor)
        }
    }

    /// 构成区块内容的开关组及其页眉。
    private var section: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                if showsIcon, let enableSubtitle {
                    SettingsFeatureToggleLabel(
                        anchor: anchor, title: enableTitle, subtitle: enableSubtitle)
                } else {
                    SettingsRowTitle(anchor, enableTitle)
                    if let enableSubtitle { Text(enableSubtitle) }
                }
            }
            Toggle("Show in launcher", isOn: $showsInLauncher)
                // 上面的总开关始终保持可交互，以便功能随时可以重新打开。
                .settingsEnabled(isEnabled)
        } header: {
            if showsHeader { SettingsSectionHeader(anchor) }
        }
    }
}

/// 长列表上方的筛选行，外观做成搜索框而不是表单输入框。
struct SettingsFilterField: View {
    let prompt: String
    @Binding var query: String
    /// 无边框字段没有可点击区域：若不加这层，只有文字本身能作为点击目标。
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // 同时使用 `prompt:` 与 `labelsHidden`，否则表单会把占位文字变成左侧列的标题。
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}

/// 别名输入用的 AppKit 文本视图桥接：为保留焦点与按键处理而自绘 `NSTextView`。
private struct AliasTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onCancel: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 构建单行、无背景的 `NSTextView`。
    func makeNSView(context: Context) -> NSTextView {
        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        editor.textContainerInset = NSSize(width: 0, height: 5.5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.maximumNumberOfLines = 1
        editor.textContainer?.lineBreakMode = .byTruncatingTail
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editor.setAccessibilityRole(.textField)
        return editor
    }

    /// 同步文本与启用状态，并在失焦时主动交出第一响应者。
    func updateNSView(_ editor: NSTextView, context: Context) {
        context.coordinator.field = self
        if editor.string != text { editor.string = text }
        editor.isEditable = isEnabled
        editor.isSelectable = isEnabled
        editor.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        if !focused, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
    }

    /// 作为 `NSTextView` 的代理，回写文本、拦截换行/制表/取消等按键。
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var field: AliasTextField

        init(_ field: AliasTextField) {
            self.field = field
        }

        /// 文本变化时回写到绑定值。
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            field.text = editor.string
        }

        /// 把粘贴内容中的换行替换为空格，保持单行输入。
        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString, replacementString.contains(where: \.isNewline) else {
                return true
            }
            textView.insertText(
                String(replacementString.map { $0.isNewline ? " " : $0 }),
                replacementRange: range)
            return false
        }

        /// 开始编辑时标记为聚焦。
        func textDidBeginEditing(_ notification: Notification) {
            field.focused = true
        }

        /// 结束编辑时清除聚焦标记。
        func textDidEndEditing(_ notification: Notification) {
            field.focused = false
        }

        /// 处理回车、Tab、Shift-Tab 与 Esc 的按键行为。
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectNextKeyView(textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.recalculateKeyViewLoop()
                textView.window?.selectPreviousKeyView(textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                field.onCancel()
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// 外观与 `ShortcutRecorder` 一致；使用常驻的 AppKit 输入框以在更新间保持焦点。
struct AliasField: View {
    /// 持有者的 `preferenceKey`，以原始字符串接收，使没有 `AppEntry` 的行也能携带别名。
    let key: String
    let name: String
    @Environment(AliasStore.self) private var aliases
    @State private var draft = ""
    @State private var focused = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        HStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .leading) {
                if draft.isEmpty {
                    Text("Add Alias")
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                AliasTextField(text: $draft, focused: $focused, onCancel: revert)
                    .focusEffectDisabled()
                    // 面板的 `releasesFocusOnOutsideClick` 会让输入框失焦；这里捕获失焦并提交。
                    .onChange(of: focused) { _, now in
                        if !now { commit() }
                    }
            }
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear alias for \(name)")
            }
        }
        .onAppear { draft = aliases.alias(for: key) ?? "" }
        // 导入备份会在行未聚焦时替换整张表，此时需刷新草稿。
        .onChange(of: aliases.revision) { _, _ in
            if !focused { draft = aliases.alias(for: key) ?? "" }
        }
        // 复用的表格行会把该输入框交给另一个条目；未保存的文本属于旧条目。
        .onChange(of: key) { old, new in
            if focused {
                aliases.setAlias(draft, for: old)
                focused = false
            }
            draft = aliases.alias(for: new) ?? ""
        }
        .padding(.horizontal, Theme.Spacing.sm + 1)
        .frame(width: Theme.Size.shortcutRecorder, height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
        .clipShape(shape)
        .accessibilityLabel("Alias for \(name)")
    }

    /// 唯一的提交路径——按 ↵ 或焦点转走；草稿为空则删除该别名。
    private func commit() {
        aliases.setAlias(draft, for: key)
        draft = aliases.alias(for: key) ?? ""
    }

    /// 还原草稿为已保存的别名，并清除焦点。
    private func revert() {
        draft = aliases.alias(for: key) ?? ""
        focused = false
    }

    /// 清空草稿并提交，从而删除别名。
    private func clear() {
        draft = ""
        commit()
    }
}

extension AliasField {
    /// 以 `AppEntry` 构造别名字段。
    init(entry: AppEntry) {
        self.init(key: entry.preferenceKey, name: entry.name)
    }
}
