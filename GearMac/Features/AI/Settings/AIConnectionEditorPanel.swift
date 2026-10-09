// 文件职责：API 连接编辑面板，编辑名称、Provider、Base URL、API Key，并发现/搜索/手输该连接可用的模型，校验后回传保存。
// 分层：UI；仅 SwiftUI 视图，Keychain 读取与模型发现等副作用委托给 KeychainSecretStore 与注入的 AIModelDiscoveryService，不直接持久化设置。
import SwiftUI

/// 编辑面板的输入目标：待编辑的连接、是否已有存储密钥，以及是否为新建。
struct AIConnectionEditorTarget: Identifiable {
    let connection: AIConnection
    let hasStoredKey: Bool
    let isNew: Bool
    var id: UUID { connection.id }
}

/// API 连接的新建/编辑面板，含模型发现、搜索与手动输入。
struct AIConnectionEditorPanel: View {
    let target: AIConnectionEditorTarget
    let onSave: (AIConnection, String, Bool) -> String?
    let onCancel: () -> Void

    @State private var connection: AIConnection
    @State private var key = ""
    @State private var modelQuery = ""
    @State private var discovery: ModelDiscoveryState = .waitingForKey
    @State private var discoveryRevision = 0
    @State private var error: String?

    private let modelDiscovery = AIModelDiscoveryService()

