// 文件职责：AI 设置的状态仓库，读写并持久化连接、默认模型、提示词、保留策略、模型显示与已安装工具覆盖项。
// 分层：Settings（@MainActor @Observable）；只依赖 UserDefaults 与 Keychain 存储抽象，不包含 UI 与 AppKit。
import Foundation
import Observation

@MainActor
@Observable
final class AISettingsStore {
    private let defaults: UserDefaults

    private(set) var connections: [AIConnection] {
        didSet { persistConnections() }
    }
    private(set) var defaultModel: AIModelSelection? {
        didSet { persistDefaultModel() }
    }
    /// 默认关闭：只有用户明确同意后，提示词才会发往搜索引擎。
    var webSearchEnabled: Bool {
        didSet { defaults.set(webSearchEnabled, forKey: AppSettingsKey.aiWebSearch.rawValue) }
    }
    /// 每轮对话都追加到 `AIInstructions.preamble` 之后，因此每轮都会计费。
    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: AppSettingsKey.aiSystemPrompt.rawValue) }
    }
    /// 默认开启：否则模型不知道自己在为哪个应用作答。
    var systemPromptEnabled: Bool {
        didSet {
            defaults.set(systemPromptEnabled, forKey: AppSettingsKey.aiSystemPromptEnabled.rawValue)
        }
    }
    /// 默认永久保留，避免升级时删掉用户未要求删除的记录。
    var retention: AIRetention {
        didSet { defaults.set(retention.rawValue, forKey: AppSettingsKey.aiRetention.rawValue) }
    }
    var opensTo: AIOpensTo {
        didSet { defaults.set(opensTo.rawValue, forKey: AppSettingsKey.aiOpensTo.rawValue) }
    }
    var newChatAfter: AINewChatAfter {
        didSet {
            defaults.set(newChatAfter.rawValue, forKey: AppSettingsKey.aiNewChatAfter.rawValue)
        }
    }
    var toolRounds: AIToolRounds {
        didSet { defaults.set(toolRounds.rawValue, forKey: AppSettingsKey.aiToolRounds.rawValue) }
    }
    /// 每条路由的模型选择器中列出的模型；没有条目表示列出全部（包括之后新增的）。
    private(set) var shownModels: [String: [String]] {
        didSet { defaults.set(shownModels, forKey: AppSettingsKey.aiShownModels.rawValue) }
    }
    /// 已关闭但未移除的本机模型与 API 连接。
    private(set) var disabledRoutes: Set<String> {
        didSet {
            defaults.set(disabledRoutes.sorted(), forKey: AppSettingsKey.aiDisabledRoutes.rawValue)
        }
    }
    var enabledInstalledProviders: Set<InstalledAIKind> {
        didSet {
            guard
                let data = try? JSONEncoder().encode(
                    enabledInstalledProviders.sorted(by: {
                        $0.rawValue < $1.rawValue
                    }))
            else { return }
            defaults.set(data, forKey: AppSettingsKey.aiInstalledProviders.rawValue)
        }
    }

    // MARK: - Decisions 判定

    /// Decide 动作与 Decisions 模型的聊天共用的一套判定问题。
    var decisionsQuestions: DecisionsQuestionSet {
        didSet { persistDecisionsQuestions() }
    }

    /// 首个启用的、模型目录里含 Decisions 模型的 API 连接；没有则为 nil。
    /// 端点、密钥与模型都来自这条连接，因此不再单独配置。
    func decisionsRoute() -> (connection: AIConnection, model: String)? {
        for connection in connections where isRouteEnabled(.api(connection.id)) {
            if let model = connection.models.first(where: DecisionsRouting.isDecisionsModel) {
                return (connection, model)
            }
        }
        return nil
    }
    /// 每个已安装工具的命令路径与变量名；未改动的工具没有条目。
    private(set) var installedOverrides: [InstalledAIKind: InstalledAIOverride] {
        didSet { persistInstalledOverrides() }
    }
    /// 每次修改工具启动配置（包含从名称上看不出的值变更）都会自增。
    private(set) var launchRevisions: [InstalledAIKind: Int] = [:]

    /// 每次实时询问：模型可能在会话中途就绪，启动时读取的标志无法感知。
    @ObservationIgnored let isAppleIntelligenceAvailable: @Sendable () -> Bool
    @ObservationIgnored private let environmentStore: InstalledAIEnvironmentStore

    /// 从 UserDefaults 读取全部设置，并在默认模型已失效时回落到首个可用选择。
    init(
        defaults: UserDefaults = .standard,
        environmentStore: InstalledAIEnvironmentStore = .none,
        isAppleIntelligenceAvailable: @escaping @Sendable () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.environmentStore = environmentStore
        self.isAppleIntelligenceAvailable = isAppleIntelligenceAvailable
        installedOverrides = Self.decodeInstalledOverrides(
            defaults.data(forKey: AppSettingsKey.aiInstalledOverrides.rawValue))
        connections = Self.decodeConnections(
            defaults.data(forKey: AppSettingsKey.aiConnections.rawValue))
        defaultModel = Self.decodeDefaultModel(
            defaults.data(forKey: AppSettingsKey.aiDefaultModel.rawValue))
        webSearchEnabled =
            defaults.object(forKey: AppSettingsKey.aiWebSearch.rawValue) as? Bool ?? false
        systemPrompt = defaults.string(forKey: AppSettingsKey.aiSystemPrompt.rawValue) ?? ""
        systemPromptEnabled =
            defaults.object(forKey: AppSettingsKey.aiSystemPromptEnabled.rawValue) as? Bool ?? true
        // 未设置时读作 0，而没有任何 retention 分支对应 0 —— `forever` 故意取负值。
        retention =
            AIRetention(rawValue: defaults.integer(forKey: AppSettingsKey.aiRetention.rawValue))
            ?? .forever
        opensTo =
            AIOpensTo(rawValue: defaults.integer(forKey: AppSettingsKey.aiOpensTo.rawValue))
            ?? .recent
        newChatAfter =
            AINewChatAfter(
                rawValue: defaults.integer(forKey: AppSettingsKey.aiNewChatAfter.rawValue))
            ?? .fiveMinutes
        toolRounds =
            AIToolRounds(rawValue: defaults.integer(forKey: AppSettingsKey.aiToolRounds.rawValue))
            ?? .twentyFive
        shownModels =
            defaults.dictionary(forKey: AppSettingsKey.aiShownModels.rawValue) as? [String: [String]]
            ?? [:]
        disabledRoutes = Set(
            defaults.stringArray(forKey: AppSettingsKey.aiDisabledRoutes.rawValue) ?? [])
        enabledInstalledProviders = Self.decodeEnabledInstalledProviders(
            defaults.data(forKey: AppSettingsKey.aiInstalledProviders.rawValue))
        decisionsQuestions = Self.decodeDecisionsQuestions(
            defaults.data(forKey: AppSettingsKey.aiDecisionsQuestions.rawValue))
        if case .api(let connection, let model, _) = defaultModel,
            !connections.contains(where: { $0.id == connection && $0.models.contains(model) })
        {
            defaultModel = firstAvailableSelection()
        }
        if let source = defaultModel?.source, !isRouteEnabled(source), source.installedKind == nil {
            defaultModel = firstAvailableSelection()
        }
        if defaultModel == nil {
            defaultModel = firstAvailableSelection()
        }
    }

    /// 按 id 查找连接。
    func connection(id: UUID) -> AIConnection? {
        connections.first { $0.id == id }
    }

    /// 选择默认模型；API 连接需确认模型仍在其列表中。
    func select(_ selection: AIModelSelection) {
        if case .api(let connection, let model, _) = selection {
            guard self.connection(id: connection)?.models.contains(model) == true else { return }
        }
        defaultModel = selection
    }

    /// 保存连接（规范化后插入或替换），并把默认模型对齐到该连接可用的模型。
    func save(_ connection: AIConnection) {
        let connection = normalized(connection)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if case .api(connection.id, let model, let effort) = defaultModel {
            if connection.models.contains(model) {
                defaultModel = .api(
                    connection: connection.id, model: model,
                    effort: connection.reasoningOptions(for: model)?.resolvedEffort(effort))
            } else {
                defaultModel = connection.models.first.map {
                    .api(
                        connection: connection.id, model: $0,
                        effort: connection.reasoningOptions(for: $0)?.resolvedEffort(nil))
                }
            }
        }
        if defaultModel == nil, let model = connection.models.first {
            defaultModel = .api(
                connection: connection.id, model: model,
                effort: connection.reasoningOptions(for: model)?.resolvedEffort(nil))
        }
    }

    /// 移除连接，并清理其模型显示与禁用记录，必要时切换默认模型。
    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        shownModels[AIModelSource.api(id).storageKey] = nil
        disabledRoutes.remove(AIModelSource.api(id).storageKey)
        guard case .api(id, _, _) = defaultModel else { return }
        defaultModel = firstAvailableSelection()
    }

    /// 让默认模型与 Codex 当前的模型目录保持一致。
    func reconcile(codexModels models: [ChatGPTSubscription.Model], isUnavailable: Bool) {
        guard case .codex(let model, let effort) = defaultModel else { return }
        if isUnavailable {
            defaultModel = firstAvailableSelection()
            return
        }
        guard !models.isEmpty else { return }
        if let match = models.first(where: { $0.id == model }) {
            let resolved = match.resolvedEffort(effort)
            if resolved != effort { defaultModel = .codex(model: model, effort: resolved) }
            return
        }
        guard let replacement = models.first(where: \.isDefault) ?? models.first else { return }
        defaultModel = .codex(
            model: replacement.id, effort: replacement.resolvedEffort(nil))
    }

    /// 让默认模型与某个已安装工具的模型目录保持一致。
    func reconcile(
        installed kind: InstalledAIKind, models: [InstalledAIModel], isUnavailable: Bool
    ) {
        let selectedModel: String
        switch (kind, defaultModel) {
        case (.claude, .claude(let model, _)), (.grok, .grok(let model, _)),
            (.openCode, .openCode(let model, _)), (.cursor, .cursor(let model, _)):
            selectedModel = model
        default:
            return
        }
        if isUnavailable {
            defaultModel = firstAvailableSelection()
            return
        }
        guard !models.isEmpty else { return }
        if let match = models.first(where: { $0.id == selectedModel }) {
            let resolved = match.resolvedEffort(defaultModel?.effort)
            if resolved != defaultModel?.effort { defaultModel = defaultModel?.withEffort(resolved) }
            return
        }
        guard let replacement = models.first else { return }
        switch kind {
        case .claude:
            defaultModel = .claude(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .grok:
            defaultModel = .grok(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .openCode:
            defaultModel = .openCode(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .cursor:
            defaultModel = .cursor(
                model: replacement.id, effort: replacement.resolvedEffort(nil))
        case .codex: break
        }
    }

    /// 尚未选择时才预置一个无需账号的默认路由，不会覆盖用户真实保存的选择。
    func resolveDefaultModel() {
        guard defaultModel == nil, let selection = firstAvailableSelection() else { return }
        defaultModel = selection
    }

    /// 该模型来源是否启用。
    func isRouteEnabled(_ source: AIModelSource) -> Bool {
        if let kind = source.installedKind { return enabledInstalledProviders.contains(kind) }
        return !disabledRoutes.contains(source.storageKey)
    }

    /// 已安装路由有自己的开关；其他来源被关闭时会把默认模型移走。
    func setRoute(_ source: AIModelSource, enabled: Bool) {
        if let kind = source.installedKind {
            setInstalledProviderEnabled(enabled, for: kind)
            return
        }
        if enabled {
            disabledRoutes.remove(source.storageKey)
        } else {
            disabledRoutes.insert(source.storageKey)
            if defaultModel?.source == source { defaultModel = firstAvailableSelection() }
        }
        if defaultModel == nil { defaultModel = firstAvailableSelection() }
    }

    /// 该模型是否出现在来源的模型选择器中。
    func isModelShown(_ model: String, in source: AIModelSource) -> Bool {
        shownModels[source.storageKey]?.contains(model) ?? true
    }

    /// `available` 是该路由的完整列表，在首次隐藏某个模型时需要用到。
    func setModel(
        _ model: String, shown: Bool, in source: AIModelSource, available: [String]
    ) {
        var shownList = shownModels[source.storageKey] ?? available
        shownList.removeAll { $0 == model }
        if shown { shownList.append(model) }
        // 全部重新显示时清除该条目，使路由之后新增的模型也会出现。
        let everything = Set(available)
        shownModels[source.storageKey] =
            everything.isSubset(of: shownList) ? nil : shownList.filter(everything.contains)
    }

    /// 显示该来源的全部模型（清除条目）。
    func showAllModels(in source: AIModelSource) {
        shownModels[source.storageKey] = nil
    }

    /// 默认模型始终保持列出，因为选择器必须能显示当前选中项。
    func hideAllModels(in source: AIModelSource) {
        let kept = defaultModel.flatMap { $0.source == source ? [$0.model] : nil } ?? []
        shownModels[source.storageKey] = kept
    }

    /// 启用/停用某个已安装工具。
    func setInstalledProviderEnabled(_ enabled: Bool, for kind: InstalledAIKind) {
        var providers = enabledInstalledProviders
        if enabled {
            providers.insert(kind)
        } else {
            providers.remove(kind)
        }
        enabledInstalledProviders = providers
    }

    /// 该工具的设置覆盖项，没有则返回空值。
    func override(for kind: InstalledAIKind) -> InstalledAIOverride {
        installedOverrides[kind] ?? InstalledAIOverride()
    }

    /// 设置命令路径覆盖项，变更时递增启动版本号。
    func setCommandPath(_ path: String, for kind: InstalledAIKind) {
        var override = override(for: kind)
        override.commandPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard override != self.override(for: kind) else { return }
        installedOverrides[kind] = override.isEmpty ? nil : override
        launchRevisions[kind, default: 0] += 1
    }

    /// 读取该工具的环境变量（名称来自覆盖项，值来自 Keychain）。
    func environment(for kind: InstalledAIKind) throws -> [InstalledAIVariable] {
        let values = try environmentStore.values(kind)
        return override(for: kind).environmentNames.map {
            InstalledAIVariable(name: $0, value: values[$0] ?? "")
        }
    }

    /// 先保存变量值：只有名称没有值会让工具以不完整配置启动。
    func setEnvironment(_ variables: [InstalledAIVariable], for kind: InstalledAIKind) throws {
        var seen = Set<String>()
        let kept = variables.filter {
            InstalledAILaunch.isVariableName($0.name) && seen.insert($0.name).inserted
        }
        guard try kept != environment(for: kind) else { return }
        try environmentStore.save(
            Dictionary(uniqueKeysWithValues: kept.map { ($0.name, $0.value) }), kind)
        var override = override(for: kind)
        override.environmentNames = kept.map(\.name)
        installedOverrides[kind] = override.isEmpty ? nil : override
        launchRevisions[kind, default: 0] += 1
    }

    /// 仅对配置了变量的工具读取 Keychain，多数启动流程不会触碰它。
    func launch(for kind: InstalledAIKind) -> InstalledAILaunch {
        let override = override(for: kind)
        guard !override.environmentNames.isEmpty else {
            return InstalledAILaunch(commandPath: override.commandPath)
        }
        let names = Set(override.environmentNames)
        let values = (try? environmentStore.values(kind)) ?? [:]
        return InstalledAILaunch(
            commandPath: override.commandPath,
            environment: values.filter { names.contains($0.key) })
    }

    /// 当某工具的模型选择被停用时，把默认模型移开。
    func disableInstalledModelSelection(for kind: InstalledAIKind) {
        guard let source = defaultModel?.source else { return }
        let matches =
            switch (kind, source) {
            case (.codex, .codex), (.claude, .claude), (.grok, .grok), (.openCode, .openCode),
                (.cursor, .cursor):
                true
            default: false
            }
        guard matches else { return }
        defaultModel = firstAvailableSelection()
    }

    /// 优先选本机模型：免费、私密、始终可用，不会出现意外的落点。
    private func firstAvailableSelection() -> AIModelSelection? {
        if isAppleIntelligenceAvailable(), isRouteEnabled(.appleIntelligence) {
            return .appleIntelligence
        }
        for connection in connections where isRouteEnabled(.api(connection.id)) {
            if let model = connection.models.first {
                return .api(
                    connection: connection.id, model: model,
                    effort: connection.reasoningOptions(for: model)?.resolvedEffort(nil))
            }
        }
        return nil
    }

    /// 把连接列表编码写入 UserDefaults。
    private func persistConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: AppSettingsKey.aiConnections.rawValue)
    }

    /// 把判定问题集写入 UserDefaults；编码失败时保留旧值，不让一次坏写入清空配置。
    private func persistDecisionsQuestions() {
        guard let data = try? JSONEncoder().encode(decisionsQuestions) else { return }
        defaults.set(data, forKey: AppSettingsKey.aiDecisionsQuestions.rawValue)
    }

    /// 把已安装工具覆盖项写入 UserDefaults，为空时移除键。
    private func persistInstalledOverrides() {
        let keyed = Dictionary(
            uniqueKeysWithValues: installedOverrides.map { ($0.key.rawValue, $0.value) })
        guard !keyed.isEmpty, let data = try? JSONEncoder().encode(keyed) else {
            defaults.removeObject(forKey: AppSettingsKey.aiInstalledOverrides.rawValue)
            return
        }
        defaults.set(data, forKey: AppSettingsKey.aiInstalledOverrides.rawValue)
    }

    /// 从 UserDefaults 数据解码已安装工具覆盖项。
    private static func decodeInstalledOverrides(
        _ data: Data?
    ) -> [InstalledAIKind: InstalledAIOverride] {
        guard let data,
            let keyed = try? JSONDecoder().decode([String: InstalledAIOverride].self, from: data)
        else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: keyed.compactMap { key, value in
                InstalledAIKind(rawValue: key).map { ($0, value) }
            })
    }

    /// 把默认模型写入 UserDefaults，为空时移除键。
    private func persistDefaultModel() {
        guard let defaultModel, let data = try? JSONEncoder().encode(defaultModel) else {
            defaults.removeObject(forKey: AppSettingsKey.aiDefaultModel.rawValue)
            return
        }
        defaults.set(data, forKey: AppSettingsKey.aiDefaultModel.rawValue)
    }

    /// 规范化连接：去除首尾空白、模型去重，并清理无效的视觉模型与推理选项。
    private func normalized(_ connection: AIConnection) -> AIConnection {
        var connection = connection
        connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        connection.models = connection.models.compactMap {
            let model = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, seen.insert(model).inserted else { return nil }
            return model
        }
        connection.visionModels = connection.visionModels.filter(seen.contains)
        connection.reasoningOptions = connection.reasoningOptions?.filter {
            seen.contains($0.key) && !$0.value.efforts.isEmpty
        }
        if connection.reasoningOptions?.isEmpty == true { connection.reasoningOptions = nil }
        return connection
    }

    /// 解码已保存的连接列表。
    private static func decodeConnections(_ data: Data?) -> [AIConnection] {
        guard let data,
            let connections = try? JSONDecoder().decode([AIConnection].self, from: data)
        else { return [] }
        return connections
    }

    /// 解码已保存的判定问题集；损坏时回落默认集，Decide 不因坏数据而变砖。
    private static func decodeDecisionsQuestions(_ data: Data?) -> DecisionsQuestionSet {
        guard let data,
            let set = try? JSONDecoder().decode(DecisionsQuestionSet.self, from: data)
        else { return .standard }
        return set
    }

    /// 解码已保存的默认模型。
    private static func decodeDefaultModel(_ data: Data?) -> AIModelSelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AIModelSelection.self, from: data)
    }

    /// 解码已启用的已安装工具集合。
    private static func decodeEnabledInstalledProviders(_ data: Data?) -> Set<InstalledAIKind> {
        guard let data,
            let providers = try? JSONDecoder().decode([InstalledAIKind].self, from: data)
        else { return [] }
        return Set(providers)
    }
}
