// 文件职责：Apple Shortcuts 设置面板，展示从 Shortcuts app 发现的快捷指令并支持搜索过滤。
// 分层：Settings；只负责展示与交互，数据与刷新由 AppleShortcutCoordinator 提供。
import SwiftUI

/// 展示从 Shortcuts app 发现的快捷指令，每行带有普通条目一致的启动器控件。
struct AppleShortcutsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(AppIndex.self) private var appIndex
    @State private var query = ""

    /// 根据搜索词过滤后的快捷指令条目。
    private var entries: [AppEntry] {
        let entries = core.appleShortcutCoordinator.entries
        guard !query.isEmpty else { return entries }
        // 仅按是否匹配过滤：若按得分排序，正在编辑的行会在光标下移动。
        let matched = Set(appIndex.matches(query).map(\.id))
        return entries.filter { matched.contains($0.id) }
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.appleShortcutsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .appleShortcutsAppleShortcuts,
                        title: settings.text(AppleShortcutsKey.settingsEnableTitle),
                        subtitle: settings.text(AppleShortcutsKey.settingsEnableSubtitle))
                }
            }
            .settingsAnchor(.appleShortcutsAppleShortcuts)

            if settings.appleShortcutsEnabled {
                library
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.appleShortcuts)
        .releasesFocusOnOutsideClick()
        // 设置界面关闭期间快捷指令可能变化，因此面板每次打开都重新读取。
        .task(id: settings.appleShortcutsEnabled) { core.appleShortcutCoordinator.refresh() }
    }

    /// 由搜索框、条目列表与「打开 Shortcuts」按钮构成的分区。
    private var library: some View {
        Section {
            SettingsFilterField(
                prompt: settings.text(AppleShortcutsKey.searchPlaceholder), query: $query)
            LauncherItemsList(entries: entries, query: query, isEnabled: true)
            Button(settings.text(AppleShortcutsKey.openShortcuts)) {
                core.appleShortcutCoordinator.openShortcutsApp()
            }
        } header: {
            SettingsSectionHeader(.appleShortcutsShortcuts)
        }
    }
}
