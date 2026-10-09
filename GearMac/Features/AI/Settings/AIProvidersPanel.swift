// 文件职责：设置 → AI → Providers 面板，左侧列出全部 AI 来源（本机模型、已安装命令、API 连接），右侧显示所选来源的分页详情与启停开关。
// 分层：UI + Settings 编排；读写 AISettingsStore 与 Keychain，并触发 InstalledAIManager / ChatGPTSubscriptionManager 的生命周期。
import AppKit
import SwiftUI

/// Providers 列表中的一项：本机模型、已安装命令或 API 连接。
enum AIProviderRoute: Hashable {
    case appleIntelligence
    case installed(InstalledAIKind)
    case api(UUID)

    /// 该路由对应的模型来源。
    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .installed(let kind): return kind.source
        case .api(let id): return .api(id)
        }
    }
}

/// 来源详情的一页；某路由只列出它确实有内容的页。
enum AIProviderTab: String, CaseIterable, Identifiable {
    case overview
    case models
    case advanced

    var id: String { rawValue }

    /// 页签的显示标题。
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        case .advanced: return "Advanced"
        }
    }

    /// 按路由返回可用的页签列表。
    static func tabs(for route: AIProviderRoute) -> [AIProviderTab] {
        switch route {
        case .appleIntelligence: return [.overview]
        case .installed: return [.overview, .models, .advanced]
        case .api: return [.overview, .models]
        }
    }
}

