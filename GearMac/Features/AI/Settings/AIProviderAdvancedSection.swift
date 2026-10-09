// 文件职责：已安装 AI 工具的高级设置区，编辑命令路径与启动环境变量，离开字段即保存。
// 分层：UI + Settings；经 AISettingsStore 写入 UserDefaults 与 Keychain，命令选择经 ExecutablePicker。
import SwiftUI

/// 已安装工具的命令路径与启动变量，离开字段即保存。
struct AIProviderAdvancedSection: View {
    @Environment(AISettingsStore.self) private var settings

    let kind: InstalledAIKind
    /// 命令查找的结果，也是 Choose… 打开的起始位置。
    let detected: URL?

    @State private var path = ""
    @State private var variables: [Draft] = []
    @State private var saveFailed = false
    @State private var readFailed = false
    @FocusState private var focus: Field?

    /// 编辑中的环境变量草稿，带独立 id 以便 ForEach 绑定。
    private struct Draft: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    /// 当前焦点字段：路径、变量名或变量值。
    private enum Field: Hashable {
        case path
        case name(UUID)
        case value(UUID)
    }

    /// 命令区（路径与选择按钮）与环境变量区（增删行）。
    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Command path", text: $path, prompt: Text("Automatic"))
                        .labelsHidden()
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .focused($focus, equals: .path)
                        .onSubmit(save)
                    Button("Choose…", action: choose)
                        .fixedSize()
                }
            } label: {
                Text("Command path")
                Text("Empty finds \(kind.command) the way Terminal does.")
            }
            .task(id: kind) { load() }
            .onChange(of: focus) { old, new in
                if old != nil, old != new { save() }
            }
        } header: {
            Text("Command")
        }
        Section {
            LabeledContent {
                Button("Add Variable", action: addVariable)
                    .fixedSize()
                    .disabled(readFailed)
            } label: {
                Text("Variables")
                Text("Set for \(kind.title) only, each time it starts.")
            }
            ForEach($variables) { $variable in
                variableRow($variable)
            }
        } header: {
            Text("Environment")
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(
                    saveFailed || readFailed
                        ? AnyShapeStyle(Theme.Colors.destructive) : AnyShapeStyle(.secondary))
        }
    }

    /// 单个环境变量的编辑行：名称、值、删除按钮与校验提示。
    private func variableRow(_ variable: Binding<Draft>) -> some View {
        let draft = variable.wrappedValue
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Name", text: variable.name, prompt: Text("NAME"))
                    .labelsHidden()
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    .frame(width: Theme.Size.aiVariableName)
                    .focused($focus, equals: .name(draft.id))
                    .onSubmit(save)
                RevealableSecureField(
                    title: "Value of \(draft.name)", text: variable.value, prompt: Text("Value")
                )
                .labelsHidden()
                .font(.callout.monospaced())
                .focused($focus, equals: .value(draft.id))
                .onSubmit(save)
                Button {
                    remove(draft.id)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel("Remove \(draft.name)")
            }
            if let note = note(for: draft.name) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 根据读写失败状态给出底部说明文案。
    private var footer: String {
        if readFailed { return "The variables could not be read from your login Keychain." }
        return saveFailed
            ? "The variables could not be saved to your login Keychain."
            : "Values stay in your login Keychain. A change applies the next time \(kind.title) starts."
    }

    /// 校验变量名：命名非法或由 GearMac 自行管理的变量给出提示。
    private func note(for name: String) -> String? {
        guard !name.isEmpty else { return nil }
        if !InstalledAILaunch.isVariableName(name) {
            return "A name is letters, digits and underscores, and does not start with a digit."
        }
        if kind.isManagedVariable(name) {
            return "GearMac sets \(name) itself, so this value is not used."
        }
        return nil
    }

    /// 从设置加载当前命令路径与环境变量，读取失败时标记失败。
    private func load() {
        path = settings.override(for: kind).commandPath
        do {
            variables = try settings.environment(for: kind).map {
                Draft(name: $0.name, value: $0.value)
            }
            readFailed = false
        } catch {
            variables = []
            readFailed = true
        }
        saveFailed = false
    }

    /// 保存命令路径与环境变量；读取失败时不保存，以免覆盖已存值。
    private func save() {
        settings.setCommandPath(path, for: kind)
        // 读取失败后的草稿没有值，保存它们会把已存的值清空。
        guard !readFailed else { return }
        do {
            try settings.setEnvironment(
                variables.map {
                    InstalledAIVariable(
                        name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value)
                }, for: kind)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    /// 追加一条空变量草稿并把焦点移到名称输入框。
    private func addVariable() {
        let draft = Draft()
        variables.append(draft)
        focus = .name(draft.id)
    }

    /// 删除指定变量并立即保存。
    private func remove(_ id: UUID) {
        variables.removeAll { $0.id == id }
        save()
    }

    /// 打开可执行文件选择器，选中后写入路径并保存。
    private func choose() {
        let start =
            detected?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard
            let url = ExecutablePicker.choose(
                message: "Choose the \(kind.command) command GearMac should run.",
                startingAt: start)
        else { return }
        path = (url.path as NSString).abbreviatingWithTildeInPath
        save()
    }
}
