// 文件职责：剪贴板功能的设置面板，包含开关、历史保留时长、文本识别、默认动作与禁用应用等选项。
// 分层：Settings；SwiftUI 视图，只读写 AppSettings，并通过 AppCore 触发清空历史。
import SwiftUI
import UniformTypeIdentifiers

/// 剪贴板设置页：配置剪贴板历史、保留时长、文本识别与默认行为。
struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.clipboardEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .clipboardClipboard,
                        title: settings.text(ClipboardKey.settingsEnable),
                        subtitle: settings.text(ClipboardKey.settingsEnableSubtitle))
                }
            }
            .settingsAnchor(.clipboardClipboard)

            FeatureCommandsSection(owner: .clipboard, anchor: .clipboardCommands)
                .settingsEnabled(settings.clipboardEnabled)

            Section {
                Picker(selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.localizedTitle(settings.language)).tag(retention)
                    }
                } label: {
                    SettingsRowTitle(
                        .clipboardHistory, settings.text(ClipboardKey.settingsKeepHistoryFor))
                }
                Toggle(isOn: $settings.clipboardTextSearchEnabled) {
                    SettingsRowTitle(
                        .clipboardHistory, settings.text(ClipboardKey.settingsTextSearch))
                    Text(settings.text(ClipboardKey.settingsTextSearchSubtitle))
                }
                Picker(selection: $settings.clipboardDefaultAction) {
                    ForEach(ClipboardDefaultAction.allCases) { action in
                        Text(action.localizedTitle(settings.language)).tag(action)
                    }
                } label: {
                    SettingsRowTitle(
                        .clipboardHistory, settings.text(ClipboardKey.settingsDefaultAction))
                    Text(settings.text(ClipboardKey.settingsDefaultActionSubtitle))
                }
            } header: {
                SettingsSectionHeader(.clipboardHistory)
            }
            .settingsEnabled(settings.clipboardEnabled)

            DisabledApplicationsSection(
                bundleIDs: $settings.clipboardDisabledApps,
                anchor: .clipboardDisabledApplications,
                footer: settings.text(ClipboardKey.settingsDisabledAppsFooter)
            )
            .settingsEnabled(settings.clipboardEnabled)

            Section {
                LabeledContent {
                    Button(settings.text(ClipboardKey.settingsClearButton), role: .destructive) {
                        confirmingClear = true
                    }
                } label: {
                    SettingsRowTitle(
                        .clipboardDisabledApplications, settings.text(ClipboardKey.settingsClearTitle))
                    Text(settings.text(ClipboardKey.settingsClearSubtitle))
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
        .confirmationDialog(
            settings.text(ClipboardKey.settingsClearConfirmTitle),
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button(settings.text(ClipboardKey.settingsClearConfirm), role: .destructive) {
                core.clipboardCoordinator.clearHistory()
            }
            Button(settings.text(ClipboardKey.settingsCancel), role: .cancel) {}
        } message: {
            Text(settings.text(ClipboardKey.settingsClearConfirmMessage))
        }
    }
}
