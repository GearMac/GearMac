// 文件职责：Notes 功能的设置页，提供启用开关、Markdown 渲染、格式栏与笔记文件夹选择。
// 分层：Settings（SwiftUI View）；只做设置项绑定与展示，不直接读写文件。
import SwiftUI

/// 设置窗口中 Notes 分区的内容视图。
struct NotesSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    /// 表单主体：按启用开关、编辑选项与命令分组渲染，并按设置项状态控制可用性。
    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.notesEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .notesNotes, title: settings.text(NotesKey.settingsEnableTitle),
                        subtitle: settings.text(NotesKey.settingsEnableSubtitle))
                }
            }
            .settingsAnchor(.notesNotes)

            Section {
                Toggle(isOn: $settings.notesRendersMarkdown) {
                    SettingsRowTitle(.notesOptions, settings.text(NotesKey.settingsRenderMarkdown))
                    Text(settings.text(NotesKey.settingsRenderMarkdownSubtitle))
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesShowsFormattingBar) {
                    SettingsRowTitle(.notesOptions, settings.text(NotesKey.settingsFormattingBar))
                }
                .settingsEnabled(settings.notesEnabled && settings.notesRendersMarkdown)
                LabeledContent {
                    if settings.notesFolder != nil {
                        Button(
                            settings.text(NotesKey.settingsUseDefault),
                            action: core.notesCoordinator.resetNotesFolder)
                    }
                    Button(
                        settings.text(NotesKey.settingsChoose),
                        action: core.notesCoordinator.chooseNotesFolder)
                } label: {
                    SettingsRowTitle(.notesOptions, settings.text(NotesKey.settingsFolder))
                    Text((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
                }
            } header: {
                SettingsSectionHeader(.notesOptions)
            }

            FeatureCommandsSection(owner: .notes, anchor: .notesCommands)
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }
}
