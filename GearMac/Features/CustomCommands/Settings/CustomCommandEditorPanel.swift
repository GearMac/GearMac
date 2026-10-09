// 文件职责：单条自定义命令的新增/编辑面板，编辑名称、命令、图标、运行目录、位置参数与各运行选项。
// 分层：UI（Settings）；本地维护草稿状态，保存时统一交给 CustomCommandCoordinator 校验落库。
import AppKit
import SwiftUI

/// 单条自定义命令的新增/编辑面板，由命令设置面板弹出。
struct CustomCommandEditorPanel: View {
    let command: CustomCommand?

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var name: String
    @State private var shellCommand: String
    @State private var loadsShellEnvironment: Bool
    @State private var requiresConfirmation: Bool
    @State private var showsConfirmation: Bool
    @State private var showsOutput: Bool
    @State private var arguments: [ArgumentDraft]
    @State private var workingDirectory: String
    @State private var iconSymbol: String?
    @State private var showingIconPicker = false
    @State private var errorMessage: String?

    /// 参数草稿；持久化模型中缺少稳定标识，用它保证删除某行时其余输入框不跳动。
    private struct ArgumentDraft: Identifiable {
        let id = UUID()
        var name: String
        var isOptional: Bool
    }

    /// 传入 nil 表示新增，否则以已有命令的字段初始化各草稿状态。
    init(command: CustomCommand?) {
        self.command = command
        _name = State(initialValue: command?.name ?? "")
        _shellCommand = State(initialValue: command?.command ?? "")
        _loadsShellEnvironment = State(initialValue: command?.loadsShellEnvironment ?? false)
        _requiresConfirmation = State(initialValue: command?.requiresConfirmation ?? false)
        _showsConfirmation = State(initialValue: command?.showsConfirmation ?? false)
        _showsOutput = State(initialValue: command?.showsOutput ?? false)
        _arguments = State(
            initialValue: (command?.arguments ?? []).map {
                ArgumentDraft(name: $0.name, isOptional: $0.isOptional)
            })
        _workingDirectory = State(initialValue: command?.workingDirectory ?? "")
        _iconSymbol = State(initialValue: command?.iconSymbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: settings.text(
                    command == nil
                        ? CustomCommandsKey.editorAddTitle : CustomCommandsKey.editorEditTitle))

            HStack(alignment: .bottom, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(settings.text(CustomCommandsKey.editorName))
                        .font(.callout.weight(.medium))
                    TextField(settings.text(CustomCommandsKey.editorNamePlaceholder), text: $name)
                        .settingsEditorTextField()
                }
                iconField
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(settings.text(CustomCommandsKey.editorCommand))
                    .font(.callout.weight(.medium))
                TextEditor(text: $shellCommand)
                    .font(.body.monospaced())
                    .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
            }

            Text(settings.text(CustomCommandsKey.editorCommandExample))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            workingDirectoryField

