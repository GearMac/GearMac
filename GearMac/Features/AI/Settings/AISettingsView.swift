// 文件职责：设置页的 AI 面板，聚合启用开关、Providers 入口、默认模型、聊天、会话与系统提示等分组。
// 分层：UI；从环境读取各 Store/Manager，改动经绑定写回，Providers 以 settingsEditorPanel 弹出。
import SwiftUI

/// 设置页的 AI 主面板。
struct AISettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    @State private var providersPresented = false

    /// 渲染 AI 设置表单与 Providers 弹出面板，并在相关状态变化时同步模型选择。
    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .aiAI, title: appSettings.text(AIKey.enableTitle),
                        subtitle: appSettings.text(AIKey.enableSubtitle))
                }
                SettingsRow(
                    title: appSettings.text(AIKey.providersTitle), subtitle: providerSummary,
                    anchor: .aiProviders
                ) {
                    Button(appSettings.text(AIKey.providersManage)) { providersPresented = true }
                }
            } header: {
                SettingsSectionHeader(.aiAI)
            }

            // Decisions 服务的是 Quick Actions 的 Decide 动作，有自己的开关，不随 aiEnabled 变灰。
            DecisionsSettingsSection()

            FeatureCommandsSection(owner: .ai, anchor: .aiCommands)
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                defaultModelSection
                chatSection
                conversationsSection
                systemPromptSection
                MCPSettingsSection()
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
        .onAppear {
            core.applyInstalledAILifecycle()
        }
        // 在面板已打开时打开开关，否则提供方状态会一直为空。
        .onChange(of: appSettings.aiEnabled) { core.applyInstalledAILifecycle() }
        .onChange(of: settings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            syncSelection()
        }
        .onChange(of: subscription.models) { syncSelection() }
        .onChange(of: subscription.phase) { syncSelection() }
        .onChange(of: installedAI.statuses) { syncSelection() }
    }

    /// 默认模型分组，含本机模型不可用时的提示。
    private var defaultModelSection: some View {
        Section {
            // 未做任何配置的 Mac，正是需要提醒它免费路由已关闭的那个。
            if let reason = appleIntelligenceReason {
                Label(reason, systemImage: "apple.intelligence")
                    .foregroundStyle(.secondary)
            }
            AIModelSelectionRows(
                selection: settings.defaultModel,
                select: { $0.map(settings.select) },
                modelLabel: {
                    SettingsRowTitle(.aiDefault, appSettings.text(AIKey.defaultModel))
                },
                effortLabel: {
                    SettingsRowTitle(.aiDefault, appSettings.text(AIKey.reasoningEffort))
                }
            )
        } header: {
            SettingsSectionHeader(.aiDefault)
        } footer: {
            Text(defaultModelFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 默认模型分组的底部说明。
    private var defaultModelFooter: String {
        if settings.defaultModel?.isOnDevice == true {
            return appSettings.text(AIKey.defaultFooterOnDevice)
        }
        return settings.defaultModel == nil
            ? appSettings.text(AIKey.defaultFooterNone)
            : appSettings.text(AIKey.defaultFooterSelected)
    }

    /// 本机路由未出现在选择器中的原因；存在时返回 nil。
    private var appleIntelligenceReason: String? {
        guard !settings.isAppleIntelligenceAvailable() else { return nil }
        // macOS 15 上该路由整体不展示，选择器缺失也无需解释；26 上其他不可用原因照旧说明。
        let status = AppleIntelligenceProvider.status()
        return status == .requiresNewerSystem ? nil : status.message
    }

    /// Providers 行的摘要：当前已就绪的外部提供方。
    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.managedCLIKinds
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(
                count == 1
                    ? appSettings.text(AIKey.apiConnectionOne)
                    : String(format: appSettings.text(AIKey.apiConnectionMany), count))
        }
        return providers.isEmpty
            ? appSettings.text(AIKey.noExternalProviders)
            : providers.joined(separator: ", ")
    }

    /// 让已保存的默认模型与各提供方的当前状态对齐。
    private func syncSelection() {
        settings.reconcile(subscription: subscription, installedAI: installedAI)
    }

    /// 聊天分组：联网搜索开关与工具调用轮数。
    private var chatSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.webSearchEnabled) {
                SettingsRowTitle(.aiChat, appSettings.text(AIKey.webSearch))
                Text(appSettings.text(AIKey.webSearchSubtitle))
            }
            Picker(selection: $settings.toolRounds) {
                ForEach(AIToolRounds.allCases) { Text($0.title(appSettings.language)).tag($0) }
            } label: {
                SettingsRowTitle(.aiChat, appSettings.text(AIKey.toolRounds))
                Text(appSettings.text(AIKey.toolRoundsSubtitle))
            }
        } header: {
            SettingsSectionHeader(.aiChat)
        }
    }

    /// 会话分组：打开位置、新会话间隔与保留策略。
    private var conversationsSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text($0.title(appSettings.language)).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, appSettings.text(AIKey.opensTo))
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) {
                        Text($0.title(appSettings.language)).tag($0)
                    }
                } label: {
                    SettingsRowTitle(.aiConversations, appSettings.text(AIKey.newChatAfter))
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title(appSettings.language)).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, appSettings.text(AIKey.retention))
                Text(appSettings.text(AIKey.retentionSubtitle))
            }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text(appSettings.text(AIKey.conversationsFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 系统提示分组：开关与提示词编辑器。
    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, appSettings.text(AIKey.systemPromptEnable))
                Text(appSettings.text(AIKey.systemPromptEnableSubtitle))
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text(appSettings.text(AIKey.systemPromptFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
