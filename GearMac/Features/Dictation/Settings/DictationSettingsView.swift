// 文件职责：听写功能的设置界面，配置启用状态、快捷键、模型、内存释放、麦克风与输出方式。
// 分层：UI/SwiftUI；只读写 AppSettings 并调用 Coordinator，不直接触碰底层服务。
import AppKit
import AVFoundation
import SwiftUI

/// 听写设置页面。
struct DictationSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var microphones: [AVCaptureDevice] = []
    @State private var modelSize: Int64?
    @State private var microphoneAccess = Permissions.microphoneAccess()
    /// 设置表单：按启用状态分节展示快捷键、模型、内存与输出选项。
    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .dictationDictation,
                        title: settings.text(DictationKey.enableTitle),
                        subtitle: settings.text(DictationKey.enableSubtitle))
                }
                if microphoneAccess != .authorized {
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: SettingsListMetrics.iconSize)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(settings.text(DictationKey.micRequiredTitle))
                                .foregroundStyle(.orange)
                            Text(settings.text(DictationKey.micRequiredSubtitle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.lg)
                        Button(
                            microphoneAccess == .notDetermined
                                ? settings.text(DictationKey.micGrantAccess)
                                : settings.text(DictationKey.micOpenSettings)
                        ) {
                            if microphoneAccess == .notDetermined {
                                Task {
                                    _ = await Permissions.requestMicrophoneAccess()
                                    microphoneAccess = Permissions.microphoneAccess()
                                }
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                    }
                }
            }
            .settingsAnchor(.dictationDictation)

            if settings.dictationEnabled {
                Section {
                    Picker(selection: $settings.dictationMode) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.title(settings.language)).tag(mode)
                        }
                    } label: {
                        SettingsRowTitle(.dictationCommands, settings.text(DictationKey.shortcutBehavior))
                    }
                    HStack {
                        SettingsRowTitle(.dictationCommands, settings.text(DictationKey.shortcut))
                        Spacer()
                        ShortcutRecorder(action: .dictation)
                    }
                    if settings.dictationMode == .pushToTalk {
                        let issue = coordinator.holdShortcutIssue
                        Text(issue ?? settings.text(DictationKey.shortcutHoldHint))
                        .font(.caption)
                        .foregroundStyle(issue == nil ? Color.secondary : Color.orange)
                    }
                } header: {
                    SettingsSectionHeader(.dictationCommands)
                }

                Section {
                    Picker(selection: familyBinding) {
                        ForEach(DictationModel.Family.allCases) { family in
                            Text(family.rawValue).tag(family)
                        }
                    } label: {
                        SettingsRowTitle(.dictationModel, settings.text(DictationKey.engine))
                        Text(
                            settings.dictationModel.family.summary(settings.language) + " · "
                                + settings.dictationModel.coverage(settings.language))
                    }
                    Picker(selection: $settings.dictationModel) {
                        ForEach(
                            DictationModel.allCases.filter { $0.family == settings.dictationModel.family }
                        ) { model in
                            Text(model.variantTitle).tag(model)
                        }
                    } label: {
                        SettingsRowTitle(.dictationModel, settings.text(DictationKey.model))
                        Text(settings.dictationModel.summary(settings.language))
                    }

                    let installed = coordinator.models.isInstalled(settings.dictationModel)
                    let downloading = coordinator.models.downloading == settings.dictationModel
                    LabeledContent {
                        if downloading {
                            Button(settings.text(DictationKey.buttonCancel)) {
                                coordinator.models.cancelDownload()
                            }
                        } else if installed {
                            Button(settings.text(DictationKey.buttonRemove)) {
                                removeModel(settings.dictationModel)
                            }
                            .disabled(
                                coordinator.models.transcribing || coordinator.models.removing != nil)
                        } else {
                            Button(settings.text(DictationKey.buttonDownload)) {
                                downloadModel(settings.dictationModel)
                            }
                            .disabled(
                                coordinator.models.downloading != nil
                                    || coordinator.models.removing == settings.dictationModel)
                        }
                    } label: {
                        Text(
                            downloading
                                ? settings.text(DictationKey.stateDownloading)
                                : installed
                                    ? settings.text(DictationKey.stateInstalled)
                                    : settings.text(DictationKey.stateNotInstalled))
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(modelDescription)
                            if downloading {
                                if let progress = coordinator.models.downloadProgress, progress.total > 0 {
                                    ProgressView(
                                        value: Double(progress.received), total: Double(progress.total)
                                    )
                                    .accessibilityLabel(settings.text(DictationKey.downloadProgress))
                                    Text(
                                        String(
                                            format: settings.text(
                                                DictationKey.downloadProgressDetail),
                                            "\(progress.received / 1_000_000)",
                                            "\(progress.total / 1_000_000)")
                                    )
                                    .monospacedDigit()
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    if settings.dictationModel.isQwen, installed {
                        Picker(selection: languageBinding) {
                            Text(settings.text(DictationKey.modelAuto)).tag("")
                            Divider()
                            ForEach(DictationLanguage.allCases) { language in
                                Text(language.displayName(settings.language)).tag(language.rawValue)
                            }
                        } label: {
                            SettingsRowTitle(.dictationModel, settings.text(DictationKey.modelLanguage))
                        }
                    }
                } header: {
                    SettingsSectionHeader(.dictationModel)
                }

                Section {
                    Picker(selection: $settings.dictationIdleRelease) {
                        ForEach(DictationIdleRelease.allCases) { option in
                            Text(option.title(settings.language)).tag(option)
                        }
                    } label: {
                        SettingsRowTitle(.dictationMemory, settings.text(DictationKey.memoryTitle))
                    }
                } header: {
                    SettingsSectionHeader(.dictationMemory)
                } footer: {
                    Text(settings.text(DictationKey.memoryFooter))
                }

                Section {
                    Picker(selection: microphoneBinding) {
                        Text(
                            microphones.isEmpty
                                ? settings.text(DictationKey.outputNoMicrophone)
                                : settings.text(DictationKey.outputSystemDefault)
                        )
                        .tag("")
                        if !microphones.isEmpty { Divider() }
                        ForEach(microphones, id: \.uniqueID) { microphone in
                            Text(microphone.localizedName).tag(microphone.uniqueID)
                        }
                    } label: {
                        SettingsRowTitle(.dictationOutput, settings.text(DictationKey.outputMicrophone))
                    }
                    Picker(selection: $settings.dictationDestination) {
                        ForEach(DictationDestination.allCases) { destination in
                            Text(destination.title(settings.language)).tag(destination)
                        }
                    } label: {
                        SettingsRowTitle(
                            .dictationOutput, settings.text(DictationKey.outputWhenFinished))
                    }
                    Toggle(isOn: $settings.dictationAdaptsCapitalization) {
                        SettingsRowTitle(
                            .dictationOutput, settings.text(DictationKey.outputAdaptCapitalization))
                        Text(settings.text(DictationKey.outputAdaptCapitalizationSubtitle))
                    }
                } header: {
                    SettingsSectionHeader(.dictationOutput)
                } footer: {
                    Text(settings.text(DictationKey.outputFooter))
                }

            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.dictation)
        .onAppear {
            microphoneAccess = Permissions.microphoneAccess()
            if settings.dictationEnabled { microphones = DictationCapture.microphones }
        }
        .onChange(of: settings.dictationEnabled) { _, enabled in
            if enabled { microphones = DictationCapture.microphones }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
                if settings.dictationEnabled { microphones = DictationCapture.microphones }
            }
        }
        .task(id: settings.dictationEnabled ? settings.dictationModel : nil) {
            modelSize = nil
            guard settings.dictationEnabled else { return }
            coordinator.models.refreshInstalledModels()
            await refreshModelSize(settings.dictationModel)
        }
    }

    /// 启用开关绑定：交由 coordinator 处理权限与确认流程。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationEnabled },
            set: { coordinator.setEnabled($0) })
    }

    /// 麦克风选择绑定：空字符串映射为 nil（系统默认）。
    private var microphoneBinding: Binding<String> {
        Binding(
            get: { settings.dictationMicrophone ?? "" },
            set: { settings.dictationMicrophone = $0.isEmpty ? nil : $0 })
    }

    /// 族系切换绑定：换族系时回落到该族系的默认变体。
    private var familyBinding: Binding<DictationModel.Family> {
        Binding(
            get: { settings.dictationModel.family },
            set: {
                settings.dictationModel = $0 == .parakeet ? .redux : .qwenSmall
            })
    }

    /// 语言选择绑定：空字符串表示自动检测。
    private var languageBinding: Binding<String> {
        Binding(
            get: { settings.dictationLanguage ?? "" },
            set: {
                settings.dictationLanguage = $0.isEmpty ? nil : $0
            })
    }

    /// 模型体积说明：已安装时显示实际占用，否则显示预估。
    private var modelDescription: String {
        guard let modelSize else {
            return String(
                format: settings.text(DictationKey.sizeAboutInstalled),
                settings.dictationModel.approximateInstalledMegabytes)
        }
        return String(
            format: settings.text(DictationKey.sizeOnDisk),
            ByteCountFormatter.string(fromByteCount: modelSize, countStyle: .file))
    }

    /// 后台统计模型体积，并仅在参数未变时写回状态。
    private func refreshModelSize(_ model: DictationModel) async {
        let size = await coordinator.models.installedSize(model)
        if !Task.isCancelled, settings.dictationModel == model { modelSize = size }
    }

    /// 触发下载并在结束后刷新体积。
    private func downloadModel(_ model: DictationModel) {
        Task {
            await coordinator.downloadModel(model)
            await refreshModelSize(model)
        }
    }

    /// 触发删除并在结束后刷新体积。
    private func removeModel(_ model: DictationModel) {
        Task {
            await coordinator.removeModel(model)
            await refreshModelSize(model)
        }
    }
}
