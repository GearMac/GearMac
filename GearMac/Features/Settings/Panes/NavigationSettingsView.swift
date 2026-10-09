// 文件职责：设置面板「导航」页，开关窗口切换与菜单栏搜索，并管理被禁用的应用列表。
// 分层：UI；仅绑定 AppSettings，行为由对应功能模块与 Coordinator 承担。
import SwiftUI

/// 用于「移动到某处」——一个窗口、一个菜单项——而不是「改变某物」。两个功能共用
/// 一个开关，因此该面板放在这里，而不是放进其中任一功能内部。
struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.navigationEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .navigationNavigation, title: "Enable navigation",
                        subtitle: "Switch windows and search menu bar items.")
                }
            }
            .settingsAnchor(.navigationNavigation)

            // 没有「在启动器中显示」开关：下面的逐命令复选框已经起到该作用。
            FeatureCommandsSection(
                owner: .navigation, anchor: .navigationCommands,
                excluding: [.searchMenuItems]
            )
            .settingsEnabled(settings.navigationEnabled)

            // 菜单搜索命令与仅由它读取的两个设置放在一起。
            Section {
                if let entry = CommandCatalog.entry(for: .searchMenuItems) {
                    FeatureCommandRow(entry: entry)
                }

                Toggle(isOn: $settings.menuSearchShowsAppleMenu) {
                    SettingsRowTitle(.navigationMenuSearch, "Show Apple menu items")
                }

                SettingsRow(
                    title: "Disabled Applications",
                    subtitle: "Their menus are never searched.",
                    anchor: .navigationMenuSearch
                ) {
                    EmptyView()
                }

                DisabledApplicationsList(bundleIDs: $settings.menuSearchDisabledApps)
            } header: {
                SettingsSectionHeader(.navigationMenuSearch)
            }
            .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