/// 设置 → AI → Providers：左侧列出全部路由，右侧显示所选路由的分页。
struct AIProvidersPanel: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    let onDone: () -> Void

    @State private var selection: AIProviderRoute?
    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?
    @State private var modelQuery = ""
    /// 跨来源保留，如同 Mail 跨账户保留页签；没有该页的来源回落到 Overview。
    @State private var tab = AIProviderTab.overview

    private let keyStore = KeychainSecretStore.aiAPIKeys

    /// 渲染头部、列表/详情两栏与底部 Done，并挂载编辑面板与移除确认弹窗。
    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "AI Providers",
                subtitle: "Installed tools, API connections, and the models each one offers."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: Theme.Size.aiProvidersList)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // 固定高度而非自适应：选择标题更长的来源不能改变面板尺寸。
            .frame(height: Theme.Size.aiProvidersPanel.height)
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .frame(width: Theme.Size.aiProvidersPanel.width)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .releasesFocusOnOutsideClick()
        .settingsEditorPanel(item: $editor) { target in
            AIConnectionEditorPanel(
                target: target,
                onSave: saveConnection,
                onCancel: { editor = nil })
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove “\($0.title)”?" } ?? "Remove connection?",
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Connection", role: .destructive) {
                if let pendingRemoval { removeConnection(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its saved API key will also be deleted from Keychain.")
        }
        .onAppear {
            selection = selection ?? initialSelection
            loadKeyStatuses()
            core.applyInstalledAILifecycle()
        }
        .onChange(of: selection) { modelQuery = "" }
        .onChange(of: settings.connections.map(\.id)) { _, ids in
            if case .api(let id) = selection, !ids.contains(id) { selection = .installed(.codex) }
        }
    }

    // MARK: - List

    /// macOS 15 没有 FoundationModels，本机路由整体不展示（空 Section 随 header 一并隐藏）；
    /// 26 上仅设备不支持等状态仍展示，可解释原因。复用 status() 判断，不新增可用性分支。
    private var showsAppleIntelligenceRoute: Bool {
        AppleIntelligenceProvider.status() != .requiresNewerSystem
    }

    /// 左侧来源列表：按本机、已安装、API 连接分组，底部为增删操作。
    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("On This Mac") {
                    if showsAppleIntelligenceRoute {
                        listRow(.appleIntelligence)
                    }
                }
                Section("Installed") {
                    ForEach(InstalledAIKind.allCases) { listRow(.installed($0)) }
                }
                Section("API Connections") {
                    if settings.connections.isEmpty {
                        Text("None yet")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(settings.connections) { listRow(.api($0.id)) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            listActions
        }
    }

    /// 单个来源列表行：图标、标题与状态摘要。
    private func listRow(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            AIProviderTile(icon: icon(for: route))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .lineLimit(1)
                Text(caption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .tag(route)
    }

    /// 类似 Mail 的 Accounts 列表：在列表下方新增，并移除当前选中项。
    private var listActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Menu {
                ForEach(AIProviderKind.allCases) { provider in
                    Button(provider.title) {
                        editor = AIConnectionEditorTarget(
                            connection: AIConnection(provider: provider),
                            hasStoredKey: false, isNew: true)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add API Connection")
            .accessibilityLabel("Add API Connection")
            Button {
                pendingRemoval = selectedConnection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selectedConnection == nil)
            .help("Remove API Connection")
            .accessibilityLabel("Remove API Connection")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Detail

    /// 右侧详情：按当前选中路由渲染对应表单，未选中时显示占位。
    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appleIntelligence?:
            detailForm(.appleIntelligence) { _ in appleIntelligenceSections }
        case .installed(let kind)?:
            detailForm(.installed(kind)) { installedSections(kind, tab: $0) }
        case .api(let id)?:
            if let connection = settings.connection(id: id) {
                detailForm(.api(id)) { connectionSections(connection, tab: $0) }
            }
        case nil:
            ContentUnavailableView("Select a provider", systemImage: "sparkles")
        }
    }

    /// 渲染详情头部、页签选择器与当前页内容，并按路由切换重置状态。
    private func detailForm<Content: View>(
        _ route: AIProviderRoute, @ViewBuilder content: (AIProviderTab) -> Content
    ) -> some View {
        let tabs = AIProviderTab.tabs(for: route)
        let shown = tabs.contains(tab) ? tab : .overview
        return VStack(spacing: 0) {
            detailHeader(route)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xl)
            if tabs.count > 1 {
                Picker("Page", selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.top, Theme.Spacing.xl)
            }
            Form { content(shown) }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
        .id(route)
    }

    /// 详情头部：图标、标题、副标题、版本/编辑入口与启停开关。
    private func detailHeader(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            AIProviderTile(icon: icon(for: route), size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .font(Theme.Typography.panelTitle)
                    .lineLimit(1)
                Text(kindCaption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.lg)
            switch route {
            case .installed(let kind):
                if let version = installedAI.status(for: kind).version,
                    settings.enabledInstalledProviders.contains(kind)
                {
                    Text("v" + version)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case .api(let id):
                if let connection = settings.connection(id: id) {
                    Button("Edit…") { edit(connection) }
                }
            case .appleIntelligence:
                EmptyView()
            }
            routeToggle(route)
        }
    }

    // MARK: On this Mac

    /// 本机 Apple Intelligence 的可用状态与说明。
    @ViewBuilder
    private var appleIntelligenceSections: some View {
        let available = settings.isAppleIntelligenceAvailable()
        if !settings.isRouteEnabled(.appleIntelligence) { turnedOffSection() }
        Section {
            LabeledContent {
                Text(available ? "Ready" : "Unavailable")
                    .foregroundStyle(.secondary)
            } label: {
                Text(AppleIntelligence.title)
                Text(
                    available
                        ? "Runs on this Mac. Nothing leaves it."
                        : AppleIntelligenceProvider.status().message ?? "Not available on this Mac.")
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Choose the default model on the AI pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Installed commands

    /// 已安装命令的详情页：Advanced 显示路径与变量，Overview/Models 显示状态与模型。
    @ViewBuilder
    private func installedSections(_ kind: InstalledAIKind, tab: AIProviderTab) -> some View {
        let isOn = settings.enabledInstalledProviders.contains(kind)
        switch tab {
        case .advanced:
            AIProviderAdvancedSection(kind: kind, detected: isOn ? executable(for: kind) : nil)
        case .overview, .models:
            if !isOn {
                turnedOffSection(footer: installedFooter(kind))
            } else if tab == .models {
                modelsSection(route: .installed(kind), models: installedModels(kind))
            } else {
                Section {
                    if kind == .codex {
                        codexStatusRows
                    } else {
                        installedStatusRows(kind)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text(installedFooter(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 来源被关闭时显示的提示区。
    private func turnedOffSection(footer: String? = nil) -> some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                Label("Turned off", systemImage: "pause.circle")
                Text("GearMac leaves it alone, and its models stay out of every model picker.")
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Codex 订阅的各状态行：检查中、需登录、已连接、未安装或检查失败。
    @ViewBuilder
    private var codexStatusRows: some View {
        switch subscription.phase {
        case .idle, .starting:
            checkingRow("Codex")
        case .signedOut:
            signInRow(.codex, check: { subscription.refresh() })
        case .connected:
            LabeledContent {
                Button("Refresh") { subscription.refresh() }
            } label: {
                Text("Ready")
                Text(modelCount(subscription.models.count) + " available")
            }
            if let account = subscription.account {
                LabeledContent {
                    Text(account.planTitle == "API key" ? "Codex API key" : "ChatGPT \(account.planTitle)")
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Account")
                    if let email = account.email {
                        RedactedText(
                            value: email,
                            revealHelp: "Click to reveal the signed-in account",
                            hideHelp: "Click to hide the signed-in account")
                    }
                }
            }
            if let limits = subscription.rateLimits {
                if let primary = limits.primary { usageRow(primary, fallbackTitle: "Primary window") }
                if let secondary = limits.secondary {
                    usageRow(secondary, fallbackTitle: "Secondary window")
                }
            }
            if let executable = subscription.executable { commandRow(executable) }
        case .unavailable(let message):
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install Codex CLI…") { NSWorkspace.shared.open(InstalledAIKind.codex.installURL) }
                    Button("Check Again") { subscription.refresh() }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text(message)
            }
        case .failed(let message):
            failedRow(message, retry: { subscription.refresh() })
        }
    }

    /// 其他已安装命令的状态行。
    @ViewBuilder
    private func installedStatusRows(_ kind: InstalledAIKind) -> some View {
        let status = installedAI.status(for: kind)
        switch status.phase {
        case .idle, .checking:
            checkingRow(kind.title)
        case .ready:
            LabeledContent {
                Button("Refresh") { installedAI.refresh(kind: kind) }
            } label: {
                Text("Ready")
                Text(modelCount(status.models.count) + " available")
            }
            if let account = status.account { accountRow(account, kind: kind) }
        case .signInRequired:
            signInRow(kind, check: { installedAI.refresh(kind: kind) })
        case .notInstalled:
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install…") { NSWorkspace.shared.open(kind.installURL) }
                    Button("Check Again") { installedAI.refresh(kind: kind) }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text("GearMac could not find the \(kind.command) command.")
            }
        case .failed(let message):
            failedRow(message, retry: { installedAI.refresh(kind: kind) })
        }
        if let executable = status.executable { commandRow(executable) }
    }

    /// 显示命令可执行文件路径的行。
    private func commandRow(_ executable: URL) -> some View {
        LabeledContent("Command") {
            Text((executable.path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    /// 显示账号邮箱与套餐的行，邮箱默认打码。
    private func accountRow(_ account: InstalledAIAccount, kind: InstalledAIKind) -> some View {
        LabeledContent {
            if let plan = account.planTitle {
                Text("\(kind.title) \(plan)").foregroundStyle(.secondary)
            }
        } label: {
            Text("Account")
            if let email = account.email {
                RedactedText(
                    value: email,
                    revealHelp: "Click to reveal the signed-in account",
                    hideHelp: "Click to hide the signed-in account")
            }
        }
    }

    /// 返回该已安装工具当前使用的可执行文件位置。
    private func executable(for kind: InstalledAIKind) -> URL? {
        kind == .codex ? subscription.executable : installedAI.status(for: kind).executable
    }

    /// 检查过程中的加载行。
    private func checkingRow(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.small)
            Text("Checking \(title)…").foregroundStyle(.secondary)
        }
    }

    /// 需要登录的行，提供复制登录命令与重新检查。
    private func signInRow(_ kind: InstalledAIKind, check: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Copy Sign-In Command") { copySignInCommand(kind) }
                Button("Check Again", action: check)
            }
            .fixedSize()
        } label: {
            Text("Sign in required")
            Text("Run \(kind.signInCommand) in Terminal, then check again.")
        }
    }

    /// 检查失败的行，提供重试。
    private func failedRow(_ message: String, retry: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Try Again", action: retry)
        } label: {
            Label("Check failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
        }
    }

    /// 用量窗口行：剩余百分比进度条与重置时间。
    private func usageRow(
        _ window: ChatGPTSubscription.UsageWindow, fallbackTitle: String
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .frame(width: Theme.Size.aiUsageBar)
                Text("\(window.remainingPercent)% left")
                    .monospacedDigit()
            }
        } label: {
            Text(usageTitle(window, fallback: fallbackTitle))
            if let reset = window.resetsAt {
                Text("Resets \(reset, style: .relative)")
            }
        }
    }

    /// 该工具的底部说明，优先显示隔离限制提示。
    private func installedFooter(_ kind: InstalledAIKind) -> String {
        kind.isolationCaveat(hasManagedMCPPolicy: InstalledAIManager.hasManagedMCPPolicy)
            ?? "Uses the \(kind.command) command signed in on this Mac. Its keys are never stored."
    }

    /// 该已安装工具当前可用的模型列表。
    private func installedModels(_ kind: InstalledAIKind) -> [ProviderModel] {
        if kind == .codex {
            guard subscription.isConnected else { return [] }
            return subscription.models.map { ProviderModel(id: $0.id, name: $0.name) }
        }
        let status = installedAI.status(for: kind)
        guard status.isReady else { return [] }
        return status.models.map { ProviderModel(id: $0.id, name: $0.name) }
    }

    // MARK: API connections

    /// API 连接的详情页：Models 页显示模型清单，否则显示连接信息。
    @ViewBuilder
    private func connectionSections(
        _ connection: AIConnection, tab: AIProviderTab
    ) -> some View {
        if !settings.isRouteEnabled(.api(connection.id)) { turnedOffSection() }
        if tab == .models {
            modelsSection(
                route: .api(connection.id),
                models: connection.models.map { ProviderModel(id: $0, name: $0) })
        } else {
            connectionSection(connection)
        }
    }

    /// API 连接信息区：Provider、Base URL 与密钥状态。
    private func connectionSection(_ connection: AIConnection) -> some View {
        Section {
            LabeledContent("Provider", value: connection.provider.title)
            LabeledContent("Base URL") {
                Text(connection.baseURL)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("API key") {
                Text(keyStatus(connection))
                    .foregroundStyle(
                        keyIsMissing(connection) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            if keyError {
                Label("The login Keychain could not be accessed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Keys stay in your login Keychain, tied to the endpoint they were saved for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Models

    /// 模型清单区：显示/隐藏统计、过滤框与复选框清单。
    @ViewBuilder
    private func modelsSection(route: AIProviderRoute, models: [ProviderModel]) -> some View {
        if models.isEmpty {
            Section {
                Text("Models are listed here once \(title(for: route)) is ready.")
                    .foregroundStyle(.secondary)
            }
        } else {
            let source = route.source
            let shownSet = settings.shownModels[source.storageKey].map(Set.init)
            let shownCount = shownSet.map { set in models.count { set.contains($0.id) } } ?? models.count
            let matches = filtered(models)
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Show All") { settings.showAllModels(in: source) }
                            .disabled(shownCount == models.count)
                        Button("Hide All") { settings.hideAllModels(in: source) }
                    }
                    .fixedSize()
                } label: {
                    Text("\(shownCount) of \(modelCount(models.count)) in the model picker")
                }
                if models.count > Self.filterThreshold {
                    SettingsFilterField(prompt: "Filter models", query: $modelQuery)
                }
                if matches.isEmpty {
                    Text("No model matches “\(modelQuery)”.")
                        .foregroundStyle(.secondary)
                }
                if !matches.isEmpty {
                    AIModelChecklist(
                        items: matches.map { model in
                            AIModelChecklist.Item(
                                id: model.id, title: model.name,
                                isOn: shownSet?.contains(model.id) ?? true,
                                isLocked: isDefault(model.id, route: route))
                        },
                        onToggle: { id, isOn in
                            settings.setModel(
                                id, shown: isOn, in: source, available: models.map(\.id))
                        })
                }
            } footer: {
                Text(
                    "Ticked models appear in the model picker. The default model always does; "
                        + "choose it on the AI pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// 超过一屏时（OpenCode 单独就会列出数百个），清单才出现设置页的过滤行。
    private static let filterThreshold = 8

    /// 按查询过滤模型（匹配名称或 id）。
    private func filtered(_ models: [ProviderModel]) -> [ProviderModel] {
        let query = modelQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    /// 判断某模型是否正是当前默认模型。
    private func isDefault(_ model: String, route: AIProviderRoute) -> Bool {
        guard let selection = settings.defaultModel else { return false }
        return selection.source == route.source && selection.model == model
    }

    // MARK: - Titles and glyphs

    /// 来源的显示标题。
    private func title(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return AppleIntelligence.title
        case .installed(let kind): return kind.title
        case .api(let id): return settings.connection(id: id)?.title ?? "API Connection"
        }
    }

    /// 详情头部使用的来源类型说明。
    private func kindCaption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return "On this Mac · No account needed"
        case .installed(let kind): return "Installed command · \(kind.command)"
        case .api(let id):
            return "API connection · " + (settings.connection(id: id)?.provider.title ?? "")
        }
    }

    /// 列表中最值得一读的一行：是否可用，以及不可用的原因。
    private func caption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence:
            guard settings.isRouteEnabled(.appleIntelligence) else { return "Off" }
            return settings.isAppleIntelligenceAvailable() ? "Ready · Runs on this Mac" : "Unavailable"
        case .installed(let kind):
            guard settings.enabledInstalledProviders.contains(kind) else { return "Off" }
            return kind == .codex ? codexCaption : installedCaption(kind)
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return "" }
            guard settings.isRouteEnabled(.api(id)) else { return "Off" }
            if keyIsMissing(connection) { return "Key missing" }
            let count = modelCount(connection.models.count)
            return connection.name.isEmpty ? count : "\(connection.provider.title) · \(count)"
        }
    }

    /// Codex 路由的列表状态摘要。
    private var codexCaption: String {
        switch subscription.phase {
        case .idle, .starting: return "Checking…"
        case .signedOut: return "Sign in required"
        case .unavailable: return "Not installed"
        case .failed: return "Check failed"
        case .connected:
            let count = modelCount(subscription.models.count)
            guard let account = subscription.account else { return "Ready · " + count }
            let plan = account.planTitle == "API key" ? "API key" : "ChatGPT \(account.planTitle)"
            return "\(plan) · \(count)"
        }
    }

    /// 已安装命令路由的列表状态摘要。
    private func installedCaption(_ kind: InstalledAIKind) -> String {
        let status = installedAI.status(for: kind)
        switch status.phase {
        case .idle, .checking: return "Checking…"
        case .ready: return "Ready · " + modelCount(status.models.count)
        case .signInRequired: return "Sign in required"
        case .notInstalled: return "Not installed"
        case .failed: return "Check failed"
        }
    }

    /// 该路由在列表与详情中使用的图标。
    private func icon(for route: AIProviderRoute) -> PopoverMenuIcon {
        switch route {
        case .appleIntelligence: return AIModelOption.appleIntelligenceIcon
        case .installed(.codex): return .asset(AIBrand.openAI.assetName)
        case .installed(.claude): return .asset(AIBrand.claude.assetName)
        case .installed(.grok): return .asset(AIBrand.grok.assetName)
        case .installed(.openCode): return .asset(AIBrand.openCode.assetName)
        case .installed(.cursor): return AIModelOption.cursorIcon
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return .symbol("sparkles") }
            // OpenRouter 有自己的品牌标识；按模型解析会显示最先出现的厂商图标。
            if connection.provider == .openRouter { return .asset(AIBrand.openRouter.assetName) }
            return AIModelOption.icon(
                AIBrand.resolve(provider: connection.provider, model: connection.models.first ?? ""))
        }
    }

    /// 模型数量的文案（单复数处理）。
    private func modelCount(_ count: Int) -> String {
        count == 1 ? "1 model" : "\(count) models"
    }

    // MARK: - Actions

    /// 默认打开默认模型所用的路由，因为它最常被查看。
    private var initialSelection: AIProviderRoute {
        switch settings.defaultModel?.source {
        case .appleIntelligence?: return .appleIntelligence
        case .api(let id)?: return .api(id)
        case let source?:
            return source.installedKind.map(AIProviderRoute.installed) ?? .installed(.codex)
        case nil: return .installed(.codex)
        }
    }

    /// 当前选中的 API 连接（未选中 API 路由时为 nil）。
    private var selectedConnection: AIConnection? {
        guard case .api(let id) = selection else { return nil }
        return settings.connection(id: id)
    }

    /// 路由的启用开关。
    private func routeToggle(_ route: AIProviderRoute) -> some View {
        Toggle(
            "Enable \(title(for: route))",
            isOn: Binding(
                get: { settings.isRouteEnabled(route.source) },
                set: { settings.setRoute(route.source, enabled: $0) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
    }

    /// 移除确认弹窗的展开绑定。
    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    /// 是否缺少可用密钥（本地端点无需密钥）。
    private func keyIsMissing(_ connection: AIConnection) -> Bool {
        keyStatuses[connection.id] != true && !AIEndpointPolicy.isLoopback(connection.baseURL)
    }

    /// 密钥状态文案。
    private func keyStatus(_ connection: AIConnection) -> String {
        if keyStatuses[connection.id] == true { return "Stored in Keychain" }
        return AIEndpointPolicy.isLoopback(connection.baseURL) ? "None needed locally" : "Missing"
    }

    /// 打开该连接的编辑面板。
    private func edit(_ connection: AIConnection) {
        editor = AIConnectionEditorTarget(
            connection: connection,
            hasStoredKey: keyStatuses[connection.id] == true,
            isNew: false)
    }

    /// 按密钥策略写入/删除/保留密钥，然后保存连接并刷新状态；出错时返回提示文案。
    private func saveConnection(
        _ connection: AIConnection, key: String, isNew: Bool
    ) -> String? {
        let outcome = AIConnectionKeyPolicy.resolve(
            enteredKey: key, connection: connection, saved: settings.connection(id: connection.id),
            hasStoredKey: keyStatuses[connection.id] == true)
        do {
            switch outcome {
            case .store(let key): try keyStore.setSecret(key, for: connection.id)
            case .removeStored: try keyStore.removeSecret(for: connection.id)
            case .keep: break
            case .reject(let message): return message
            }
            settings.save(connection)
            editor = nil
            selection = .api(connection.id)
            loadKeyStatuses()
            settings.reconcile(subscription: subscription, installedAI: installedAI)
            return nil
        } catch {
            keyError = true
            return isNew
                ? "The key could not be saved to Keychain."
                : "The saved key could not be updated in Keychain."
        }
    }

    /// 删除连接及其在 Keychain 中的密钥。
    private func removeConnection(_ connection: AIConnection) {
        do {
            try keyStore.removeSecret(for: connection.id)
            settings.removeConnection(id: connection.id)
            pendingRemoval = nil
            loadKeyStatuses()
        } catch {
            keyError = true
        }
    }

    /// 复制登录命令并提示。
    private func copySignInCommand(_ kind: InstalledAIKind) {
        Paster.copyPlainText(kind.signInCommand)
        core.showMessage("Copied \(kind.signInCommand)")
    }

    /// 用量窗口标题，按分钟数换算为天/小时/分钟。
    private func usageTitle(
        _ window: ChatGPTSubscription.UsageWindow, fallback: String
    ) -> String {
        guard let minutes = window.durationMinutes else { return fallback }
        if minutes >= 1_440 { return "\(minutes / 1_440)-day window" }
        if minutes >= 60 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }

    /// 重新读取各连接的密钥存在状态。
    private func loadKeyStatuses() {
        var statuses: [UUID: Bool] = [:]
        do {
            for connection in settings.connections {
                statuses[connection.id] = try keyStore.hasSecret(for: connection.id)
            }
            keyStatuses = statuses
            keyError = false
        } catch {
            keyStatuses = statuses
            keyError = true
        }
    }
}

/// 模型行的内容，无论来自三种目录形态中的哪一种。
private struct ProviderModel: Identifiable {
    let id: String
    let name: String
}

/// 列表与头部的图标：SettingsTabIcon 所绘方块上的品牌标记或符号。
private struct AIProviderTile: View {
    let icon: PopoverMenuIcon
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        glyph
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(.primary)
            .padding(Theme.Spacing.xs * scale)
            .background(
                Theme.Colors.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    /// 按图标类型渲染具体图形，file/thumbnail/blank 统一回落为 sparkles。
    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .asset(let name):
            Image(name).resizable().renderingMode(.template).scaledToFit()
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .file, .thumbnail, .blank, .dot:
            Image(systemName: "sparkles").resizable().scaledToFit()
        }
    }
}

extension AISettingsStore {
    /// 把默认模型从刚消失的路由移开，或对齐到该路由当前的模型目录。
    func reconcile(subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager) {
        let enabled = enabledInstalledProviders
        reconcile(
            codexModels: enabled.contains(.codex) ? subscription.models : [],
            isUnavailable: !enabled.contains(.codex) || subscription.phase == .signedOut
                || subscription.phase.isUnavailable)
        for kind in InstalledAIKind.managedCLIKinds {
            let status = installedAI.status(for: kind)
            reconcile(
                installed: kind,
                models: enabled.contains(kind) ? status.models : [],
                isUnavailable: !enabled.contains(kind) || status.phase == .signInRequired
                    || status.phase == .notInstalled)
        }
    }
}
