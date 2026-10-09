// 文件职责：代码片段功能的设置面板，提供启用开关、Accessibility 提示、片段库列表、增删改编辑器面板与错误提示。
// 分层：Settings/UI；通过 SnippetsStore、AppSettings 与 SnippetCoordinator 读写状态，自身不直接触碰文件系统。
import SwiftUI

/// 代码片段设置面板：启用开关、Accessibility 提示、片段库列表与编辑器入口。
struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings

    @State private var editor: SnippetEditRequest?
    @State private var pendingDeletion: StoredSnippet?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: settings.text(SnippetsKey.settingsEnableTitle),
                enableSubtitle: settings.text(SnippetsKey.settingsEnableSubtitle),
                // 启用同时意味着同意关键字展开，因此这里走会先确认的 setter。
                isEnabled: Binding(
                    get: { settings.snippetsEnabled },
                    set: { core.snippetCoordinator.setSnippetsEnabled($0) }),
                showsInLauncher: $settings.snippetsShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            if settings.snippetsEnabled, core.snippetListener.status == .needsAccessibility {
                Section {
                    LabeledContent {
                        Button(settings.text(SnippetsKey.settingsGrantAccess)) {
                            Permissions.openAccessibilitySettings()
                        }
                    } label: {
                        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .frame(width: SettingsListMetrics.iconSize)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(settings.text(SnippetsKey.settingsAccessTitle))
                                    .foregroundStyle(.orange)
                                Text(settings.text(SnippetsKey.settingsAccessSubtitle))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Group {
                FeatureCommandsSection(owner: .snippets, anchor: .snippetsCommands)
                library
                libraryNotices
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
        .settingsEditorPanel(item: $editor) { request in
            SnippetEditorPanel(record: request.record)
        }
        .onChange(of: core.pendingSnippetEdit?.id, initial: true) { _, _ in
            guard let request = core.pendingSnippetEdit else { return }
            editor = request
            core.pendingSnippetEdit = nil
        }
        .alert(item: $pendingDeletion) { record in
            Alert(
                title: Text(
                    String(
                        format: settings.text(SnippetsKey.settingsDeleteTitle),
                        record.snippet.name)),
                message: Text(
                    String(
                        format: settings.text(SnippetsKey.settingsDeleteMessage),
                        record.fileURL.lastPathComponent)),
                primaryButton: .destructive(Text(settings.text(SnippetsKey.settingsDeleteAction))) {
                    delete(record)
                },
                secondaryButton: .cancel())
        }
    }

    /// 片段库区段：列出全部片段行，并提供新增入口与片段文件夹操作。
    private var library: some View {
        Section {
            if sortedSnippets.isEmpty {
                Text(
                    settings.text(
                        snippetsStore.state == .loading
                            ? SnippetsKey.settingsLoading : SnippetsKey.settingsEmpty)
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSnippets) { record in
                    SnippetSettingsRow(
                        record: record,
                        onEdit: { editor = SnippetEditRequest(record: record) },
                        onDelete: { pendingDeletion = record })
                }
            }

            LabeledContent {
                Button(settings.text(SnippetsKey.settingsAdd)) {
                    editor = SnippetEditRequest(record: nil)
                }
            } label: {
                SettingsRowTitle(.snippetsLibrary, settings.text(SnippetsKey.settingsNewSnippet))
            }

            LabeledContent {
                if settings.snippetsFolder != nil {
                    Button(
                        settings.text(SnippetsKey.settingsUseDefault),
                        action: core.snippetCoordinator.resetSnippetsFolder)
                }
                Button(
                    settings.text(SnippetsKey.settingsChoose),
                    action: core.snippetCoordinator.chooseSnippetsFolder)
                Button(
                    settings.text(SnippetsKey.settingsOpenFolder),
                    action: core.snippetCoordinator.revealSnippetsInFinder
                )
                .accessibilityHint(settings.text(SnippetsKey.settingsOpenFolderHint))
            } label: {
                SettingsRowTitle(.snippetsLibrary, settings.text(SnippetsKey.settingsFolder))
                Text((snippetsStore.snippetsDirectory.path as NSString).abbreviatingWithTildeInPath)
            }
        } header: {
            SettingsSectionHeader(.snippetsLibrary)
        }
    }

    /// 片段库的提示区段：加载失败、解析问题与无面板可依的操作错误。
    @ViewBuilder
    private var libraryNotices: some View {
        if case .failed(let message) = snippetsStore.state {
            noticeSection(
                settings.text(SnippetsKey.noticeLoadFailed), message, tint: .orange,
                retryHint: settings.text(SnippetsKey.noticeLoadRetryHint))
        }

        if !snippetsStore.issues.isEmpty {
            noticeSection(
                snippetIssueTitle, snippetIssueMessage, tint: .orange,
                retryHint: settings.text(SnippetsKey.noticeIssuesRetryHint))
        }

        // 编辑器会自行报告失败，这里只覆盖没有对应面板的错误。
        if editor == nil, let operationError = snippetsStore.operationError {
            noticeSection(
                settings.text(SnippetsKey.noticeOperationFailed), operationError, tint: .red,
                retryHint: nil)
        }
    }

    /// 构建一条提示区段，可选地附带重试按钮及其提示文案。
    private func noticeSection(
        _ title: String, _ message: String, tint: Color, retryHint: String?
    ) -> some View {
        Section {
            LabeledContent {
                if let retryHint {
                    Button(settings.text(SnippetsKey.noticeRetry), action: snippetsStore.retry)
                        .accessibilityHint(retryHint)
                }
            } label: {
                Label(title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 按名称不区分大小写排序后的片段列表，供界面稳定展示。
    private var sortedSnippets: [StoredSnippet] {
        snippetsStore.snippets.sorted {
            $0.snippet.name.localizedCaseInsensitiveCompare($1.snippet.name) == .orderedAscending
        }
    }

    private var snippetIssueTitle: String {
        let count = snippetsStore.issues.count
        return count == 1
            ? settings.text(SnippetsKey.issueTitleOne)
            : String(format: settings.text(SnippetsKey.issueTitleMany), count)
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        let base = String(
            format: settings.text(SnippetsKey.issueMessage),
            first.fileURL.lastPathComponent, first.message)
        if snippetsStore.issues.count == 1 {
            return base
        }
        return base
            + String(
                format: settings.text(SnippetsKey.issuePlusMore),
                snippetsStore.issues.count - 1)
    }

    private func delete(_ record: StoredSnippet) {
        Task { try? await snippetsStore.delete(id: record.id) }
    }
}

/// 请求在设置面板中打开片段编辑器；record 为 nil 表示新增片段。
struct SnippetEditRequest: Identifiable {
    let id = UUID()
    /// 尚未落盘的片段为 nil。
    let record: StoredSnippet?
}

/// 片段库中的单行：图标、名称与元信息，以及快捷键录制、编辑和删除按钮。
private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(title: record.snippet.name, subtitle: metadata) {
            Image(systemName: "doc.text")
                .font(.system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs))
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            // 被禁用片段的快捷键会在统一入口被拒绝，因此这里也一并置灰。
            ShortcutRecorder(action: .snippet(id: record.id))
                .settingsEnabled(record.snippet.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help(settings.text(SnippetsKey.rowEdit))
            .accessibilityLabel(
                String(format: settings.text(SnippetsKey.rowEditNamed), record.snippet.name))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(settings.text(SnippetsKey.rowDelete))
            .accessibilityLabel(
                String(format: settings.text(SnippetsKey.rowDeleteNamed), record.snippet.name))
        }
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}

/// 新增/编辑片段的编辑器面板：字段校验、占位符插入与保存。
private struct SnippetEditorPanel: View {
    /// 新增时为 nil；否则是被保存目标文件（及其修订版本）对应的记录。
    let record: StoredSnippet?

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(SnippetsStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @FocusState private var isTemplateFocused: Bool
    @State private var name: String
    @State private var keyword: String
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isEnabled: Bool
    @State private var showsConfirmation: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(record: StoredSnippet?) {
        self.record = record
        let snippet = record?.snippet
        _name = State(initialValue: snippet?.name ?? "")
        _keyword = State(initialValue: snippet?.keyword ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _isEnabled = State(initialValue: snippet?.isEnabled ?? true)
        _showsConfirmation = State(initialValue: snippet?.showsConfirmation ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: settings.text(
                    record == nil ? SnippetsKey.editorAddTitle : SnippetsKey.editorEditTitle))

            field(
                title: settings.text(SnippetsKey.editorName),
                placeholder: settings.text(SnippetsKey.editorNamePlaceholder), text: $name,
                hint: settings.text(SnippetsKey.editorNameHint))
            field(
                title: settings.text(SnippetsKey.editorKeyword),
                placeholder: settings.text(SnippetsKey.editorKeywordPlaceholder), text: $keyword,
                hint: settings.text(SnippetsKey.editorKeywordHint))

            templateEditor

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    settings.text(SnippetsKey.editorEnabled), isOn: $isEnabled,
                    detail: settings.text(SnippetsKey.editorEnabledDetail))
                optionToggle(
                    settings.text(SnippetsKey.editorConfirm), isOn: $showsConfirmation,
                    detail: settings.text(SnippetsKey.editorConfirmDetail))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(settings.text(SnippetsKey.editorCancel)) { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(SnippetsKey.editorSave), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(settings.text(SnippetsKey.editorTemplate))
                    .font(.callout.weight(.medium))
                Spacer()
                placeholderMenu
            }
            TextEditor(text: $text, selection: $selection)
                .font(.body.monospaced())
                .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
                .focused($isTemplateFocused)
                .accessibilityLabel(settings.text(SnippetsKey.editorTemplateAccessibility))
                .accessibilityHint(settings.text(SnippetsKey.editorTemplateHint))
        }
    }

    /// 引擎支持的全部占位符；参数说明见 docs/features/snippets.md。
    private var placeholderMenu: some View {
        Menu(settings.text(SnippetsKey.editorInsert)) {
            Section(settings.text(SnippetsKey.editorSectionText)) {
                placeholderItem("{cursor}")
                placeholderItem("{clipboard}")
                placeholderItem("{selection}")
                placeholderItem("{uuid}")
            }
            Section(settings.text(SnippetsKey.editorSectionDateTime)) {
                placeholderItem("{date}")
                placeholderItem("{time}")
                placeholderItem("{datetime}")
                placeholderItem("{day}")
            }
            Section(settings.text(SnippetsKey.editorSectionArguments)) {
                placeholderItem("{argument name=\"Name\"}")
            }
            Section(settings.text(SnippetsKey.editorSectionSnippets)) {
                placeholderItem("{snippet name=\"Name\"}")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(settings.text(SnippetsKey.editorInsertAccessibility))
    }

    private func placeholderItem(_ token: String) -> some View {
        Button(token) { insert(token) }
    }

    /// 替换选中的文本，或落在光标处；没有可用选区时追加到末尾。
    private func insert(_ token: String) {
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        {
            text.replaceSubrange(range, with: token)
        } else {
            text += token
        }
        // 这些下标属于被替换掉的字符串，不能带到下一次插入。
        selection = nil
        isTemplateFocused = true
    }

    private func field(
        title: String, placeholder: String, text: Binding<String>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            TextField(placeholder, text: text)
                .settingsEditorTextField()
                .accessibilityLabel(
                    String(
                        format: settings.text(SnippetsKey.editorFieldAccessibility),
                        title.lowercased())
                )
                .accessibilityHint(hint)
        }
    }

    private func optionToggle(
        _ title: String, isOn: Binding<Bool>, detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var draft: Snippet {
        Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text,
            keyword: trimmedOrNil(keyword),
            isEnabled: isEnabled,
            showsConfirmation: showsConfirmation)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // 保存会带修订版本比对，中途的编辑会冲突，而不会被直接覆盖。
                if var updated = record {
                    updated.snippet = draft
                    try await store.save(updated)
                } else {
                    try await store.create(draft)
                }
                dismiss()
            } catch let error as SnippetRepository.RepositoryError {
                errorMessage = error.message(settings.language)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
