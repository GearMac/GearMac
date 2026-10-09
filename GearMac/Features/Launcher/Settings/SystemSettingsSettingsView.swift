// 文件职责：「系统设置」类别设置页，组合该类别总开关与设置面板条目列表。
// 分层：UI（SwiftUI）；纯界面装配，不持有业务状态。
import SwiftUI

/// 面向 macOS 系统设置面板的启动器类别——因此名称里出现了重复的 System Settings。
struct SystemSettingsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .systemSettings, anchor: .systemSettingsSystemSettings)

            LauncherItemsSection(
                kind: .systemSettings,
                anchor: .systemSettingsSystemSettings,
                searchPrompt: settings.text(LauncherKey.searchSystemSettings))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemSettings)
        .releasesFocusOnOutsideClick()
    }
}
