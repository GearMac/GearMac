// 文件职责：窗口管理设置主视图，串联开关、循环方式、间距、快捷键预设、布局/房间/自定义尺寸区块与各窗口命令。
// 分层：UI（SwiftUI 设置页）；通过 AppCore / AppSettings / 各 Coordinator 触发副作用，不亲自操作窗口。
import SwiftUI

/// 窗口管理设置页：把窗口相关的各设置区块与命令列表组装成一个 Form。
struct WindowManagementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    /// 当前打开的布局编辑器请求；nil 表示弹窗关闭。
    @State private var editor: WindowLayoutEditRequest?
    /// 等确认删除的布局。
    @State private var pendingDeletion: WindowLayout?
    /// 当前打开的自定义尺寸编辑器请求。
    @State private var customSizeEdit: CustomWindowSizeEditRequest?
    /// 待应用的快捷键预设（需点“应用”才生效）。
    @State private var chosenPreset: WindowShortcutPreset?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .windowManagementWindowManagement,
                enableTitle: settings.text(WindowKey.settingsEnableTitle),
                enableSubtitle: settings.text(WindowKey.settingsEnableSubtitle),
                isEnabled: $settings.windowManagementEnabled,
                showsInLauncher: $settings.windowManagementShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                options
                WindowLayoutsSection(
                    onEdit: { editor = WindowLayoutEditRequest(layout: $0) },
                    onDelete: { pendingDeletion = $0 })
                RoomsSection()
                FeatureCommandsSection(
                    owner: .windowManagement, anchor: .windowManagementLayoutCommands)
                CustomWindowSizesSection(onEdit: {
                    customSizeEdit = CustomWindowSizeEditRequest(size: $0)
                })
                commands
            }
            .settingsEnabled(settings.windowManagementEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowManagement)
        .settingsEditorPanel(item: $editor) { request in
            WindowLayoutEditorPanel(request: request)
        }
        .onChange(of: core.pendingWindowLayoutEdit?.id, initial: true) { _, _ in
            guard let request = core.pendingWindowLayoutEdit else { return }
            editor = request
            core.pendingWindowLayoutEdit = nil
        }
        .settingsEditorPanel(item: $customSizeEdit) { request in
            CustomWindowSizeEditorPanel(request: request)
        }
        .alert(item: $pendingDeletion) { layout in
            Alert(
                title: Text(
                    String(
                        format: settings.text(WindowKey.deleteTitle), layout.name)),
                message: Text(settings.text(WindowKey.settingsDeleteLayoutMessage)),
                primaryButton: .destructive(Text(settings.text(WindowKey.actionDelete))) {
                    core.windowLayoutCoordinator.deleteWindowLayout(id: layout.id)
                },
                secondaryButton: .cancel())
        }
    }

    /// 窗口循环、间距与快捷键预设三个选项行。
    private var options: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.windowCycle) {
                ForEach(WindowCycle.allCases) { cycle in
                    Text(cycle.localizedTitle(settings.resolvedLanguage)).tag(cycle)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, settings.text(WindowKey.settingsCycling))
                Text(settings.windowCycle.localizedDetail(settings.resolvedLanguage))
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(settings.windowGap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        settings.text(WindowKey.settingsGap), value: $settings.windowGap,
                        in: WindowPlacementEngine.gapRange, step: 2
                    )
                    .labelsHidden()
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, settings.text(WindowKey.settingsGap))
                Text(settings.text(WindowKey.settingsGapDetail))
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Picker(settings.text(WindowKey.settingsShortcutPreset), selection: $chosenPreset) {
                        Text(settings.text(WindowKey.settingsChoose)).tag(WindowShortcutPreset?.none)
                        ForEach(WindowShortcutPreset.allCases) { preset in
                            Text(preset.localizedTitle(settings.resolvedLanguage))
                                .tag(Optional(preset))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(settings.text(WindowKey.settingsApply)) {
                        guard let chosenPreset else { return }
                        Task { await core.windowShortcutPresetCoordinator.apply(chosenPreset) }
                    }
                    // 判定完全由绑定值决定：已应用的预设一旦被改动，按钮就会重新可用。
                    .disabled(
                        chosenPreset == nil
                            || chosenPreset == core.windowShortcutPresetCoordinator.matchingPreset)
                }
            } label: {
                SettingsRowTitle(
                    .windowManagementOptions, settings.text(WindowKey.settingsShortcutPreset))
                Text(settings.text(WindowKey.settingsShortcutPresetDetail))
            }
        } header: {
            SettingsSectionHeader(.windowManagementOptions)
        }
    }

    /// 目录中的每个分组各成一段，标题由侧边栏自身分组给出。
    private var commands: some View {
        ForEach(WindowCommandCatalog.grouped(), id: \.group) { section in
            Section {
                ForEach(section.commands) { command in
                    WindowCommandSettingsRow(command: command)
                }
            } header: {
                Text(section.group.localizedTitle(settings.resolvedLanguage))
            }
        }
    }
}

/// 单个命令的快捷键录制器与可见性勾选框，样式与快捷键行保持一致。
private struct WindowCommandSettingsRow: View {
    let command: WindowCommand
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: command.localizedTitle(settings.resolvedLanguage)) {
            Image(systemName: command.sfSymbol)
        } trailing: {
            ShortcutRecorder(action: .windowCommand(id: command.id))

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(
                        format: settings.text(WindowKey.actionShowInLauncher),
                        command.localizedTitle(settings.resolvedLanguage)))
        }
    }

    /// `VisibilityStore` 以 entry 为键，因此这里构造与 `AppIndex` 发布的一致条目。
    private var entry: AppEntry {
        AppEntry(
            id: command.entryID, name: command.name,
            url: URL(string: "gearmac://window-command/" + command.id.rawValue)!, bundleID: nil,
            kind: .windowCommand)
    }

    /// 把命令包装成与索引一致的 AppEntry 后读写 VisibilityStore。
    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
