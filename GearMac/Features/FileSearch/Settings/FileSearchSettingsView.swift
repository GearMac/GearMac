// 文件职责：「搜索文件」功能的设置界面：启用开关、命令区、搜索范围列表与忽略模式列表。
// 分层：Settings；SwiftUI 视图，直接读写 AppSettings。
import SwiftUI

/// 「搜索文件」设置页的根视图。
struct FileSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.fileSearchEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .fileSearchFileSearch,
                        title: settings.text(FileSearchKey.settingsToggleTitle),
                        subtitle: settings.text(FileSearchKey.settingsToggleSubtitle))
                }
            }
            .settingsAnchor(.fileSearchFileSearch)

            FeatureCommandsSection(owner: .fileSearch, anchor: .fileSearchCommands)
                .settingsEnabled(settings.fileSearchEnabled)
            FileSearchScopesSection()
                .settingsEnabled(settings.fileSearchEnabled)
            FileSearchIgnoreSection()
                .settingsEnabled(settings.fileSearchEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fileSearch)
    }
}

/// 搜索范围列表区段：展示、新增、删除与恢复默认范围。
private struct FileSearchScopesSection: View {
    @Environment(AppSettings.self) private var settings
    /// 仅在变化时重算：每次 body 渲染对每行都执行 `fileExists` 开销过大。
    @State private var missing: Set<String> = []

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var isDefault: Bool { settings.fileSearchScopes == FileSearchScope.defaultScopes }

    var body: some View {
        Section {
            ForEach(settings.fileSearchScopes, id: \.self) { scope in
                SettingsScopeRow(
                    scope: scope,
                    path: FileSearchScope.expand(scope, homeDirectory: home).path,
                    isMissing: missing.contains(scope)
                ) {
                    settings.fileSearchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button(settings.text(FileSearchKey.settingsAddButton), action: addScopes)
                    .help(settings.text(FileSearchKey.settingsAddHelp))
                if !isDefault {
                    Button(settings.text(FileSearchKey.settingsRestoreDefaults)) {
                        settings.fileSearchScopes = FileSearchScope.defaultScopes
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.fileSearchSearchScopes)
        } footer: {
            Text(settings.text(FileSearchKey.settingsScopesFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.fileSearchScopes) { _, _ in refreshMissing() }
    }

    /// 重新计算哪些范围路径已不存在。
    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.fileSearchScopes.filter { scope in
                !fm.fileExists(atPath: FileSearchScope.expand(scope, homeDirectory: home).path)
            })
    }

    /// 弹出目录选择面板并把选中的目录添加到搜索范围。
    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = settings.text(FileSearchKey.settingsPanelPrompt)
        panel.message = settings.text(FileSearchKey.settingsPanelMessage)
        // GearMac 是辅助型应用，若不这样处理，打开的对话框会落在前台应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.fileSearchScopes = FileSearchScope.normalize(
            settings.fileSearchScopes + panel.urls.map(\.path), homeDirectory: home)
    }
}

/// 忽略模式列表区段：展示内置规则、用户规则并新增规则。
private struct FileSearchIgnoreSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""

    var body: some View {
        Section {
            ForEach(FileSearchIgnoreList.defaults, id: \.self) { pattern in
                PatternRow(pattern: pattern, onRemove: nil)
            }
            ForEach(settings.fileSearchIgnorePatterns, id: \.self) { pattern in
                PatternRow(pattern: pattern) {
                    settings.fileSearchIgnorePatterns.removeAll { $0 == pattern }
                }
            }

            TextField(settings.text(FileSearchKey.settingsAddPattern), text: $draft)
                .onSubmit(addPattern)
        } header: {
            SettingsSectionHeader(.fileSearchIgnorePatterns)
        } footer: {
            Text(settings.text(FileSearchKey.settingsIgnoreFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 把输入框中的模式追加到用户忽略列表（去重且排除内置规则）。
    private func addPattern() {
        let pattern = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !pattern.isEmpty,
            !FileSearchIgnoreList.defaults.contains(pattern),
            !settings.fileSearchIgnorePatterns.contains(pattern)
        else { return }
        settings.fileSearchIgnorePatterns.append(pattern)
    }
}

/// 单条忽略模式的展示行。
private struct PatternRow: View {
    @Environment(AppSettings.self) private var settings
    let pattern: String
    /// 内置规则为 nil：它无法被关闭，因此没有删除入口。
    let onRemove: (() -> Void)?

    var body: some View {
        LabeledContent {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(
                        format: settings.text(FileSearchKey.accessibilityRemovePattern), pattern))
            }
        } label: {
            Text(pattern)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(onRemove == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
}
