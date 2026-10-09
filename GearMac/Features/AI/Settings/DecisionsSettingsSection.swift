// 文件职责：设置 → AI 的 Decisions 分区：判定问题集编辑与默认恢复。
// 分层：UI；配置写回 AISettingsStore；模型即路由（选中 Decisions 模型走 /decisions），因此这里只定义问什么。
import SwiftUI

/// 设置 → AI 的 Decisions 部分：问题集是这套判定的唯一配置。
/// 端点、密钥与模型都来自聊天选中的那条 API 连接，所以分区不随 aiEnabled 变灰。
struct DecisionsSettingsSection: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings

    @State private var editor: DecisionsQuestionEditTarget?
    @State private var pendingRemoval: DecisionsQuestion?
    @State private var pendingRestore = false

    var body: some View {
        Section {
            questionRows
            Button {
                editor = DecisionsQuestionEditTarget(question: nil)
            } label: {
                Label {
                    SettingsRowTitle(.aiDecisions, appSettings.text(AIKey.decisionsAddQuestion))
                } icon: {
                    Image(systemName: "plus").foregroundStyle(.primary)
                }
            }
            if settings.decisionsQuestions != .standard {
                Button(role: .destructive) {
                    pendingRestore = true
                } label: {
                    SettingsRowTitle(.aiDecisions, appSettings.text(AIKey.decisionsRestoreDefaults))
                }
            }
        } header: {
            SettingsSectionHeader(.aiDecisions)
        } footer: {
            Text(appSettings.text(AIKey.decisionsFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsEditorPanel(item: $editor) { target in
            DecisionsQuestionEditor(target: target, onSave: saveQuestion, onCancel: { editor = nil })
        }
        .confirmationDialog(
            appSettings.text(AIKey.decisionsRestoreDefaults),
            isPresented: $pendingRestore
        ) {
            Button(appSettings.text(AIKey.decisionsRestoreDefaults), role: .destructive) {
                settings.decisionsQuestions = .standard
            }
        } message: {
            Text(appSettings.text(AIKey.decisionsQuestionsSubtitle))
        }
        .confirmationDialog(
            pendingRemoval?.name ?? "",
            isPresented: removalBinding,
            presenting: pendingRemoval
        ) { question in
            Button(appSettings.text(AIKey.decisionsDelete), role: .destructive) {
                remove(question)
            }
        }
    }

    /// 问题列表：一行一个问题，铅笔编辑、垃圾桶删除。
    private var questionRows: some View {
        Group {
            if settings.decisionsQuestions.questions.isEmpty {
                Text(appSettings.text(AIKey.decisionsNoQuestions))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.decisionsQuestions.questions) { question in
                    SettingsRow(title: question.name, subtitle: question.instructions) {
                        Image(systemName: kindSymbol(question.kind))
                            .foregroundStyle(.secondary)
                    } trailing: {
                        Button {
                            editor = DecisionsQuestionEditTarget(question: question)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button {
                            pendingRemoval = question
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 问题类型在行首的符号；与编辑器里的分段控件一一对应。
    private func kindSymbol(_ kind: DecisionsQuestionKind) -> String {
        switch kind {
        case .predicate: return "questionmark.bubble"
        case .choice: return "list.bullet"
        case .score: return "chart.bar"
        }
    }

    /// 控制删除确认弹窗显示与否的绑定。
    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// 保存一个问题的编辑结果；返回非 nil 文案时面板停留并展示。
    private func saveQuestion(_ question: DecisionsQuestion, isNew: Bool) -> String? {
        var set = settings.decisionsQuestions
        if isNew {
            set.questions.append(question)
        } else if let index = set.questions.firstIndex(where: { $0.id == question.id }) {
            set.questions[index] = question
        }
        do {
            try set.validated()
        } catch let error as DecisionsQuestionError {
            return error.message(appSettings.language)
        } catch {
            return error.localizedDescription
        }
        settings.decisionsQuestions = set
        editor = nil
        return nil
    }

    /// 删除一个问题；问题集删空是合法的，Decide 会在运行时提示补充。
    private func remove(_ question: DecisionsQuestion) {
        pendingRemoval = nil
        settings.decisionsQuestions.questions.removeAll { $0.id == question.id }
    }
}

/// 打开问题编辑器的请求；`question` 为 nil 表示新建。
struct DecisionsQuestionEditTarget: Identifiable {
    let id = UUID()
    let question: DecisionsQuestion?

    var isNew: Bool { question == nil }
}

/// 单个判定问题的编辑面板：类型、名称、说明，choice 的选项与 score 的档位。
struct DecisionsQuestionEditor: View {
    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings
    @Environment(AISettingsStore.self) private var store

    let target: DecisionsQuestionEditTarget
    let onSave: (DecisionsQuestion, Bool) -> String?
    let onCancel: () -> Void

    @State private var kind: DecisionsQuestionKind
    @State private var name: String
    @State private var instructions: String
    @State private var choices: [DecisionsChoice]
    @State private var levels: [DecisionsLevel]
    @State private var failure: String?

    init(
        target: DecisionsQuestionEditTarget,
        onSave: @escaping (DecisionsQuestion, Bool) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        _kind = State(initialValue: target.question?.kind ?? .predicate)
        _name = State(initialValue: target.question?.name ?? "")
        _instructions = State(initialValue: target.question?.instructions ?? "")
        _choices = State(initialValue: target.question?.choices ?? [])
        _levels = State(initialValue: target.question?.levels ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: target.isNew
                    ? appSettings.text(AIKey.decisionsAddQuestion)
                    : appSettings.text(AIKey.decisionsEditTitle),
                subtitle: appSettings.text(AIKey.decisionsQuestionsSubtitle)
            )

            Picker(
                appSettings.text(AIKey.decisionsKindTitle), selection: $kind
            ) {
                Text(kindTitle(.predicate)).tag(DecisionsQuestionKind.predicate)
                Text(kindTitle(.choice)).tag(DecisionsQuestionKind.choice)
                Text(kindTitle(.score)).tag(DecisionsQuestionKind.score)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            fieldLabel(AIKey.decisionsNameTitle)
            TextField(
                appSettings.text(AIKey.decisionsNamePrompt), text: $name
            )
            .settingsEditorTextField()

            fieldLabel(AIKey.decisionsInstructionsTitle)
            TextEditor(text: $instructions)
                .font(.body)
                .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text(appSettings.text(AIKey.decisionsInstructionsPrompt))
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.md)
                            .allowsHitTesting(false)
                    }
                }

            switch kind {
            case .predicate:
                Text(appSettings.text(AIKey.decisionsKindFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .choice:
                choicesEditor
            case .score:
                levelsEditor
            }

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                Button(appSettings.text(AIKey.decisionsCancel), action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(appSettings.text(AIKey.decisionsSave), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    /// choice 选项编辑：每行 value + 说明，可增删。
    private var choicesEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            fieldLabel(AIKey.decisionsChoicesTitle)
            ForEach(choices.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.md) {
                    TextField(
                        appSettings.text(AIKey.decisionsChoiceValuePrompt),
                        text: Binding(
                            get: { choices[index].value },
                            set: { choices[index].value = $0 }))
                    .settingsEditorTextField()
                    TextField(
                        appSettings.text(AIKey.decisionsChoiceDescriptionPrompt),
                        text: Binding(
                            get: { choices[index].description ?? "" },
                            set: { choices[index].description = $0.isEmpty ? nil : $0 }))
                    .settingsEditorTextField()
                    Button {
                        choices.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                choices.append(DecisionsChoice(value: "", description: nil))
            } label: {
                Label(
                    appSettings.text(AIKey.decisionsAddChoice),
                    systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    /// score 档位编辑：每行 label + 说明，可增删。
    private var levelsEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            fieldLabel(AIKey.decisionsLevelsTitle)
            ForEach(levels.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.md) {
                    TextField(
                        appSettings.text(AIKey.decisionsLevelLabelPrompt),
                        text: Binding(
                            get: { levels[index].label },
                            set: { levels[index].label = $0 }))
                    .settingsEditorTextField()
                    TextField(
                        appSettings.text(AIKey.decisionsLevelDescriptionPrompt),
                        text: Binding(
                            get: { levels[index].description ?? "" },
                            set: { levels[index].description = $0.isEmpty ? nil : $0 }))
                    .settingsEditorTextField()
                    Button {
                        levels.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                levels.append(DecisionsLevel(label: "", description: nil))
            } label: {
                Label(
                    appSettings.text(AIKey.decisionsAddLevel),
                    systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    /// 表单字段的标题行。
    private func fieldLabel(_ key: AIKey) -> some View {
        Text(appSettings.text(key))
            .font(.callout.weight(.medium))
    }

    private func kindTitle(_ kind: DecisionsQuestionKind) -> String {
        switch kind {
        case .predicate: return appSettings.text(AIKey.decisionsKindPredicate)
        case .choice: return appSettings.text(AIKey.decisionsKindChoice)
        case .score: return appSettings.text(AIKey.decisionsKindScore)
        }
    }

    /// 保存草稿；名称在集内重复由调用方校验，其余约束先在这里拦住。
    private func save() {
        var draft = DecisionsQuestion(
            id: target.question?.id ?? UUID(), kind: kind, name: name,
            instructions: instructions, choices: choices, levels: levels)
        draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = onSave(draft, target.isNew) {
            failure = message
        }
    }
}
