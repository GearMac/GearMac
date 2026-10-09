// 文件职责：承载快捷动作的用户设置（预览选择、目标语言、内置指令覆盖）及其规范化存取。
// 分层：Model；设置值可安全序列化到 UserDefaults，不依赖 AppKit/SwiftUI。
import Foundation

struct QuickActionSettings: Equatable, Sendable {
    /// 只记录用户真正选过的项：未出现的动作取默认值，以便默认值以后可以调整。
    var previewChoices: [BuiltInQuickAction: Bool] = [:]

    /// BCP-47 语言标识，例如 `es-419`。空串表示使用 Mac 自身语言。
    var targetLanguage: String = ""
    /// 内置动作的自定义指令覆盖，仅允许非翻译类动作写入。
    private(set) var instructionOverrides: [BuiltInQuickAction: String] = [:]

    /// 统一动作的“是否先预览结果”查询。
    func previewsResult(_ action: QuickAction) -> Bool {
        switch action {
        case .builtIn(let builtIn): return previewsResult(builtIn)
        case .custom(let custom): return custom.previewsResult
        }
    }

    /// 内置动作的预览选择：始终预览的直接为 true，否则取用户选择，再回退到默认。
    func previewsResult(_ action: BuiltInQuickAction) -> Bool {
        if action.alwaysPreviews { return true }
        return previewChoices[action] ?? !action.replacesDirectlyByDefault
    }

    /// 记录用户对某内置动作的预览选择；始终预览的动作忽略此设置。
    mutating func setPreviewsResult(_ previews: Bool, for action: BuiltInQuickAction) {
        guard !action.alwaysPreviews else { return }
        previewChoices[action] = previews
    }

    /// 取某统一动作的指令覆盖（仅内置动作有效）。
    func instructionOverride(for action: QuickAction) -> String? {
        action.builtInAction.flatMap(instructionOverride)
    }

    /// 取某内置动作的指令覆盖。
    func instructionOverride(for action: BuiltInQuickAction) -> String? {
        instructionOverrides[action]
    }

    /// 设置某内置动作的指令覆盖；翻译类动作不支持覆盖，直接忽略。
    mutating func setInstructionOverride(_ instructions: String?, for action: BuiltInQuickAction) {
        guard !action.usesTranslationFramework else { return }
        instructionOverrides[action] = instructions
    }

    /// 通过 `UserDefaults` 往返序列化；未知 key 表示该动作已不存在。
    var storedPreviewChoices: [String: Bool] {
        get { Dictionary(uniqueKeysWithValues: previewChoices.map { ($0.rawValue, $1) }) }
        set {
            previewChoices = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    BuiltInQuickAction(rawValue: key).map { ($0, value) }
                })
        }
    }

    /// 指令覆盖的 UserDefaults 往返形式，同时过滤掉已失效或翻译类的动作。
    var storedInstructionOverrides: [String: String] {
        get { Dictionary(uniqueKeysWithValues: instructionOverrides.map { ($0.rawValue, $1) }) }
        set {
            instructionOverrides = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    guard let action = BuiltInQuickAction(rawValue: key),
                        !action.usesTranslationFramework
                    else { return nil }
                    return (action, value)
                })
        }
    }
}
