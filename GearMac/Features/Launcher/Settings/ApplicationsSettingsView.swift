// 文件职责：「应用」设置页，组合应用类别开关、搜索范围与启动器条目列表。
// 分层：UI（SwiftUI）；纯设置界面装配，不持有业务状态。
import SwiftUI

/// 「应用」设置页的根视图。
struct ApplicationsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications)

            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: settings.text(LauncherKey.searchApplications))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }

}
