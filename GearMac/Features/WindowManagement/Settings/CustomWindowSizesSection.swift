// 文件职责：窗口管理设置中的自定义尺寸库，列出每个尺寸并提供新增、编辑、删除、快捷键与启动器可见性。
// 分层：UI（SwiftUI 设置区块）；读取 CustomWindowSizeStore，写入统一委托给 CustomWindowSizeCoordinator。
import SwiftUI

/// 自定义尺寸库，位于窗口管理设置面板内，紧跟它所扩展的窗口命令之后。
struct CustomWindowSizesSection: View {
    /// 点击新增或编辑时上抛选中项；nil 表示新建。
    let onEdit: (CustomWindowSize?) -> Void

    @Environment(CustomWindowSizeStore.self) private var store
    @Environment(CustomWindowSizeCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            ForEach(store.sizes) { size in
                CustomWindowSizeRow(
                    size: size,
                    onEdit: { onEdit(size) },
                    onDelete: { delete(size) })
            }
            Button {
                onEdit(nil)
            } label: {
                SettingsRowTitle(.windowManagementCustomSizes, settings.text(WindowKey.sizesNew))
            }
        } header: {
            SettingsSectionHeader(.windowManagementCustomSizes)
        }
    }

    /// 删除通过 Coordinator 异步执行（需持久化与全局快捷键注销）。
    private func delete(_ size: CustomWindowSize) {
        Task { await coordinator.deleteCustomWindowSize(id: size.id) }
    }
}

/// 单个尺寸的快捷键、启动器勾选框与操作按钮，样式与窗口命令行保持一致。
private struct CustomWindowSizeRow: View {
    let size: CustomWindowSize
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: size.name, subtitle: size.localizedSummary(settings.resolvedLanguage)) {
            Image(systemName: CustomWindowSize.sfSymbol)
        } trailing: {
            ShortcutRecorder(action: .customWindowSize(id: size.id))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionEdit))
            .accessibilityLabel(String(format: settings.text(WindowKey.actionEdit), size.name))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionDelete))
            .accessibilityLabel(String(format: settings.text(WindowKey.actionDelete), size.name))

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(format: settings.text(WindowKey.actionShowInLauncher), size.name))
        }
    }

    /// 把尺寸包装为 AppEntry 后读写 VisibilityStore，与应用索引发布的键保持一致。
    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(size)) },
            set: { visibility.setItemVisible($0, for: AppEntry(size)) })
    }
}
