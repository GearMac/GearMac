// 文件职责：自定义命令面板的设置界面，承载内置命令开关、自定义命令列表与新增/导入/编辑/删除入口。
// 分层：UI（Settings）；通过 Environment 读取 CustomCommandStore/AppCore/AppSettings，所有命令变更一律经 CustomCommandCoordinator 执行。
import SwiftUI

/// 两类命令放在同一面板：先是内置命令，再是用户自定义的 shell 命令。
struct CommandsSettingsView: View {
    @Environment(CustomCommandStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: CustomCommand?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherCategorySwitchSection(kind: .command, anchor: .commandsCommands)

            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: settings.text(CustomCommandsKey.settingsSearchPrompt))

            FeatureSwitchSection(
                anchor: .commandsCustomCommands,
                enableTitle: settings.text(CustomCommandsKey.settingsEnableTitle),
                enableSubtitle: settings.text(CustomCommandsKey.settingsEnableSubtitle),
                isEnabled: $settings.customCommandsEnabled,
                showsInLauncher: $settings.customCommandsShowInLauncher)

            Section {
                if store.commands.isEmpty {
                    Text(settings.text(CustomCommandsKey.settingsEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCommands) { command in
                        CustomCommandSettingsRow(
                            command: command,
                            showsInLauncher: settings.customCommandsShowInLauncher,
                            isEnabled: Binding(
                                get: { command.isEnabled },
                                set: {
                                    core.customCommandCoordinator.setCustomCommandEnabled(
                                        $0, id: command.id)
                                }),
                            onEdit: { editor = EditorTarget(command: command) },
                            onDelete: { pendingDeletion = command })
                    }
                }
                Button {
                    editor = EditorTarget(command: nil)
                } label: {
                    SettingsRowTitle(
                        .commandsCustomCommands, settings.text(CustomCommandsKey.settingsAdd))
                }
                Button {
                    Task { await core.customCommandCoordinator.importScriptDirectory() }
                } label: {
                    SettingsRowTitle(
                        .commandsCustomCommands, settings.text(CustomCommandsKey.settingsImport))
                }
            } footer: {
                Text(settings.text(CustomCommandsKey.settingsImportFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.customCommandsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
        .settingsEditorPanel(item: $editor) { target in
            CustomCommandEditorPanel(command: target.command)
        }
        .alert(item: $pendingDeletion) { command in
            Alert(
                title: Text(
                    String(
                        format: settings.text(CustomCommandsKey.deleteTitle), command.name)),
                message: Text(settings.text(CustomCommandsKey.deleteMessage)),
                primaryButton: .destructive(Text(settings.text(CustomCommandsKey.deleteAction))) {
                    core.customCommandCoordinator.deleteCustomCommand(id: command.id)
                },
                secondaryButton: .cancel())
        }
    }

    /// 按名称不区分大小写排序后的命令列表。
    private var sortedCommands: [CustomCommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

/// 编辑面板的展示目标；`command` 为 nil 表示新增。
private struct EditorTarget: Identifiable {
    let id = UUID()
    let command: CustomCommand?
}

/// 设置面板中的单条自定义命令行：别名、快捷键、编辑/删除与启用开关。
private struct CustomCommandSettingsRow: View {
    let command: CustomCommand
    let showsInLauncher: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: command.name, subtitle: command.command) {
            Image(systemName: command.symbol)
        } trailing: {
            // 别名只有经由启动器条目才参与排序，因此随该条目一同置灰。
            AliasField(key: command.entryID, name: command.name)
                .settingsEnabled(command.isEnabled && showsInLauncher)

            // 已禁用命令的快捷键只会撞上运行入口的拒绝逻辑，因此同样置灰。
            ShortcutRecorder(action: .customCommand(id: command.id))
                .settingsEnabled(command.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(settings.text(CustomCommandsKey.rowEdit))
            .accessibilityLabel(
                String(format: settings.text(CustomCommandsKey.rowEditNamed), command.name))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(settings.text(CustomCommandsKey.rowDelete))
            .accessibilityLabel(
                String(format: settings.text(CustomCommandsKey.rowDeleteNamed), command.name))

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(settings.text(CustomCommandsKey.rowEnabled))
                .accessibilityLabel(
                    String(format: settings.text(CustomCommandsKey.rowEnableNamed), command.name))
        }
    }
}
