// 文件职责：提供 MCP 服务器的编辑面板，支持 HTTP/命令两种连接方式、凭证输入与连接测试。
// 分层：Settings（SwiftUI View）；表单状态本地暂存，保存与登录通过 MCPCoordinator 完成。
import SwiftUI

/// 面板打开的编辑目标：待编辑的服务器与是否为新建。
struct MCPServerEditorTarget: Identifiable {
    let server: MCPServer
    let isNew: Bool
    var id: UUID { server.id }
}

/// 新增或编辑单个服务器，并能在关闭面板前验证它确实可以连接。
struct MCPServerEditor: View {
    @Environment(MCPCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    let target: MCPServerEditorTarget
    let onSave: (MCPServer, MCPSecretStore.Secrets) -> String?
    let onCancel: () -> Void

    /// 连接方式：HTTP 远程端点或本地命令。
    private enum Kind: String, CaseIterable, Identifiable {
        case http
        case stdio

        var id: String { rawValue }

        /// 分段控件的显示标题。
        func title(_ language: AppLanguage) -> String {
            L10n.string(self == .http ? MCPKey.kindHTTP : MCPKey.kindCommand, language: language)
        }
    }

    /// Test Connection 的探测结果。
    private enum Probe: Equatable {
        case idle
        case running
        case found(Int)
        case failed(String)
    }

    @State private var usesOAuth: Bool
    @State private var clientID: String
    @State private var clientSecret: String
    // 状态文案所用的副本：视图 body 从不读取 Keychain，动作执行时才重新读取。
    @State private var storedOAuth: MCPOAuth.Credentials?
    @State private var operation: Task<Void, Never>?
    @State private var name: String
    @State private var kind: Kind
    @State private var url: String
    @State private var headerName: String
    @State private var headerValue: String
    @State private var command: String
    @State private var argumentText: String
    @State private var environmentText: String
    @State private var isEnabled: Bool
    @State private var trust: MCPTrust
    @State private var probe: Probe = .idle
    @State private var error: String?

    /// 根据目标服务器与已存凭证初始化表单各字段的初始值。
    init(
        target: MCPServerEditorTarget,
        onSave: @escaping (MCPServer, MCPSecretStore.Secrets) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        let server = target.server
        let secrets = target.isNew ? MCPSecretStore.Secrets() : MCPSecretStore().secrets(for: server.id)
        _usesOAuth = State(initialValue: server.oauth == true)
        _clientID = State(initialValue: secrets.oauth?.clientID ?? "")
        _clientSecret = State(initialValue: secrets.oauth?.clientSecret ?? "")
        _storedOAuth = State(initialValue: secrets.oauth)
        _name = State(initialValue: server.name)
        _isEnabled = State(initialValue: server.isEnabled)
        _trust = State(initialValue: server.trust)
        _headerValue = State(initialValue: secrets.headerValue)
        _environmentText = State(
            initialValue: secrets.environment.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        switch server.transport {
        case .http(let url, let headerName):
            _kind = State(initialValue: .http)
            _url = State(initialValue: url)
            _headerName = State(initialValue: headerName)
            _command = State(initialValue: "")
            _argumentText = State(initialValue: "")
        case .stdio(let command, let arguments, _):
            _kind = State(initialValue: .stdio)
            _url = State(initialValue: "")
            _headerName = State(initialValue: MCPTransportKind.defaultHeaderName)
            _command = State(initialValue: command)
            _argumentText = State(initialValue: arguments.joined(separator: " "))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: target.isNew
                    ? settings.text(MCPKey.editorAddTitle) : settings.text(MCPKey.editorEditTitle)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    field(settings.text(MCPKey.fieldName)) {
                        TextField(
                            settings.text(MCPKey.fieldName), text: $name, prompt: Text("GitHub")
                        )
                        .settingsEditorTextField()
                    }
                    field(settings.text(MCPKey.fieldHandle)) {
                        Text("@\(MCPSlug.normalize(name.isEmpty ? target.server.slug : name))")
                            .foregroundStyle(.secondary)
                    }
                    field(settings.text(MCPKey.fieldConnection)) {
                        SteadySegmentedPicker(
                            title: settings.text(MCPKey.fieldConnection),
                            options: Kind.allCases.map {
                                .init(value: $0, title: $0.title(settings.language))
                            },
                            selection: $kind)
                    }
                    if kind == .http {
                        field(settings.text(MCPKey.fieldURL)) {
                            TextField(
                                settings.text(MCPKey.fieldURL), text: $url,
                                prompt: Text("https://example.com/mcp")
                            )
                            .settingsEditorTextField()
                        }
                        field(settings.text(MCPKey.fieldAuthentication)) {
                            Picker(settings.text(MCPKey.fieldAuthentication), selection: $usesOAuth) {
                                Text(settings.text(MCPKey.fieldHeader)).tag(false)
                                Text(settings.text(MCPKey.authOAuth)).tag(true)
                            }
                            .labelsHidden()
                        }
                        if usesOAuth {
                            oauthFields
                        } else {
                            field(settings.text(MCPKey.fieldHeader)) {
                                TextField(
                                    settings.text(MCPKey.fieldHeader), text: $headerName,
                                    prompt: Text("Authorization")
                                )
                                .settingsEditorTextField()
                            }
                            field(settings.text(MCPKey.fieldValue)) {
                                RevealableSecureField(
                                    title: settings.text(MCPKey.fieldValue), text: $headerValue,
                                    prompt: Text("Bearer …")
                                )
                                .settingsEditorTextField()
                            }
                        }
                    } else {
                        field(settings.text(MCPKey.fieldCommand)) {
                            TextField(
                                settings.text(MCPKey.fieldCommand), text: $command,
                                prompt: Text("npx")
                            )
                            .settingsEditorTextField()
                        }
                        field(settings.text(MCPKey.fieldArguments)) {
                            TextField(
                                settings.text(MCPKey.fieldArguments), text: $argumentText,
                                prompt: Text("-y @modelcontextprotocol/server-filesystem ~/Desktop")
                            )
                            .settingsEditorTextField()
                        }
                        field(settings.text(MCPKey.fieldEnvironment)) {
                            TextField(
                                settings.text(MCPKey.fieldEnvironment), text: $environmentText,
                                prompt: Text("GITHUB_TOKEN=…"), axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .lineLimit(2...5)
                            .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
                        }
                    }
                } footer: {
                    Text(
                        kind == .http
                            ? settings.text(MCPKey.httpFooter)
                            : settings.text(MCPKey.stdioFooter)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(settings.text(MCPKey.offerTools), isOn: $isEnabled)
                    field(settings.text(MCPKey.fieldTrust)) {
                        Picker(settings.text(MCPKey.fieldTrust), selection: $trust) {
                            ForEach(MCPTrust.allCases) { Text($0.title(settings.language)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    HStack(spacing: Theme.Spacing.lg) {
                        Button(settings.text(MCPKey.testConnection), action: test)
                            .disabled(operation != nil)
                        probeLabel
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                } footer: {
                    Text(settings.text(MCPKey.trustFooter))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Button(settings.text(MCPKey.buttonCancel), action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(MCPKey.buttonSave), action: save)
                    .disabled(operation != nil)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 560)
        .settingsEditorPanelSurface()
        .onDisappear {
            operation?.cancel()
            coordinator.cancelSignIn(target.server.id)
            if target.isNew { coordinator.discardUnsaved(target.server.id) }
        }
        .onChange(of: url) { cancelOperation() }
        .onChange(of: usesOAuth) { cancelOperation() }
        .onChange(of: kind) { cancelOperation() }
        .onChange(of: clientID) { cancelOperation() }
        .onChange(of: clientSecret) { cancelOperation() }
    }

    /// OAuth 模式下的客户端凭证输入与登录/登出操作行。
    private var oauthFields: some View {
        Group {
            field(settings.text(MCPKey.clientID)) {
                TextField(
                    settings.text(MCPKey.clientID), text: $clientID,
                    prompt: Text(settings.text(MCPKey.clientIDPrompt))
                )
                .settingsEditorTextField()
            }
            field(settings.text(MCPKey.clientSecret)) {
                RevealableSecureField(
                    title: settings.text(MCPKey.clientSecret), text: $clientSecret,
                    prompt: Text(settings.text(MCPKey.optional))
                )
                .settingsEditorTextField()
            }
            field(settings.text(MCPKey.signInSection)) {
                HStack(spacing: Theme.Spacing.lg) {
                    switch authenticationStatus {
                    case .signedIn:
                        Button(settings.text(MCPKey.signOut), action: signOut)
                            .disabled(operation != nil)
                    case .signingIn:
                        Button(settings.text(MCPKey.buttonCancel), action: cancelOperation)
                    default:
                        Button(settings.text(MCPKey.signIn), action: signIn)
                            .disabled(operation != nil)
                    }
                    Text(authenticationStatus.label(settings.language))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 由输入框当前内容构造的 OAuth 客户端凭证。
    private var supplied: MCPOAuth.Credentials { .supplied(clientID: clientID, clientSecret: clientSecret) }

    /// 结合表单当前输入判断的登录状态；输入与服务端不符时回落为未登录。
    private var authenticationStatus: MCPOAuthManager.Status {
        var server = target.server
        server.transport = .http(
            url: url.trimmingCharacters(in: .whitespaces),
            headerName: headerName.trimmingCharacters(in: .whitespaces))
        let status = coordinator.authenticationStatus(server, stored: storedOAuth)
        let supplied = supplied
        guard storedOAuth?.clientID == supplied.clientID, storedOAuth?.clientSecret == supplied.clientSecret,
            storedOAuth?.registration?.resource == (try? MCPOAuth.resource(url))
        else {
            if case .signingIn = status { return status }
            if case .failed = status { return status }
            return .signedOut
        }
        return status
    }

    /// 校验表单后发起 OAuth 登录，成功后刷新本地存储的凭证副本。
    private func signIn() {
        if let message = validate() { error = message; return }
        error = nil
        let draft = draft
        guard let credentials = draft.secrets.oauth else { return }
        operation = Task {
            defer { operation = nil }
            do {
                try await coordinator.signIn(draft.server, credentials: credentials)
                storedOAuth = MCPSecretStore().secrets(for: target.server.id).oauth
            } catch is CancellationError {
                return
            } catch let failure as MCPOAuth.Failure {
                self.error = failure.message(settings.language)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// 登出并清除本地保存的 token。
    private func signOut() {
        do {
            try coordinator.signOut(target.server.id)
            storedOAuth?.token = nil
            probe = .idle
            error = nil
        } catch { self.error = settings.text(MCPKey.credentialsRemoveFailed) }
    }

    /// 取消进行中的登录或测试操作并重置探测状态。
    private func cancelOperation() {
        operation?.cancel()
        coordinator.cancelSignIn(target.server.id)
        probe = .idle
    }

    /// 展示 Test Connection 的探测进度与结果。
    @ViewBuilder private var probeLabel: some View {
        switch probe {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .found(let count):
            let key = count == 1 ? MCPKey.toolCountOne : MCPKey.toolCount
            Label(
                String(format: settings.text(key), count), systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// 统一用 SettingsEditorField 包裹一个表单字段。
    private func field<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsEditorField(label, content: content)
    }

    /// 由表单当前状态构造待保存的服务器与凭证（含 OAuth 注册缓存处理）。
    private var draft: (server: MCPServer, secrets: MCPSecretStore.Secrets) {
        var server = target.server
        server.name = name
        server.isEnabled = isEnabled
        server.trust = trust
        let environment = Self.environment(from: environmentText)
        switch kind {
        case .http:
            server.transport = .http(
                url: url.trimmingCharacters(in: .whitespaces),
                headerName: headerName.trimmingCharacters(in: .whitespaces))
            server.oauth = usesOAuth ? true : nil
            var secrets = MCPSecretStore.Secrets(headerValue: usesOAuth ? "" : headerValue)
            if usesOAuth {
                var credentials = MCPSecretStore().secrets(for: server.id).oauth ?? MCPOAuth.Credentials()
                let supplied = supplied
                if credentials.clientID != supplied.clientID
                    || credentials.clientSecret != supplied.clientSecret
                {
                    credentials = supplied
                }
                if let registration = credentials.registration,
                    registration.resource != (try? MCPOAuth.resource(url))
                {
                    credentials.token = nil
                }
                secrets.oauth = credentials
            }
            return (server, secrets)
        case .stdio:
            server.oauth = nil
            server.transport = .stdio(
                command: command.trimmingCharacters(in: .whitespaces),
                arguments: Self.arguments(from: argumentText),
                environmentKeys: environment.keys.sorted())
            return (server, MCPSecretStore.Secrets(environment: environment))
        }
    }

    /// 真正的握手验证，让拼写错误在这里暴露，而不是在对话中途才暴露。
    private func test() {
        guard validate() == nil else {
            error = validate()
            return
        }
        error = nil
        probe = .running
        let draft = draft
        operation = Task {
            defer { operation = nil }
            let status = await coordinator.test(draft.server, secrets: draft.secrets)
            guard !Task.isCancelled else { return }
            switch status {
            case .ready(let tools): probe = .found(tools)
            case .failed(let message): probe = .failed(message)
            case .signInRequired: probe = .failed(settings.text(MCPKey.probeSignInRequired))
            default: probe = .failed(settings.text(MCPKey.probeNoAnswer))
            }
        }
    }

    /// 校验并保存表单内容，错误信息由 onSave 返回。
    private func save() {
        if let message = validate() {
            error = message
            return
        }
        let draft = draft
        error = onSave(draft.server, draft.secrets)
    }

    /// 校验必填项（HTTP 需合法 URL，stdio 需非空 command）；合法时返回 nil。
    private func validate() -> String? {
        switch kind {
        case .http:
            do {
                _ = try AIEndpointPolicy.validate(url)
            } catch {
                return error.localizedDescription
            }
        case .stdio where command.trimmingCharacters(in: .whitespaces).isEmpty:
            return settings.text(MCPKey.commandRequired)
        case .stdio:
            break
        }
        return nil
    }

    /// 以空白分隔参数，并支持引号，用于路径中带空格的那类参数。
    private static func arguments(from text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { arguments.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }

    /// 把逐行的 NAME=value 文本解析为环境变量字典。
    private static func environment(from text: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            environment[key] = String(line[line.index(after: separator)...])
        }
        return environment
    }
}
