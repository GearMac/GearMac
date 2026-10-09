// 文件职责：布局编辑器的右栏检视器，自上而下依次摆放名称/图标、间距开关与逐条目字段分组。
// 分层：UI（SwiftUI 设置控件）；只读写 WindowLayoutDraft，不承担窗口操作与持久化。
import AppKit
import SwiftUI

/// 编辑器右栏：堆叠各字段分组，自身不持有几何信息。
struct WindowLayoutInspector: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @Environment(AppSettings.self) private var settings
    @State private var showingIconPicker = false
    @FocusState private var nameFocused: Bool

    /// 排列方式与工作场景类图标；不含菜单栏自己的字形，那会让人误以为是应用本身。
    private static let iconSymbols = [
        "rectangle.3.group", "square.grid.2x2", "rectangle.split.2x1", "rectangle.split.3x1",
        "rectangle.split.1x2", "sidebar.left", "macwindow", "display", "display.2",
        "laptopcomputer", "desktopcomputer", "briefcase", "hammer",
        "chevron.left.forwardslash.chevron.right", "paintbrush", "calendar", "video", "chart.bar",
        "terminal", "globe", "envelope", "message", "music.note", "book"
    ]

    var body: some View {
        // 仅作保险：正常字号下所有分组都能放进面板固定高度内。
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                nameField
                gapToggle
                Divider()
                sectionLabel(settings.text(WindowKey.inspectorSectionLayout))
                WindowLayoutEntryPicker(draft: draft, displays: displays)
                if draft.selectedEntry != nil {
                    WindowLayoutArgumentField(draft: draft)
                    frontmostToggle
                    Divider()
                    sizeFields
                    offsetFields
                    positionField
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Layout-wide

    /// 名称字段：文本框加图标选择器，两者共用同一层控件外框，读起来像一个控件。
    private var nameField: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(settings.text(WindowKey.fieldName))
            HStack(spacing: Theme.Spacing.sm) {
                TextField(settings.text(WindowKey.inspectorNamePlaceholder), text: $draft.name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .focusEffectDisabled()
                Divider()
                    .frame(height: Theme.Spacing.xl)
                Button {
                    showingIconPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        SymbolImage(name: draft.symbol, size: 13)
                        Image(systemName: "chevron.down")
                            .font(Theme.Typography.disclosure)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.text(WindowKey.inspectorChooseIcon))
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    SymbolPicker(
                        selection: $draft.iconSymbol, fallback: WindowLayout.sfSymbol,
                        symbols: Self.iconSymbols
                    ) {
                        showingIconPicker = false
                    }
                }
            }
            .layoutFieldChrome(isFocused: nameFocused)
        }
    }

    /// “使用首选间距”开关，作用于整份布局。
    private var gapToggle: some View {
        @Bindable var draft = draft
        return switchRow(
            settings.text(WindowKey.inspectorUsePreferredGap),
            detail: settings.text(WindowKey.inspectorUsePreferredGapDetail),
            isOn: $draft.usesPreferredGap)
    }

    // MARK: - The entry being edited

    /// 是否把当前条目窗口置前；一份布局只允许一个。
    private var frontmostToggle: some View {
        @Bindable var draft = draft
        return switchRow(
            settings.text(WindowKey.inspectorBringToFront),
            detail: settings.text(WindowKey.inspectorBringToFrontDetail),
            isOn: $draft.isSelectedEntryFrontmost)
    }

    /// 当前条目的尺寸（宽高百分比）。
    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(settings.text(WindowKey.fieldSize))
            HStack(spacing: Theme.Spacing.md) {
                WindowLayoutNumberField(
                    label: "W", name: settings.text(WindowKey.fieldWidth), suffix: "%",
                    range: WindowLayoutDraft.percentRange,
                    value: WindowLayoutDraft.percent(entry.widthFraction),
                    onCommit: draft.setWidthPercent)
                WindowLayoutNumberField(
                    label: "H", name: settings.text(WindowKey.fieldHeight), suffix: "%",
                    range: WindowLayoutDraft.percentRange,
                    value: WindowLayoutDraft.percent(entry.heightFraction),
                    onCommit: draft.setHeightPercent)
            }
        }
    }

    /// 当前条目的偏移（pt）。
    private var offsetFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(settings.text(WindowKey.fieldOffset))
            HStack(spacing: Theme.Spacing.md) {
                WindowLayoutNumberField(
                    label: "X", name: settings.text(WindowKey.fieldHorizontalOffset), suffix: "pt",
                    range: WindowLayoutDraft.offsetRange, value: Int(entry.offset.x.rounded()),
                    onCommit: draft.setOffsetX)
                WindowLayoutNumberField(
                    label: "Y", name: settings.text(WindowKey.fieldVerticalOffset), suffix: "pt",
                    range: WindowLayoutDraft.offsetRange, value: Int(entry.offset.y.rounded()),
                    onCommit: draft.setOffsetY)
            }
        }
    }

    /// 当前条目的锚点位置。
    private var positionField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(settings.text(WindowKey.fieldPosition))
            WindowLayoutPositionGrid(selection: entry.anchor, onSelect: draft.setAnchor)
        }
    }

    // MARK: - Helpers

    /// 带标题与说明文字的开关行，右侧放一个紧凑开关。
    private func switchRow(
        _ title: String, detail: String, isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    /// 分组小标题。
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
    }

    /// 安全：所有调用方都在 `draft.selectedEntry != nil` 判断之后。
    private var entry: WindowLayoutEntry {
        draft.selectedEntry ?? WindowLayoutEntry(bundleID: "", display: .init(uuid: "", name: ""))
    }
}
