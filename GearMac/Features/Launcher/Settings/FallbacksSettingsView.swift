// 文件职责：设置 ▸ 兜底项页面，控制哪些命令参与输入查询的兜底提示及其顺序。
// 分层：UI（SwiftUI）；只驱动 FallbackStore 与 FallbackCoordinator，不自行保存状态。
import SwiftUI

/// 设置 ▸ 兜底项：输入型查询可以兜底到哪些命令，以及它们的顺序。
struct FallbacksSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    /// 观察该存储，使重排或勾选后列表能在触发它的按钮下方重绘。
    @Environment(FallbackStore.self) private var store

    private var fallbacks: [Fallback] { core.fallbackCoordinator.available }

    var body: some View {
        Form {
            Section {
                let fallbacks = fallbacks
                if fallbacks.isEmpty {
                    Text(settings.text(LauncherKey.fallbacksNothingToOffer))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(fallbacks.enumerated()), id: \.element) { index, fallback in
                        FallbackRow(fallback: fallback, order: fallbacks, index: index)
                    }
                }
            } header: {
                SettingsSectionHeader(.fallbacksFallbacks)
            } footer: {
                Text(settings.text(LauncherKey.fallbacksFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fallbacks)
        .releasesFocusOnOutsideClick()
    }
}

/// 兜底项列表中的一行：图标、名称、上下移动按钮与启用复选框。
private struct FallbackRow: View {
    let fallback: Fallback
    /// 当前可见顺序；移动时保存全部 id，而不只是交换的那两个。
    let order: [Fallback]
    let index: Int

    @Environment(AppCore.self) private var core
    @Environment(FallbackStore.self) private var store

    var body: some View {
        if let entry = core.fallbackCoordinator.entry(for: fallback) {
            SettingsRow(title: entry.name, subtitle: entry.kindLabel(core.settings.language)) {
                AppIconView(app: entry)
                    .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
            } trailing: {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .accessibilityLabel(
                    String(format: core.settings.text(LauncherKey.moveUpFormat), entry.name))
                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == order.count - 1)
                .accessibilityLabel(
                    String(format: core.settings.text(LauncherKey.moveDownFormat), entry.name))
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(
                        String(format: core.settings.text(LauncherKey.offerAsFallbackFormat), entry.name))
            }
        }
    }

    /// 按给定偏移量与相邻项交换位置，越界时忽略。
    private func move(by delta: Int) {
        guard order.indices.contains(index + delta) else { return }
        store.exchange(fallback, with: order[index + delta], in: order)
    }

    /// 与该兜底项启用状态双向绑定的 Binding。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(fallback) },
            set: { store.setEnabled($0, for: fallback) }
        )
    }
}
