// 文件职责：渲染某个功能面板所拥有的内置命令列表，以及单条命令的别名/快捷键/可见性控件。
// 分层：UI（SwiftUI）；命令元数据来自 CommandCatalog，状态读写经 VisibilityStore。
import SwiftUI

/// 某功能面板拥有的命令分组：逐行渲染其命令的别名、快捷键与启动器可见性开关。
struct FeatureCommandsSection: View {
    let owner: SettingsTab
    let anchor: SettingsAnchor
    /// 由该面板在其他位置绘制的命令；在此排除而不是在那边列出，因此后续新增到
    /// `ownedCommands` 的命令无需二次修改也会出现。
    var excluding: Set<CommandID> = []

    var body: some View {
        Section {
            ForEach(CommandCatalog.entries(ownedBy: owner)) { entry in
                if !excluding.contains(where: { $0.rawValue == entry.id }) {
                    FeatureCommandRow(entry: entry)
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}

/// 单条命令的控件——别名、快捷键、启动器可见性——无论其面板把它们放在哪里。
struct FeatureCommandRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(
            title: entry.name,
            labelOpacity: visibility.isItemVisible(entry) ? 1 : 0.45
        ) {
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(format: settings.text(LauncherKey.showInLauncherFormat), entry.name))
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
