// 文件职责：渲染 Quicklinks 设置页，管理启用开关、命令、列表（搜索/编辑/删除）、全局行为与导入导出。
// 分层：Settings/UI；SwiftUI 视图，数据来自 QuicklinkStore 与 AppSettings，操作经 AppCore 的 quicklinkCoordinator。
import SwiftUI

/// Quicklink 库，以及适用于所有条目的全局行为设置。
struct QuicklinksSettingsView: View {
    @Environment(QuicklinkStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var editor: QuicklinkEditRequest?
    @State private var pendingDeletion: Quicklink?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .quicklinksQuicklinks,
                enableTitle: settings.text(QuicklinksKey.settingsEnableTitle),
                enableSubtitle: settings.text(QuicklinksKey.settingsEnableSubtitle),
                isEnabled: $settings.quicklinksEnabled,
                showsInLauncher: $settings.quicklinksShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                if !store.isAvailable { storageNotice }
                FeatureCommandsSection(owner: .quicklinks, anchor: .quicklinksCommands)
                library
                behaviour
                transfer
            }
            .settingsEnabled(settings.quicklinksEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quicklinks)
        .settingsEditorPanel(item: $editor) { request in
            QuicklinkEditorPanel(quicklink: request.quicklink)
        }
        .onChange(of: core.pendingQuicklinkEdit?.id, initial: true) { _, _ in
            guard let request = core.pendingQuicklinkEdit else { return }
            editor = request
            core.pendingQuicklinkEdit = nil
        }
        .alert(item: $pendingDeletion) { quicklink in
            Alert(
                title: Text(
                    String(
                        format: settings.text(QuicklinksKey.deleteTitle), quicklink.name)),
                message: Text(settings.text(QuicklinksKey.deleteMessage)),
                primaryButton: .destructive(Text(settings.text(QuicklinksKey.deleteAction))) {
                    Task {
                        await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id, confirming: false)
                    }
                },
                secondaryButton: .cancel())
        }
    }

    // MARK: - Sections

    /// 数据库不可用时的提示区块。
    private var storageNotice: some View {
        Section {
            Label(
                settings.text(QuicklinksKey.storageNotice),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    /// Quicklink 列表区块：搜索框、条目行与新增按钮。
    @ViewBuilder
    private var library: some View {
        Section {
            if !store.quicklinks.isEmpty {
                SettingsFilterField(
                    prompt: settings.text(QuicklinksKey.searchPlaceholder), query: $query)
            }
            if results.isEmpty {
                Text(
                    store.quicklinks.isEmpty
                        ? settings.text(QuicklinksKey.emptyList)
                        : String(format: settings.text(QuicklinksKey.noMatch), query)
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(results) { quicklink in
                    QuicklinkSettingsRow(
                        quicklink: quicklink,
                        isEnabled: Binding(
                            get: { quicklink.isEnabled },
                            set: {
                                core.quicklinkCoordinator.setQuicklinkEnabled($0, id: quicklink.id)
                            }),
                        onEdit: { editor = QuicklinkEditRequest(quicklink: quicklink) },
                        onDelete: { pendingDeletion = quicklink })
                }
            }
            Button {
                editor = QuicklinkEditRequest(quicklink: nil)
            } label: {
                SettingsRowTitle(.quicklinksQuicklinks, settings.text(QuicklinksKey.addQuicklink))
            }
        }
    }

    /// 全局行为设置区块。
    private var behaviour: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.quicklinkOpensNewWindow) {
                SettingsRowTitle(.quicklinksBehaviour, settings.text(QuicklinksKey.openNewWindow))
                Text(settings.text(QuicklinksKey.openNewWindowDetail))
            }
            Picker(selection: $settings.quicklinkSelectionFallback) {
                ForEach(QuicklinkSelectionFallback.allCases) { option in
                    Text(option.localizedTitle(settings.language)).tag(option)
                }
            } label: {
                SettingsRowTitle(.quicklinksBehaviour, settings.text(QuicklinksKey.noSelection))
                Text(settings.text(QuicklinksKey.noSelectionDetail))
            }
            Toggle(isOn: $settings.quicklinkConfirmsBeforeDelete) {
                SettingsRowTitle(.quicklinksBehaviour, settings.text(QuicklinksKey.confirmDelete))
                Text(settings.text(QuicklinksKey.confirmDeleteDetail))
            }
        } header: {
            SettingsSectionHeader(.quicklinksBehaviour)
        }
    }

    /// 导入导出区块。
    private var transfer: some View {
        Section {
            LabeledContent {
                Button(settings.text(QuicklinksKey.importAction)) {
                    Task { await core.quicklinkCoordinator.importQuicklinks() }
                }
            } label: {
                SettingsRowTitle(.quicklinksImportExport, settings.text(QuicklinksKey.importTitle))
                Text(settings.text(QuicklinksKey.importDetail))
            }
            LabeledContent {
                Button(settings.text(QuicklinksKey.exportAction)) {
                    Task { await core.quicklinkCoordinator.exportQuicklinks() }
                }
                .disabled(store.quicklinks.isEmpty)
            } label: {
                SettingsRowTitle(.quicklinksImportExport, settings.text(QuicklinksKey.exportTitle))
                Text(settings.text(QuicklinksKey.exportDetail))
            }
        } header: {
            SettingsSectionHeader(.quicklinksImportExport)
        }
    }

    /// 存储已按展示顺序输出，因此过滤后置顶项仍保持在最前。
    private var results: [Quicklink] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.quicklinks }
        return store.quicklinks.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.link.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Quicklinks 设置页中的单行，包含图标、别名、快捷键、编辑与删除操作及启用开关。
private struct QuicklinkSettingsRow: View {
    let quicklink: Quicklink
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: quicklink.name, subtitle: quicklink.link) {
            SymbolImage(
                name: quicklink.symbol,
                size: Theme.Size.settingsRowIcon - Theme.Spacing.xs
            )
            .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            if quicklink.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .help(settings.text(QuicklinksKey.rowPinned))
            }
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help(settings.text(QuicklinksKey.rowHidden))
            }

            // 别名只能经由根搜索切片进入排序，因此随该切片一同变灰。
            AliasField(key: quicklink.entryID, name: quicklink.name)
                .settingsEnabled(quicklink.isEnabled && quicklink.showsInRootSearch)

            // 禁用条目的快捷键会触发统一入口的拒绝逻辑，因此也一并变灰。
            ShortcutRecorder(action: .quicklink(id: quicklink.id))
                .settingsEnabled(quicklink.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(settings.text(QuicklinksKey.editQuicklink))
            .accessibilityLabel(
                String(format: settings.text(QuicklinksKey.editNamed), quicklink.name))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(settings.text(QuicklinksKey.deleteQuicklink))
            .accessibilityLabel(
                String(format: settings.text(QuicklinksKey.deleteNamed), quicklink.name))

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(settings.text(QuicklinksKey.rowEnabled))
                .accessibilityLabel(
                    String(format: settings.text(QuicklinksKey.rowEnableNamed), quicklink.name))
        }
    }
}
