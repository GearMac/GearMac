// 文件职责：通过 UserDefaults 持久化快捷动作的设置与模型路由，并提供模型可用性修复。
// 分层：Settings；与 `AISettingsStore` 并列，拥有自己的开关、模型路由与设置面板。
import Foundation
import Observation

/// 与 `AISettingsStore` 独立：它是 chat 的同级，有自己的开关、路由和设置面板。
@MainActor
@Observable
final class QuickActionSettingsStore {
    private let defaults: UserDefaults

    var settings: QuickActionSettings {
        didSet { persistSettings() }
    }
    /// 修语法触发的频率远高于 chat 轮次，因此默认不按次计费。
    private(set) var model: AIModelSelection? {
        didSet { persistModel() }
    }
    /// 以 `QuickAction.id` 为键；没有条目的动作跟随 `model`。
    private(set) var modelOverrides: [String: AIModelSelection] {
        didSet { persistModelOverrides() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = QuickActionSettings()
        loaded.storedPreviewChoices =
            defaults.dictionary(forKey: AppSettingsKey.quickActionPreviews.rawValue)
            as? [String: Bool] ?? [:]
        loaded.targetLanguage =
            defaults.string(forKey: AppSettingsKey.quickActionLanguage.rawValue) ?? ""
        loaded.storedInstructionOverrides =
            defaults.dictionary(forKey: AppSettingsKey.quickActionInstructions.rawValue)
            as? [String: String] ?? [:]
        settings = loaded
        model = Self.decode(
            AIModelSelection.self,
            from: defaults.data(forKey: AppSettingsKey.quickActionModel.rawValue))
        modelOverrides =
            Self.decode(
                [String: AIModelSelection].self,
                from: defaults.data(forKey: AppSettingsKey.quickActionModelOverrides.rawValue))
            ?? [:]
    }

    func select(_ selection: AIModelSelection?) {
        model = selection
    }

    /// 取某动作生效的模型：优先自身覆盖，否则用全局 `model`。
    func model(for action: QuickAction) -> AIModelSelection? {
        modelOverride(for: action) ?? model
    }

    /// 取某动作的模型覆盖；未设置则为 nil。
    func modelOverride(for action: QuickAction) -> AIModelSelection? {
        modelOverrides[action.id]
    }

    /// 设置某动作的模型覆盖；翻译类动作不支持覆盖。
    func setModelOverride(_ selection: AIModelSelection?, for action: QuickAction) {
        guard !action.usesTranslationFramework, modelOverrides[action.id] != selection else { return }
        modelOverrides[action.id] = selection
    }

    /// 未选择时回退到无需账号的路由，与 chat 自身默认值的解析方式一致。
    func resolveModel(appleIntelligenceAvailable: Bool, fallback: AIModelSelection?) {
        guard model == nil else { return }
        model = appleIntelligenceAvailable ? .appleIntelligence : fallback
    }

    /// 被删除的连接不得留下一个无人应答的路由。
    func repairModel(against connections: [AIConnection], fallback: AIModelSelection?) {
        if let model, !Self.reaches(model, through: connections) {
            self.model = fallback
        }
        updateOverrides { Self.reaches($0, through: connections) ? $0 : nil }
    }

    /// 失效的覆盖直接丢弃而非重定向，使其动作重新跟随 `model`。
    func repairInstalledModel(
        available: [AIModelSelection], unavailableSources: Set<AIModelSource>,
        fallback: AIModelSelection?
    ) {
        if let model {
            let repaired = Self.repaired(
                model, available: available, unavailableSources: unavailableSources,
                fallback: fallback)
            if repaired != model { self.model = repaired }
        }
        updateOverrides {
            Self.repaired(
                $0, available: available, unavailableSources: unavailableSources, fallback: nil)
        }
    }

    /// 按变换函数批量修正覆盖项，仅在结果变化时写回。
    private func updateOverrides(_ transform: (AIModelSelection) -> AIModelSelection?) {
        let updated = modelOverrides.compactMapValues(transform)
        if updated != modelOverrides { modelOverrides = updated }
    }

    /// 判断某选择是否仍能通过现有连接得到响应（非 API 路由总是可达）。
    private static func reaches(
        _ selection: AIModelSelection, through connections: [AIConnection]
    ) -> Bool {
        guard case .api(let id, let name, _) = selection else { return true }
        return connections.contains { $0.id == id && $0.models.contains(name) }
    }

    /// 计算修正后的模型选择：源可用则保留或换用同源可用模型，否则必要时回退或置空。
    private static func repaired(
        _ selection: AIModelSelection, available: [AIModelSelection],
        unavailableSources: Set<AIModelSource>, fallback: AIModelSelection?
    ) -> AIModelSelection? {
        guard selection.source.installedKind != nil else { return selection }
        let sourceModels = available.filter { $0.source == selection.source }
        if sourceModels.contains(where: { $0.model == selection.model }) { return selection }
        if let replacement = sourceModels.first { return replacement }
        guard unavailableSources.contains(selection.source) else { return selection }
        guard let fallback, !unavailableSources.contains(fallback.source), fallback != selection
        else { return nil }
        return fallback
    }

    /// 将设置的规范化序列化形式写入 UserDefaults。
    private func persistSettings() {
        defaults.set(
            settings.storedPreviewChoices, forKey: AppSettingsKey.quickActionPreviews.rawValue)
        defaults.set(settings.targetLanguage, forKey: AppSettingsKey.quickActionLanguage.rawValue)
        defaults.set(
            settings.storedInstructionOverrides,
            forKey: AppSettingsKey.quickActionInstructions.rawValue)
    }

    private func persistModel() {
        persist(model, forKey: .quickActionModel)
    }

    private func persistModelOverrides() {
        persist(modelOverrides.isEmpty ? nil : modelOverrides, forKey: .quickActionModelOverrides)
    }

    /// 编码并写入某个键；值为空或编码失败时则移除该键。
    private func persist(_ value: (some Encodable)?, forKey key: AppSettingsKey) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    /// 从 JSON Data 解码出指定类型，数据为空或解码失败时返回 nil。
    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
