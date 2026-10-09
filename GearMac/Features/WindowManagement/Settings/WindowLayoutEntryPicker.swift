// 文件职责：布局编辑器的条目选择行：用添加按钮选应用，用下拉菜单切换下方字段正在编辑的条目。
// 分层：UI（SwiftUI 设置控件）；应用图标由 AppIndex 解析，条目的增删选由 WindowLayoutDraft 处理。
import AppKit
import SwiftUI

/// 布局行：一个添加按钮加一个下拉菜单，下拉标明下方各字段正在编辑的条目。
struct WindowLayoutEntryPicker: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @Environment(AppIndex.self) private var appIndex
    @Environment(AppSettings.self) private var settings
    @State private var showingAppPicker = false
    @State private var showingEntries = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            addButton
            entryButton
        }
    }

    /// “+”：打开应用选择器，把所选应用加到当前目标显示器上。
    private var addButton: some View {
        Button {
            showingAppPicker = true
        } label: {
            Image(systemName: "plus")
                .font(Theme.Typography.keyCap.weight(.semibold))
                .frame(width: Theme.Size.layoutControlHeight - Theme.Spacing.xl)
                .layoutFieldChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.text(WindowKey.entryAddLabel))
        .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
            AppPickerPopover { bundleID in
                showingAppPicker = false
                guard let bundleID, let display = targetDisplay else { return }
                draft.addEntry(bundleID: bundleID, on: display)
            }
        }
    }

    /// 用按钮加 popover 而不是 `Menu`：菜单标签会把 `NSImage` 拉伸变形。
    private var entryButton: some View {
        Button {
            showingEntries = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let entry = draft.selectedEntry {
                    let app = AppPresentation.resolve(bundleID: entry.bundleID, in: appIndex)
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                    Text(app.name).lineLimit(1)
                } else {
                    Text(settings.text(WindowKey.entryNoApp)).foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .layoutFieldChrome()
        }
        .buttonStyle(.plain)
        .disabled(draft.entries.isEmpty)
        .accessibilityLabel(settings.text(WindowKey.entryEditingLabel))
        .popover(isPresented: $showingEntries, arrowEdge: .bottom) { entryList }
    }

    /// 条目列表：按显示器分组展示，底部提供移除当前条目的操作。
    private var entryList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(draft.tabs(connected: displays), id: \.uuid) { display in
                let entries = draft.entries(onDisplay: display.uuid)
                if !entries.isEmpty {
                    Text(display.name)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.md)
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            if draft.selectedEntry != nil {
                Divider()
                Button(settings.text(WindowKey.entryRemove), role: .destructive) {
                    showingEntries = false
                    draft.removeSelectedEntry()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Size.layoutControlHeight, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.layoutEntryPopover)
    }

    /// 列表中的单行：显示应用图标与名称，选中时右侧打勾。
    private func row(_ entry: WindowLayoutEntry) -> some View {
        let app = AppPresentation.resolve(bundleID: entry.bundleID, in: appIndex)
        let isSelected = entry.id == draft.selectedEntryID
        return Button {
            showingEntries = false
            draft.select(entryID: entry.id)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                Text(app.name).lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark").font(Theme.Typography.disclosure)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Size.layoutControlHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(isSelected ? Theme.Colors.selection : Color.clear))
        }
        .buttonStyle(.plain)
    }

    /// 新增条目的目标显示器：取当前选中项，若无（或不连接）则退回第一个显示器。
    private var targetDisplay: WindowLayoutDisplay? {
        draft.tabs(connected: displays).first { $0.uuid == draft.selectedDisplayUUID }
            ?? displays.first
    }
}
