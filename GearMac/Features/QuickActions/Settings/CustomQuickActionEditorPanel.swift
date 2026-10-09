// 文件职责：提供新建/编辑自建快捷动作的编辑面板（名称、图标、指令与模型选择）。
// 分层：UI；面板内改变为本地状态，仅在 Save 时调用 Coordinator 落盘。
import SwiftUI

/// 打开编辑面板的请求：`action` 为 nil 表示新建，否则为编辑既有动作。
struct CustomQuickActionEditRequest: Identifiable {
    let id = UUID()
    let action: CustomQuickAction?
}

/// 自建快捷动作的编辑面板。
struct CustomQuickActionEditorPanel: View {
    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    private let existing: CustomQuickAction?
    @State private var name: String
    @State private var iconSymbol: String?
    @State private var instructions: String
    @State private var model: AIModelSelection?
    @State private var failure: String?
    @State private var showingIconPicker = false

    private static let iconSymbols = [
        "wand.and.stars", "textformat", "text.append", "text.quote", "text.badge.checkmark",
        "character.cursor.ibeam", "scissors", "arrow.down.right.and.arrow.up.left", "list.bullet",
        "bubble.left.and.text.bubble.right", "envelope", "megaphone", "face.smiling",
        "theatermasks", "graduationcap", "book", "brain", "lightbulb", "sparkles", "checkmark.seal",
        "globe", "curlybraces", "terminal", "chart.bar", "tag", "flag", "bolt", "leaf",
        "paintbrush", "hammer", "heart", "star"
    ]

    /// 指令输入为空时的占位提示。
    private var placeholder: String {
        settings.text(QuickActionsKey.customInstructionsPlaceholder)
    }

    /// 用请求中的既有动作（若有）初始化各输入字段。
    init(request: CustomQuickActionEditRequest, model: AIModelSelection?) {
        existing = request.action
        _name = State(initialValue: request.action?.name ?? "")
        _iconSymbol = State(initialValue: request.action?.iconSymbol)
        _instructions = State(initialValue: request.action?.instructions ?? "")
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: existing == nil
                    ? settings.text(QuickActionsKey.customNewTitle)
                    : String(
                        format: settings.text(QuickActionsKey.customEditTitle),
                        existing?.name ?? ""),
                subtitle: settings.text(QuickActionsKey.customSubtitle)
            )

            HStack(alignment: .bottom, spacing: Theme.Spacing.lg) {
                nameField
                iconField
            }

            instructionsField

            QuickActionModelPicker(selection: $model)

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                if let existing {
                    Button(settings.text(QuickActionsKey.customDelete), role: .destructive) {
                        dismiss()
                        Task { await core.quickActionCoordinator.deleteCustomQuickAction(id: existing.id) }
                    }
                    .buttonStyle(.modalAction(.destructive, fillsWidth: false))
                }
                Spacer()
                Button(settings.text(QuickActionsKey.settingsCancel)) { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(QuickActionsKey.settingsSave), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    /// 名称输入行。
    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuickActionsKey.customName))
                .font(.callout.weight(.medium))
            TextField(settings.text(QuickActionsKey.customNamePlaceholder), text: $name)
                .settingsEditorTextField()
        }
    }

    /// 图标选择行，用 popover 弹出符号选择器。
    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuickActionsKey.customIcon))
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: iconSymbol ?? CustomQuickAction.sfSymbol, size: 14)
                    Text(
                        settings.text(
                            iconSymbol == nil
                                ? QuickActionsKey.customAutomatic : QuickActionsKey.customCustom)
                    )
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 120)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: CustomQuickAction.sfSymbol,
                    symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    /// 指令输入区，空时显示占位提示。
    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuickActionsKey.customInstructions))
                .font(.callout.weight(.medium))
            TextEditor(text: $instructions)
                .font(.body)
                .settingsEditorTextArea(height: Theme.Size.editorTextHeight * 2)
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.md)
                            .allowsHitTesting(false)
                    }
                }
            Text(settings.text(QuickActionsKey.customInstructionsFooter))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 名称与指令都非空时才允许保存。
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 用当前表单构造草稿，并按新建/编辑分别调用 Coordinator，出错则展示错误描述。
    private func save() {
        let draft = CustomQuickAction(
            id: existing?.id ?? UUID(), name: name, iconSymbol: iconSymbol,
            instructions: instructions,
            previewsResult: existing?.previewsResult ?? true,
            createdAt: existing?.createdAt ?? Date())
        do {
            if existing == nil {
                try core.quickActionCoordinator.addCustomQuickAction(draft, model: model)
            } else {
                try core.quickActionCoordinator.updateCustomQuickAction(draft, model: model)
            }
            dismiss()
        } catch let error as CustomQuickActionError {
            failure = error.message(settings.language)
        } catch {
            failure = error.localizedDescription
        }
    }
}
