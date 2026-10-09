// 文件职责：实现快捷动作的设置面板：启用开关、动作列表、模型路由、目标语言与指令编辑。
// 分层：UI/Settings；与 AI 面板同级而非其子分区，仅借用 provider 层。
import Combine
import SwiftUI

/// 与 AI 面板平级，而非它的一个分区：只借用 provider 层。
struct QuickActionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(QuickActionSettingsStore.self) private var store
    @Environment(CustomQuickActionStore.self) private var customActions
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(VisibilityStore.self) private var visibility

    /// 像 Permissions 面板一样轮询：授权在系统设置里完成，不会向应用发通知。
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    @State private var editingAction: BuiltInQuickAction?
    @State private var customEditing: CustomQuickActionEditRequest?
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .quickActionsQuickActions,
                        title: appSettings.text(QuickActionsKey.settingsEnableTitle),
                        subtitle: appSettings.text(QuickActionsKey.settingsEnableSubtitle))
                }
                if appSettings.quickActionsEnabled, !isTrusted {
                    // 没有它每个快捷键都会失败；在这里说明比用户按了一次才发现要好。
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: Theme.Size.settingsRowIcon)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(appSettings.text(QuickActionsKey.settingsAccessTitle))
                                .foregroundStyle(.orange)
                            Text(appSettings.text(QuickActionsKey.settingsAccessSubtitle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.lg)
                        Button(appSettings.text(QuickActionsKey.settingsOpenSystemSettings)) {
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.quickActionsQuickActions)
            }

            Group {
                actionsSection
                modelSection
                languageSection
            }
            .settingsEnabled(appSettings.quickActionsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quickActions)
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
        .settingsEditorPanel(item: $editingAction) { action in
            InstructionsEditorPanel(
                action: action,
                instructionOverride: store.settings.instructionOverride(for: action),
                modelOverride: store.modelOverride(for: .builtIn(action))
            ) { instructionOverride, modelOverride in
                store.settings.setInstructionOverride(instructionOverride, for: action)
                store.setModelOverride(modelOverride, for: .builtIn(action))
            }
        }
        .settingsEditorPanel(item: $customEditing) { request in
            CustomQuickActionEditorPanel(
                request: request,
                model: request.action.flatMap { store.modelOverride(for: .custom($0)) })
        }
        .onAppear {
            core.quickActionCoordinator.loadLanguages()
            store.repairModel(against: aiSettings.connections, fallback: aiSettings.defaultModel)
            store.resolveModel(
                appleIntelligenceAvailable: aiSettings.isAppleIntelligenceAvailable(),
                fallback: aiSettings.defaultModel)
            core.applyInstalledAILifecycle()
        }
        .onChange(of: appSettings.aiEnabled) { repairInstalledModel() }
        .onChange(of: aiSettings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            repairInstalledModel()
        }
        .onChange(of: core.chatGPTSubscription.models) { repairInstalledModel() }
        .onChange(of: core.chatGPTSubscription.phase) { repairInstalledModel() }
        .onChange(of: core.installedAI.statuses) { repairInstalledModel() }
    }

    /// 动作列表分区：内置动作 + 自建动作 + 新增入口。
    private var actionsSection: some View {
        Section {
            ForEach(BuiltInQuickAction.allCases.filter(\.isAvailable), content: builtInRow)
            ForEach(customActions.actions) { action in
                SettingsRow(title: action.name, subtitle: subtitle(for: .custom(action))) {
                    SymbolImage(name: action.symbol, size: Theme.Size.quickActionHeaderIcon)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    editButton(title: action.name) {
                        customEditing = CustomQuickActionEditRequest(action: action)
                    }
                    AliasField(key: action.entryID, name: action.name)
                    ShortcutRecorder(action: .quickAction(id: action.id), isQuiet: true)
                    resultPicker(title: action.name, selection: previewBinding(action))
                    launcherToggle(title: action.name, entry: AppEntry(action))
                }
            }
            Button {
                customEditing = CustomQuickActionEditRequest(action: nil)
            } label: {
                SettingsRowTitle(.quickActionsActions, appSettings.text(QuickActionsKey.settingsAddAction))
            }
        } header: {
            SettingsSectionHeader(.quickActionsActions)
        } footer: {
            Text(appSettings.text(QuickActionsKey.settingsFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 渲染一个内置动作的设置行。
    private func builtInRow(_ action: BuiltInQuickAction) -> some View {
        let entry = CommandCatalog.entry(for: CommandID(action))
        let title = action.localizedTitle(appSettings.language)
        return SettingsRow(title: title, subtitle: subtitle(for: .builtIn(action))) {
            Image(systemName: action.symbol)
                .frame(width: Theme.Size.settingsRowIcon)
        } trailing: {
            if action.takesInstructionOverride {
                editButton(title: title) { editingAction = action }
            }
            // 这四个动作随其类型一起从 Commands 面板迁走，别名输入框也随之迁移。
            if let entry { AliasField(entry: entry) }
            ShortcutRecorder(action: .command(CommandID(action)), isQuiet: true)
            resultPicker(title: title, selection: previewBinding(action))
                .disabled(action.alwaysPreviews)
            if let entry { launcherToggle(title: title, entry: entry) }
        }
    }

    /// 行尾的编辑（铅笔）按钮。
    private func editButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SymbolImage(name: "pencil", size: Theme.Size.quickActionHeaderIcon)
        }
        .buttonStyle(.plain)
        .help(String(format: appSettings.text(QuickActionsKey.settingsEditNamed), title))
        .accessibilityLabel(
            String(format: appSettings.text(QuickActionsKey.settingsEditNamed), title))
    }

    /// 结果处理方式选择器：替换 / 预览。
    private func resultPicker(title: String, selection: Binding<Bool>) -> some View {
        Picker("", selection: selection) {
            Text(appSettings.text(QuickActionsKey.settingsReplace)).tag(false)
            Text(appSettings.text(QuickActionsKey.settingsPreview)).tag(true)
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(
            String(format: appSettings.text(QuickActionsKey.settingsResultAccessibility), title))
    }

    /// 是否在启动器显示该条目的勾选框。
    private func launcherToggle(title: String, entry: AppEntry) -> some View {
        Toggle("", isOn: launcherBinding(entry))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel(
                String(format: appSettings.text(QuickActionsKey.settingsShowInLauncher), title))
    }

    /// 模型与推理强度分区。
    private var modelSection: some View {
        Section {
            AIModelSelectionRows(
                selection: store.model,
                select: store.select,
                modelLabel: {
                    SettingsRowTitle(.quickActionsModel, appSettings.text(QuickActionsKey.settingsModel))
                    Text(appSettings.text(QuickActionsKey.settingsModelDetail))
                },
                effortLabel: {
                    SettingsRowTitle(.quickActionsModel, appSettings.text(QuickActionsKey.settingsEffort))
                }
            )
        } header: {
            SettingsSectionHeader(.quickActionsModel)
        } footer: {
            Text(appSettings.text(QuickActionsKey.settingsModelFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 翻译目标语言分区。
    private var languageSection: some View {
        Section {
            Picker(selection: languageBinding) {
                Text(appSettings.text(QuickActionsKey.settingsSameAsMac)).tag("")
                ForEach(core.quickActionCoordinator.offeredLanguages, id: \.minimalIdentifier) {
                    Text(TextTranslator.displayName(of: $0)).tag($0.minimalIdentifier)
                }
            } label: {
                SettingsRowTitle(
                    .quickActionsTranslate, appSettings.text(QuickActionsKey.settingsTranslateTo))
            }
        } header: {
            SettingsSectionHeader(.quickActionsTranslate)
        } footer: {
            Text(appSettings.text(QuickActionsKey.settingsTranslateFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 行副标题：拼接“始终预览”与模型路由的简短摘要。
    private func subtitle(for action: QuickAction) -> String? {
        let details = [
            action.alwaysPreviews ? appSettings.text(QuickActionsKey.settingsAlwaysShown) : nil,
            store.modelOverride(for: action).map(routeTitle)
        ].compactMap(\.self)
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    /// 把模型选择渲染为标题（可带推理强度）。
    private func routeTitle(_ selection: AIModelSelection) -> String {
        let model = modelChoices.first { $0.matches(selection) }?.title ?? selection.model
        guard let effort = selection.effort else { return model }
        return "\(model) (\(ChatGPTSubscription.Effort(id: effort, detail: nil).title))"
    }

    /// 启用开关的绑定，写入时调用 Coordinator。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.quickActionsEnabled },
            set: { core.quickActionCoordinator.setEnabled($0) })
    }

    /// 内置动作的结果处理方式绑定。
    private func previewBinding(_ action: BuiltInQuickAction) -> Binding<Bool> {
        Binding(
            get: { store.settings.previewsResult(action) },
            set: { store.settings.setPreviewsResult($0, for: action) })
    }

    /// 自建动作的结果处理方式绑定。
    private func previewBinding(_ action: CustomQuickAction) -> Binding<Bool> {
        Binding(
            get: { action.previewsResult },
            set: { core.quickActionCoordinator.setPreviewsResult($0, id: action.id) })
    }

    /// 启动器可见性绑定。
    private func launcherBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }

    /// 目标语言绑定。
    private var languageBinding: Binding<String> {
        Binding(
            get: { store.settings.targetLanguage },
            set: { store.settings.targetLanguage = $0 })
    }

    /// 当前可选的模型列表（展平分组）。
    private var modelChoices: [AIModelOption] {
        AIModelOption.availableGroups(
            settings: aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI
        )
        .flatMap(\.options)
    }

    /// 修复已安装模型的可用性：收集当前不可用的来重，并让 store 修正路由。
    private func repairInstalledModel() {
        // 目录行只给出路由名而不含推理强度；修正后的选择必须带上默认强度。
        let options = modelChoices.map {
            AIModelOption.withDefaultEffort(
                $0.selection, settings: aiSettings, subscription: core.chatGPTSubscription,
                installedAI: core.installedAI)
        }
        var unavailable = Set<AIModelSource>()
        if !aiSettings.enabledInstalledProviders.contains(.codex)
            || core.chatGPTSubscription.phase == .signedOut
            || core.chatGPTSubscription.phase.isUnavailable
        {
            unavailable.insert(.codex)
        }
        for kind in InstalledAIKind.managedCLIKinds {
            let phase = core.installedAI.status(for: kind).phase
            guard
                !aiSettings.enabledInstalledProviders.contains(kind)
                    || phase == .signInRequired || phase == .notInstalled
            else { continue }
            unavailable.insert(kind.source)
        }
        store.repairInstalledModel(
            available: options, unavailableSources: unavailable,
            fallback: aiSettings.defaultModel)
    }

    /// 单个内置动作的指令覆盖编辑面板，未覆盖时展示内置指令。
    private struct InstructionsEditorPanel: View {
        @Environment(\.settingsEditorDismiss) private var dismiss
        @Environment(AppSettings.self) private var appSettings
        @State private var instructions: String
        @State private var model: AIModelSelection?

        let action: BuiltInQuickAction
        let builtIn: String
        let onSave: (String?, AIModelSelection?) -> Void

        init(
            action: BuiltInQuickAction, instructionOverride: String?,
            modelOverride: AIModelSelection?,
            onSave: @escaping (String?, AIModelSelection?) -> Void
        ) {
            self.action = action
            let builtIn = QuickActionPrompt.instructions(for: action)
            _instructions = State(initialValue: instructionOverride ?? builtIn)
            _model = State(initialValue: modelOverride)
            self.builtIn = builtIn
            self.onSave = onSave
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SettingsEditorHeader(
                    title: String(
                        format: appSettings.text(QuickActionsKey.settingsCustomizeTitle),
                        action.localizedTitle(appSettings.language)),
                    subtitle: String(
                        format: appSettings.text(QuickActionsKey.settingsCustomizeSubtitle),
                        action.localizedTitle(appSettings.language))
                )

                TextEditor(text: $instructions)
                    .font(.body)
                    .settingsEditorTextArea(height: Theme.Size.editorTextHeight * 2)

                QuickActionModelPicker(selection: $model)

                HStack(spacing: Theme.Spacing.md) {
                    Button(appSettings.text(QuickActionsKey.settingsUseDefault)) { instructions = builtIn }
                        .buttonStyle(.modalAction(.standard, fillsWidth: false))
                        .disabled(instructions == builtIn)
                    Spacer()
                    Button(appSettings.text(QuickActionsKey.settingsCancel)) { dismiss() }
                        .buttonStyle(.modalAction(.cancel))
                        .keyboardShortcut(.cancelAction)
                    Button(appSettings.text(QuickActionsKey.settingsSave)) {
                        onSave(instructions == builtIn ? nil : instructions, model)
                        dismiss()
                    }
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Spacing.dialogInset)
            .frame(width: Theme.Size.editorSheetWidth)
            .settingsEditorPanelSurface()
        }
    }
}
