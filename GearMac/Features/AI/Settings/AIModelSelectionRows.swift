// 文件职责：渲染默认模型与推理强度两个联动 Picker，选项按来源分组，供设置页选择默认模型及其 effort。
// 分层：UI；从环境读取 AISettingsStore / ChatGPTSubscriptionManager / InstalledAIManager，选项由 AIModelOption 计算。
import SwiftUI

/// 默认模型选择行：一个模型 Picker 与可选的推理强度 Picker。
struct AIModelSelectionRows<ModelLabel: View, EffortLabel: View>: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI
    @Environment(AppSettings.self) private var appSettings

    let selection: AIModelSelection?
    /// 把 nil 也作为一种可选值，供「空选择表示另一条路径」的调用方使用。
    var inheritedTitle: String?
    let select: (AIModelSelection?) -> Void
    @ViewBuilder let modelLabel: () -> ModelLabel
    @ViewBuilder let effortLabel: () -> EffortLabel

    /// 无可用来源时显示提示，否则渲染模型 Picker 与可选的推理强度 Picker。
    var body: some View {
        if modelGroups.isEmpty {
            Label(appSettings.text(AIKey.noProviderConfigured), systemImage: "sparkles")
                .foregroundStyle(.secondary)
        } else {
            Picker(selection: modelBinding) {
                if let inheritedTitle {
                    Text(inheritedTitle).tag(AIModelSelection?.none)
                    Divider()
                }
                ForEach(modelGroups) { group in
                    Section(group.title) {
                        ForEach(group.options) { option in
                            Text(option.title).tag(Optional(option.selection))
                        }
                    }
                }
            } label: {
                modelLabel()
            }
            if !efforts.isEmpty {
                Picker(selection: effortBinding) {
                    ForEach(efforts) { effort in
                        Text(effort.title).tag(effort.id)
                    }
                } label: {
                    effortLabel()
                }
            }
        }
    }

    /// 当前可选的分组模型列表。
    private var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: settings, subscription: subscription, installedAI: installedAI)
    }

    /// 当前选择对应的推理强度选项。
    private var efforts: [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: selection, settings: settings, subscription: subscription,
            installedAI: installedAI)
    }

    /// 模型 Picker 的绑定：设置选择时自动补齐默认推理强度，读取时忽略 effort。
    private var modelBinding: Binding<AIModelSelection?> {
        Binding(
            get: { selection?.withEffort(nil) },
            set: { value in
                select(
                    value.map {
                        AIModelOption.withDefaultEffort(
                            $0, settings: settings, subscription: subscription,
                            installedAI: installedAI)
                    })
            })
    }

    /// 推理强度 Picker 的绑定：写回所选模型上的 effort。
    private var effortBinding: Binding<String> {
        Binding(
            get: { selection?.effort ?? "" },
            set: { effort in
                guard let selection else { return }
                select(selection.withEffort(effort))
            })
    }
}
