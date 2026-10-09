// 文件职责：定义模型选择项 AIModelOption 及其来源分组，并根据已启用/就绪的来源汇总可选模型与推理强度。
// 分层：UI/Model（SwiftUI 选择器数据）；只读取设置与各来源的管理器状态，不产生副作用。
import Foundation

/// 模型选择器里的一个候选项：选择值、显示标题、来源标题与图标。
struct AIModelOption: Identifiable {
    let selection: AIModelSelection
    let title: String
    let sourceTitle: String
    let menuIcon: PopoverMenuIcon

    static let appleIntelligenceIcon = PopoverMenuIcon.symbol("apple.intelligence")

    /// 汇总所有已启用且就绪的来源，按来源分组列出可选模型。
    @MainActor
    static func availableGroups(
        settings: AISettingsStore, subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager
    ) -> [AIModelOptionGroup] {
        let enabled = settings.enabledInstalledProviders
        let claude = installedAI.status(for: .claude)
        let grok = installedAI.status(for: .grok)
        let openCode = installedAI.status(for: .openCode)
        let cursor = installedAI.status(for: .cursor)
        // 即使未勾选，默认模型也要保留在列表中，否则选择器无法展示它当前持有的值。
        func shown(_ model: String, _ source: AIModelSource) -> Bool {
            settings.isModelShown(model, in: source)
                || (settings.defaultModel?.source == source && settings.defaultModel?.model == model)
        }
        func shown(_ models: [InstalledAIModel], _ source: AIModelSource) -> [InstalledAIModel] {
            models.filter { shown($0.id, source) }
        }
        return groupedCatalog(
            appleIntelligence: settings.isAppleIntelligenceAvailable()
                && settings.isRouteEnabled(.appleIntelligence),
            codex: enabled.contains(.codex) && subscription.isConnected
                ? subscription.models.filter { shown($0.id, .codex) } : [],
            claude: enabled.contains(.claude) && claude.isReady ? shown(claude.models, .claude) : [],
            grok: enabled.contains(.grok) && grok.isReady ? shown(grok.models, .grok) : [],
            openCode: enabled.contains(.openCode) && openCode.isReady
                ? shown(openCode.models, .openCode) : [],
            cursor: enabled.contains(.cursor) && cursor.isReady ? shown(cursor.models, .cursor) : [],
            connections: settings.connections.compactMap { connection in
                guard settings.isRouteEnabled(.api(connection.id)) else { return nil }
                var trimmed = connection
                trimmed.models.removeAll { !shown($0, .api(connection.id)) }
                return trimmed
            })
    }

    /// 无法识别的模型保留通用星光图标，而不去借用某家的品牌标记。
    static func icon(_ brand: AIBrand?) -> PopoverMenuIcon {
        brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    static let cursorIcon = PopoverMenuIcon.asset(AIBrand.cursor.assetName)

    /// Mac 能访问的所有路由，设备端优先：它是未配置任何服务的 Mac 唯一可用的路由。
    private static func catalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        grok: [InstalledAIModel],
        openCode: [InstalledAIModel],
        cursor: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOption] {
        let onDevice =
            appleIntelligence
            ? [
                AIModelOption(
                    selection: .appleIntelligence, title: AppleIntelligence.title,
                    sourceTitle: "On device", menuIcon: appleIntelligenceIcon)
            ] : []
        let codex = codex.map { model in
            AIModelOption(
                selection: .codex(model: model.id, effort: nil),
                title: model.name,
                sourceTitle: "Codex",
                menuIcon: .asset(AIBrand.openAI.assetName))
        }
        let claude = claude.map { model in
            AIModelOption(
                selection: .claude(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Claude", menuIcon: .asset(AIBrand.claude.assetName))
        }
        let grok = grok.map { model in
            AIModelOption(
                selection: .grok(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Grok", menuIcon: .asset(AIBrand.grok.assetName))
        }
        let openCode = openCode.map { model in
            AIModelOption(
                selection: .openCode(model: model.id, effort: nil), title: model.name,
                sourceTitle: "OpenCode", menuIcon: icon(AIBrand.resolve(model: model.id)))
        }
        let cursor = cursor.map { model in
            AIModelOption(
                selection: .cursor(model: model.id, effort: nil), title: model.name,
                sourceTitle: "Cursor", menuIcon: cursorIcon)
        }
        let api = connections.flatMap { connection in
            connection.models.map { model in
                AIModelOption(
                    selection: .api(connection: connection.id, model: model, effort: nil),
                    title: model,
                    sourceTitle: connection.title,
                    menuIcon: icon(AIBrand.resolve(provider: connection.provider, model: model)))
            }
        }
        return onDevice + codex + claude + grok + openCode + cursor + api
    }

    /// 把扁平的模型列表按来源切成连续的分组（同一来源相邻即归为一组）。
    private static func groupedCatalog(
        appleIntelligence: Bool,
        codex: [ChatGPTSubscription.Model],
        claude: [InstalledAIModel],
        grok: [InstalledAIModel],
        openCode: [InstalledAIModel],
        cursor: [InstalledAIModel],
        connections: [AIConnection]
    ) -> [AIModelOptionGroup] {
        var groups: [AIModelOptionGroup] = []
        for option in catalog(
            appleIntelligence: appleIntelligence, codex: codex, claude: claude, grok: grok,
            openCode: openCode, cursor: cursor, connections: connections)
        {
            if groups.last?.id == option.selection.source {
                groups[groups.count - 1].options.append(option)
            } else {
                groups.append(
                    AIModelOptionGroup(
                        source: option.selection.source, title: option.sourceTitle,
                        options: [option]))
            }
        }
        return groups
    }

    /// 模型列表只给出路由名；它自带的推理强度取该路由的默认值。
    @MainActor
    static func withDefaultEffort(
        _ selection: AIModelSelection, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> AIModelSelection {
        let model = selection.model
        let effort: String?
        switch selection.source {
        case .appleIntelligence:
            return selection
        case .codex:
            effort = subscription.models.first { $0.id == model }?.resolvedEffort(nil)
        case .claude, .grok, .openCode, .cursor:
            effort = installedAI.models(for: selection.source)
                .first { $0.id == model }?.resolvedEffort(nil)
        case .api(let connection):
            effort = settings.connection(id: connection)?
                .reasoningOptions(for: model)?.resolvedEffort(nil)
        }
        return selection.withEffort(effort)
    }

    /// 某个选择值可用的推理强度列表；Apple Intelligence 不支持时返回空。
    @MainActor
    static func efforts(
        for selection: AIModelSelection?, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager
    ) -> [ChatGPTSubscription.Effort] {
        guard let selection else { return [] }
        let model = selection.model
        switch selection.source {
        case .appleIntelligence:
            return []
        case .codex:
            return subscription.models.first { $0.id == model }?.efforts ?? []
        case .claude, .grok, .openCode, .cursor:
            return installedAI.models(for: selection.source).first { $0.id == model }?.efforts ?? []
        case .api(let connection):
            return settings.connection(id: connection)?.reasoningOptions(for: model)?
                .efforts.map { ChatGPTSubscription.Effort(id: $0, detail: nil) } ?? []
        }
    }

    var id: AIModelSelection { selection }
    func matches(_ other: AIModelSelection) -> Bool {
        selection.source == other.source && selection.model == other.model
    }
}

/// 一组同来源的模型选项（如 Codex、Claude、某个 API 连接）。
struct AIModelOptionGroup: Identifiable {
    let source: AIModelSource
    let title: String
    var options: [AIModelOption]
    var id: AIModelSource { source }
}