            argumentsSection

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    settings.text(CustomCommandsKey.editorLoadShellEnv), isOn: $loadsShellEnvironment,
                    detail: settings.text(CustomCommandsKey.editorLoadShellEnvDetail))
                optionToggle(
                    settings.text(CustomCommandsKey.editorNeedsConfirmation),
                    isOn: $requiresConfirmation,
                    detail: settings.text(CustomCommandsKey.editorNeedsConfirmationDetail))
                optionToggle(
                    settings.text(CustomCommandsKey.editorShowConfirmation), isOn: $showsConfirmation,
                    detail: settings.text(CustomCommandsKey.editorShowConfirmationDetail))
                optionToggle(
                    settings.text(CustomCommandsKey.editorShowOutput), isOn: $showsOutput,
                    detail: settings.text(CustomCommandsKey.editorShowOutputDetail))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(settings.text(CustomCommandsKey.editorCancel)) { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(CustomCommandsKey.editorSave), action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    /// 图标选择器中可选的 SF Symbol 列表。
    private static let iconSymbols = [
        "terminal", "hammer", "wrench", "gearshape", "bolt", "arrow.clockwise", "trash",
        "shippingbox", "cube", "server.rack", "externaldrive", "internaldrive", "cloud",
        "arrow.up.circle", "arrow.down.circle", "doc.text", "folder", "magnifyingglass",
        "ladybug", "chevron.left.forwardslash.chevron.right", "network", "lock", "key",
        "display", "speaker.wave.2", "moon", "sun.max", "power", "clock", "calendar",
        "chart.bar", "flame"
    ]

    /// 图标选择字段：未选择时展示默认图标并标注为 Automatic。
    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(CustomCommandsKey.editorIcon))
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: iconSymbol ?? CustomCommand.sfSymbol, size: 14)
                    Text(
                        settings.text(
                            iconSymbol == nil
                                ? CustomCommandsKey.editorAutomatic : CustomCommandsKey.editorCustom)
                    )
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: Self.iconFieldWidth)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: CustomCommand.sfSymbol,
                    symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    private static let iconFieldWidth: CGFloat = 130

    /// 运行目录字段：可手动输入或通过面板选择，留空表示用户主目录。
    private var workingDirectoryField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(CustomCommandsKey.editorRunIn))
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.sm) {
                TextField(settings.text(CustomCommandsKey.editorRunInPlaceholder), text: $workingDirectory)
                    .settingsEditorTextField()
                Button(settings.text(CustomCommandsKey.editorChoose), action: chooseWorkingDirectory)
            }
            Text(settings.text(CustomCommandsKey.editorRunInHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 打开目录选择面板，并把结果以缩写形式（`~`）写入草稿。
    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = settings.text(CustomCommandsKey.editorChoosePrompt)
        panel.message = settings.text(CustomCommandsKey.editorChooseMessage)
        if !workingDirectory.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (workingDirectory as NSString).expandingTildeInPath)
        }
        // GearMac 是配件型应用，若不主动激活，面板会开在最前应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// 位置参数编辑区：最多三个，按 `$1`、`$2` 顺序传给命令。
    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(settings.text(CustomCommandsKey.editorArguments))
                    .font(.callout.weight(.medium))
                Spacer()
                Button(settings.text(CustomCommandsKey.editorAddArgument)) {
                    arguments.append(ArgumentDraft(name: "", isOptional: false))
                }
                .controlSize(.small)
                .disabled(arguments.count >= CustomCommandArgument.limit)
            }
            VStack(spacing: Theme.Spacing.sm) {
                ForEach($arguments) { $argument in argumentRow($argument) }
            }
            Text(
                arguments.isEmpty
                    ? settings.text(CustomCommandsKey.editorArgumentsEmptyHint)
                    : settings.text(CustomCommandsKey.editorArgumentsHint)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// 单个参数的编辑行：位置编号、名称、是否可选与删除按钮。
    private func argumentRow(_ argument: Binding<ArgumentDraft>) -> some View {
        let id = argument.wrappedValue.id
        return HStack(spacing: Theme.Spacing.sm) {
            Text("$\(position(of: id))")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: Self.positionWidth, alignment: .leading)
            TextField(settings.text(CustomCommandsKey.editorArgumentNamePlaceholder), text: argument.name)
                .settingsEditorTextField()
            Toggle(settings.text(CustomCommandsKey.editorOptional), isOn: argument.isOptional)
                .toggleStyle(.checkbox)
            Button {
                arguments.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(settings.text(CustomCommandsKey.editorRemoveArgument))
        }
    }

    private static let positionWidth: CGFloat = 22

    /// 该行取值最终落入的 shell 变量序号；空名称只在保存时才被丢弃。
    private func position(of id: UUID) -> Int {
        (arguments.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// 带副说明文字的复选框选项。
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

    /// 组装草稿并提交：新增走 add，编辑走 update，失败时展示错误文案。
    private func save() {
        // 编辑时保留原 UUID，从而保留该命令持有的全部引用。
        let draft = CustomCommand(
            id: command?.id ?? UUID(), name: name, command: shellCommand,
            // 启用开关由设置面板的行管理；编辑时沿用原值，不在此重置。
            isEnabled: command?.isEnabled ?? true,
            loadsShellEnvironment: loadsShellEnvironment,
            requiresConfirmation: requiresConfirmation,
            showsConfirmation: showsConfirmation,
            arguments: arguments.map {
                CustomCommandArgument(name: $0.name, isOptional: $0.isOptional)
            },
            showsOutput: showsOutput, workingDirectory: workingDirectory, iconSymbol: iconSymbol)
        do {
            if command == nil {
                try core.customCommandCoordinator.addCustomCommand(draft)
            } else {
                try core.customCommandCoordinator.updateCustomCommand(draft)
            }
            dismiss()
        } catch let error as CustomCommandValidationError {
            errorMessage = error.message(settings.language)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
