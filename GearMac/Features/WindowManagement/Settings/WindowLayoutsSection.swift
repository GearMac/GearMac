// 文件职责：窗口管理设置中的布局库，列出每个布局并提供新建、捕获当前窗口、运行、编辑、复制、删除与可见性。
// 分层：UI（SwiftUI 设置区块）；读 WindowLayoutStore，操作统一委托给 windowLayoutCoordinator。
import SwiftUI

/// 布局库，位于窗口管理设置面板内：布局归属于窗口管理。
struct WindowLayoutsSection: View {
    /// 新建或编辑时上抛选中项；nil 表示新建。
    let onEdit: (WindowLayout?) -> Void
    /// 删除时上抛选中项，由父视图弹确认框。
    let onDelete: (WindowLayout) -> Void

    @Environment(WindowLayoutStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    /// 条目少于此数时筛选行只是干扰：布局库通常只有几行，而非几百行。
    private static let filterThreshold = 6

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowLayoutsShowInLauncher) {
                SettingsRowTitle(
                    .windowManagementLayouts, settings.text(WindowKey.layoutsShowInLauncher))
            }

            if store.layouts.count > Self.filterThreshold {
                SettingsFilterField(
                    prompt: settings.text(WindowKey.layoutsSearchPrompt), query: $query)
            }

            if results.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { layout in
                    WindowLayoutSettingsRow(
                        layout: layout,
                        onEdit: { onEdit(layout) },
                        onDelete: { onDelete(layout) })
                }
            }

            Button {
                onEdit(nil)
            } label: {
                SettingsRowTitle(.windowManagementLayouts, settings.text(WindowKey.layoutsNew))
            }
            Button {
                core.windowLayoutCoordinator.captureWindowLayout()
            } label: {
                SettingsRowTitle(
                    .windowManagementLayouts, settings.text(WindowKey.layoutsCapture))
            }
        } header: {
            SettingsSectionHeader(.windowManagementLayouts)
        }
    }

    /// 按名称过滤后的结果；查询为空时返回全部。
    private var results: [WindowLayout] {
        guard !query.isEmpty else { return store.layouts }
        return store.layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// 空列表提示：无布局与“筛选无结果”文案不同。
    private var emptyMessage: String {
        guard !store.layouts.isEmpty else {
            return settings.text(WindowKey.layoutsEmpty)
        }
        return String(format: settings.text(WindowKey.layoutsNoMatch), query)
    }
}

/// 单个布局的快捷键、启动器勾选框与操作按钮，样式与窗口命令行保持一致。
private struct WindowLayoutSettingsRow: View {
    let layout: WindowLayout
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppCore.self) private var core
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: layout.name, subtitle: layout.localizedSummary(settings.resolvedLanguage)) {
            SymbolImage(name: layout.symbol, size: 13)
        } trailing: {
            ShortcutRecorder(action: .windowLayout(id: layout.id))

            Button {
                core.windowLayoutCoordinator.runWindowLayout(id: layout.id)
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionRun))
            .accessibilityLabel(
                String(
                    format: settings.text(WindowKey.actionRun), layout.name))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionEdit))
            .accessibilityLabel(
                String(format: settings.text(WindowKey.actionEdit), layout.name))

            Button {
                core.windowLayoutCoordinator.duplicateWindowLayout(id: layout.id)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionDuplicate))
            .accessibilityLabel(
                String(format: settings.text(WindowKey.actionDuplicate), layout.name))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionDelete))
            .accessibilityLabel(
                String(format: settings.text(WindowKey.actionDelete), layout.name))

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(
                        format: settings.text(WindowKey.actionShowInLauncher), layout.name))
        }
    }

    /// 把布局包装为 AppEntry 后读写 VisibilityStore，与应用索引发布的键保持一致。
    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(layout)) },
            set: { visibility.setItemVisible($0, for: AppEntry(layout)) })
    }
}