    /// 初始化：保存目标连接与保存/取消回调，并把连接复制进本地 @State 以便编辑。
    init(
        target: AIConnectionEditorTarget,
        onSave: @escaping (AIConnection, String, Bool) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        _connection = State(initialValue: target.connection)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: target.isNew ? "Add API Connection" : "Edit API Connection"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    editorField("Name") {
                        TextField(
                            "Name", text: $connection.name, prompt: Text("Optional label")
                        )
                        .settingsEditorTextField()
                    }
                    editorField("Provider") {
                        Picker("Provider", selection: $connection.provider) {
                            ForEach(AIProviderKind.allCases) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .labelsHidden()
                    }
                    editorField("Base URL") {
                        TextField(
                            "Base URL", text: $connection.baseURL,
                            prompt: Text(connection.provider.defaultBaseURL)
                        )
                        .settingsEditorTextField()
                    }
                    editorField("API Key") {
                        RevealableSecureField(title: "API Key", text: $key, prompt: Text(apiKeyPlaceholder))
                            .settingsEditorTextField()
                    }
                    if storedKeyMatchesTarget {
                        Label("A key is already stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if target.hasStoredKey {
                        Label(
                            "The saved key stays with the endpoint it was saved for. "
                                + "Enter a key for this one.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                }

                Section {
                    modelDiscoveryContent
                } header: {
                    HStack {
                        Text("Models")
                        Spacer()
                        if !connection.models.isEmpty {
                            Text("\(connection.models.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text(
                        "Search the models available to this key and add one or more. Exact model "
                            + "IDs remain available when discovery is unsupported."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 540)
        .settingsEditorPanelSurface()
        .task(id: discoveryRevision) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await discoverModels()
        }
        .onChange(of: key) { discoveryRevision += 1 }
        .onChange(of: connection.baseURL) { discoveryRevision += 1 }
        .onChange(of: connection.provider) { oldProvider, newProvider in
            if connection.baseURL.isEmpty || connection.baseURL == oldProvider.defaultBaseURL {
                connection.baseURL = newProvider.defaultBaseURL
            }
            connection.reasoningOptions = nil
            discoveryRevision += 1
        }
    }

    /// 按模型发现状态渲染模型区域：等待密钥、加载中、已加载或失败。
    @ViewBuilder
    private var modelDiscoveryContent: some View {
        switch discovery {
        case .waitingForKey:
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            if AIEndpointPolicy.isLoopback(connection.baseURL) {
                Label("Checking this local endpoint for models…", systemImage: "network")
                    .foregroundStyle(.secondary)
            } else {
                Label("Enter an API key to search its available models.", systemImage: "key")
                    .foregroundStyle(.secondary)
            }
        case .loading:
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text("Loading available models…").foregroundStyle(.secondary)
            }
        case .loaded(let models):
            ForEach(connection.models, id: \.self) { model in selectedModelRow(model) }
            if models.isEmpty {
                Label("No compatible text models were returned.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                manualModelField
            } else {
                editorField("Find a model") {
                    TextField(
                        "Find a model", text: $modelQuery,
                        prompt: Text(modelSearchPlaceholder)
                    )
                    .settingsEditorTextField()
                    .onSubmit { addExactMatch(from: models) }
                }
                modelSearchResults(models)
            }
        case .failed(let message, let allowsManualEntry):
            LabeledContent {
                Button("Try Again") { discoveryRevision += 1 }
            } label: {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(connection.models, id: \.self) { model in
                selectedModelRow(model)
            }
            if allowsManualEntry { manualModelField }
        }
    }

    /// 渲染模型搜索结果，覆盖无查询、无匹配与手动输入兜底三种情况。
    @ViewBuilder
    private func modelSearchResults(_ models: [AIModelDiscovery.Model]) -> some View {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = matchingModels(in: models)
        if query.isEmpty {
            Text("Type a model or company name. \(models.count) models available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if matches.isEmpty {
            if connection.models.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
                Label("This model is already added.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("No available model matches this key.", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                if connection.provider == .openAICompatible {
                    Button("Use “\(query)” anyway") { addModel(query) }
                }
            }
        } else {
            ForEach(matches) { model in
                Button {
                    addModel(model)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(model.name)
                            if model.name != model.id {
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(model.name)")
            }
        }
    }

    /// 手动输入模型 ID 的表单行，供发现不可用时使用。
    private var manualModelField: some View {
        editorField("Model ID") {
            TextField("Model ID", text: $modelQuery, prompt: Text(modelPlaceholder))
                .settingsEditorTextField()
                .onSubmit(addManualModel)
        }
    }

    /// 用统一的 SettingsEditorField 样式包装一行表单字段。
    private func editorField<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsEditorField(title, labelFont: .callout.weight(.medium), content: content)
    }

    /// 已选模型行，右侧提供移除按钮。
    private func selectedModelRow(_ model: String) -> some View {
        LabeledContent(model) {
            Button {
                removeModel(model)
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(model)")
        }
    }

    /// 按 Provider 给出模型 ID 输入框的占位文案。
    private var modelPlaceholder: String {
        switch connection.provider {
        case .openAI, .openAICompatible: return "Model ID (e.g. gpt-5.4-mini)"
        case .anthropic: return "Model ID (e.g. claude-sonnet-4-6)"
        case .gemini: return "Model ID (e.g. gemini-3.7-flash)"
        case .openRouter: return "Model ID (e.g. openai/gpt-5.4-mini)"
        }
    }

    /// 模型发现遵循保存规则：更换目标地址时要求输入新密钥，而不是复用旧主机上的密钥。
    private var storedKeyMatchesTarget: Bool {
        target.hasStoredKey && AIEndpointPolicy.sameDestination(connection, target.connection)
    }

    /// API Key 输入框的占位文案，取决于是否存在可用密钥以及是否为本地端点。
    private var apiKeyPlaceholder: String {
        if storedKeyMatchesTarget { return "Leave blank to keep saved key" }
        if AIEndpointPolicy.isLoopback(connection.baseURL) { return "Optional for local endpoint" }
        return "Paste API key"
    }

    /// 模型搜索框的占位文案，OpenRouter 按模型或公司名搜索。
    private var modelSearchPlaceholder: String {
        connection.provider == .openRouter
            ? "Search by model or company" : "Search available models"
    }

    /// 在已发现的模型中搜索匹配项，排除已添加的模型。
    private func matchingModels(
        in models: [AIModelDiscovery.Model]
    ) -> [AIModelDiscovery.Model] {
        AIModelDiscovery.search(
            models, query: modelQuery, excluding: Set(connection.models), limit: 12)
    }

    /// 若查询与某模型的 id 或名称完全一致，就直接添加该模型。
    private func addExactMatch(from models: [AIModelDiscovery.Model]) {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let match = models.first(where: {
                $0.id.caseInsensitiveCompare(query) == .orderedSame
                    || $0.name.caseInsensitiveCompare(query) == .orderedSame
            })
        else { return }
        addModel(match)
    }

    /// 从已选模型中移除，并同步清理其视觉能力与推理选项记录。
    private func removeModel(_ model: String) {
        connection.models.removeAll { $0 == model }
        connection.visionModels.removeAll { $0 == model }
        connection.reasoningOptions?[model] = nil
    }

    /// 解析当前 API Key 与 Base URL，调用发现服务拉取可用模型并更新状态。
    private func discoverModels() async {
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if !enteredKey.isEmpty {
            apiKey = enteredKey
        } else if storedKeyMatchesTarget {
            do {
                apiKey = try KeychainSecretStore.aiAPIKeys.secret(for: connection.id) ?? ""
            } catch {
                discovery = .failed(
                    "The saved key could not be read from Keychain.", allowsManualEntry: false)
                return
            }
        } else if AIEndpointPolicy.isLoopback(connection.baseURL) {
            apiKey = ""
        } else {
            discovery = .waitingForKey
            return
        }

        let baseURL: URL
        do {
            baseURL = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            discovery = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? "Enter a valid provider base URL.",
                allowsManualEntry: false)
            return
        }
        discovery = .loading
        do {
            let models = try await modelDiscovery.models(
                provider: connection.provider, baseURL: baseURL, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            discovery = .loaded(models)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let catalogError = error as? AIModelDiscovery.DiscoveryError
            discovery = .failed(
                catalogError?.errorDescription
                    ?? "The provider could not load models. Enter one manually.",
                allowsManualEntry: catalogError != .rejectedKey)
        }
    }

    /// 把当前查询文本当作模型 ID 添加。
    private func addManualModel() {
        addModel(modelQuery)
    }

    /// 由发现结果添加模型，一并带入图像能力与推理选项。
    private func addModel(_ model: AIModelDiscovery.Model) {
        addModel(
            model.id, acceptsImages: model.acceptsImages,
            reasoningOptions: model.reasoningOptions)
    }

    /// 添加单个模型 ID，并按需更新视觉模型与 OpenRouter 推理选项。
    private func addModel(
        _ value: String, acceptsImages: Bool? = nil,
        reasoningOptions: AIConnection.ReasoningOptions? = nil
    ) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if !connection.models.contains(model) { connection.models.append(model) }
        if acceptsImages == true, !connection.visionModels.contains(model) {
            connection.visionModels.append(model)
        }
        if connection.provider == .openRouter, let reasoningOptions,
            !reasoningOptions.efforts.isEmpty
        {
            if connection.reasoningOptions == nil { connection.reasoningOptions = [:] }
            connection.reasoningOptions?[model] = reasoningOptions
        }
        modelQuery = ""
    }

    /// 校验发现状态、模型列表与 Base URL 后回传保存，错误信息写入面板 error。
    private func save() {
        if case .failed(_, let allowsManualEntry) = discovery, !allowsManualEntry {
            error = "Resolve the API key or endpoint error before saving."
            return
        }
        guard !connection.models.isEmpty else {
            error = "Select or add at least one model."
            return
        }
        do {
            _ = try AIEndpointPolicy.validate(connection.baseURL)
        } catch {
            self.error =
                (error as? LocalizedError)?.errorDescription
                ?? "Enter a valid provider base URL."
            return
        }
        error = onSave(connection, key, target.isNew)
    }
}

/// 模型发现的状态机：等待密钥、加载中、已加载或失败。
private enum ModelDiscoveryState: Equatable {
    case waitingForKey
    case loading
    case loaded([AIModelDiscovery.Model])
    case failed(String, allowsManualEntry: Bool)
}
