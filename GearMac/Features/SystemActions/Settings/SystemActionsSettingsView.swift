// 文件职责：系统动作功能的设置面板，包含类别开关区段与可搜索的动作条目列表。
// 分层：Settings/UI；仅组合通用设置组件，不直接读写存储。
import SwiftUI

/// 系统动作设置页：类别开关与动作条目列表。
struct SystemActionsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .systemAction, anchor: .systemActionsSystemActions)

            LauncherItemsSection(
                kind: .systemAction,
                anchor: .systemActionsSystemActions,
                searchPrompt: settings.text(SystemActionsKey.searchPrompt))
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.systemActions)
        .releasesFocusOnOutsideClick()
    }
}
