// 文件职责：构建设置面板中的 MCP 服务器分区，展示开关、服务器列表及编辑/删除入口。
// 分层：Settings（SwiftUI View）；通过 MCPCoordinator 调节后端，不直接操作存储。
import SwiftUI

/// 设置 → AI 的 MCP 部分：总开关、服务器列表，以及每个服务器当前的状态。
struct MCPSettingsSection: View {
    @Environment(MCPCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var appSettings
    @Environment(MCPSettingsStore.self) private var store
    @State private var editor: MCPServerEditorTarget?
    @State private var pendingRemoval: MCPServer?
    @State private var removalError: String?

    var body: some View {
        @Bindable var appSettings = appSettings
        Section {
            Toggle(isOn: $appSettings.mcpEnabled) {
                SettingsRowTitle(.aiMCPServers, appSettings.text(MCPKey.enableServers))
            }
            Group {
                if store.servers.isEmpty {
                    Text(appSettings.text(MCPKey.emptyState))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.servers) { server in
                        MCPServerRow(
                            server: server, status: coordinator.status(of: server.id),
                            onEdit: { editor = MCPServerEditorTarget(server: server, isNew: false) },
                            onRemove: { pendingRemoval = server })
                    }
                }
                Button {
                    editor = MCPServerEditorTarget(server: MCPServer(), isNew: true)
                } label: {
                    Label {
                        SettingsRowTitle(.aiMCPServers, appSettings.text(MCPKey.addServer))
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .settingsEnabled(appSettings.mcpEnabled)
            if let removalError {
                Label(removalError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            SettingsSectionHeader(.aiMCPServers)
        } footer: {
            Text(appSettings.text(MCPKey.sectionFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsEditorPanel(item: $editor) { target in
            MCPServerEditor(target: target, onSave: save, onCancel: { editor = nil })
        }
        .confirmationDialog(
            String(
                format: appSettings.text(MCPKey.removeDialogTitle),
                pendingRemoval?.title ?? appSettings.text(MCPKey.removeThisServer)),
            isPresented: removalBinding,
            presenting: pendingRemoval
        ) { server in
            Button(appSettings.text(MCPKey.remove), role: .destructive) { remove(server) }
        } message: { _ in
            Text(appSettings.text(MCPKey.removeDialogMessage))
        }
    }

    /// 控制删除确认弹窗显示与否的绑定。
    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// 返回非 nil 消息时在面板中展示；返回 nil 则关闭面板。
    private func save(_ server: MCPServer, _ secrets: MCPSecretStore.Secrets) -> String? {
        do {
            try coordinator.save(server, secrets: secrets)
        } catch {
            return appSettings.text(MCPKey.saveKeychainFailed)
        }
        editor = nil
        return nil
    }

    /// 删除服务器及其凭证；凭证删除失败时保留配置并展示错误。
    private func remove(_ server: MCPServer) {
        pendingRemoval = nil
        do {
            try coordinator.remove(server.id)
            removalError = nil
        } catch {
            removalError = String(
                format: appSettings.text(MCPKey.removeKeychainFailed), server.title)
        }
    }
}

private struct MCPServerRow: View {
    /// 单个已配置服务器的行视图，由父级提供状态与回调。
    let server: MCPServer
    let status: MCPServerStatus
    let onEdit: () -> Void
    let onRemove: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: server.title, subtitle: subtitle) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.primary)
        } trailing: {
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help(String(format: settings.text(MCPKey.editServer), server.title))
                .accessibilityLabel(String(format: settings.text(MCPKey.editServer), server.title))
            Button(action: onRemove) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(String(format: settings.text(MCPKey.removeServer), server.title))
            .accessibilityLabel(String(format: settings.text(MCPKey.removeServer), server.title))
        }
    }

    /// 把 slug 放在最前，因为它是用户需要亲手输入到输入框里的那部分。
    private var subtitle: String {
        let state =
            server.isEnabled ? status.label(settings.language) : settings.text(MCPKey.statusDisabled)
        return "@\(server.slug) · \(state) · \(server.transport.summary)"
    }
}
