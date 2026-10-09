// 文件职责：窗口快捷键预设协调器，负责匹配当前绑定、确认覆盖用户自定义快捷键并将预设写入热键管理器。
// 分层：Coordinator；@MainActor，绑定状态从 HotKeyManager 实时读取，不缓存。
import Foundation

/// 填充预设；仅当会覆盖用户已设置的快捷键时才先行询问。
@MainActor
final class WindowShortcutPresetCoordinator {
    private let hotKeys: HotKeyManager
    /// 仅用于对话框与 HUD 展示；该类不持有它的任何状态。
    private unowned let core: AppCore

    init(hotKeys: HotKeyManager, core: AppCore) {
        self.hotKeys = hotKeys
        self.core = core
    }

    /// 从当前实际绑定读取，因此任何破坏匹配的编辑都会使其清空。
    var matchingPreset: WindowShortcutPreset? {
        WindowShortcutPreset.matching(currentBindings())
    }

    /// 应用预设：必要时先确认覆盖，先清空再逐项写入，并处理按键冲突与回退。
    func apply(_ preset: WindowShortcutPreset) async {
        var current = currentBindings()
        var plan = WindowShortcutPresetPlan(preset: preset, current: current)
        guard !plan.assignments.isEmpty else {
            core.showMessage(
                String(
                    format: core.settings.text(WindowKey.presetAlreadySet),
                    preset.localizedTitle(core.settings.resolvedLanguage)))
            return
        }
        if !plan.overwritten.isEmpty {
            let confirmed = Set(plan.overwritten)
            guard
                await core.confirm(
                    title: plan.overwritten.count == 1
                        ? core.settings.text(WindowKey.presetReplaceOne)
                        : String(
                            format: core.settings.text(WindowKey.presetReplaceMany),
                            plan.overwritten.count),
                    message: replacementMessage(plan.overwritten, preset: preset),
                    symbol: "keyboard",
                    confirmTitle: core.settings.text(WindowKey.presetReplaceConfirm))
            else { return }
            // 对话框等待期间 settings.json 重载可能重新绑定；绝不替换未看到的按键。
            current = currentBindings()
            plan = WindowShortcutPresetPlan(preset: preset, current: current)
            guard Set(plan.overwritten).isSubset(of: confirmed) else { return await apply(preset) }
        }
        // 先清空再设置，使在两个命令之间迁移的按键不会阻塞自己。
        for id in plan.displaced + plan.assignments.keys where current[id] != nil {
            hotKeys.setBinding(nil, for: .windowCommand(id: id))
        }
        var skipped: [WindowCommand.ID] = []
        for id in WindowCommand.ID.allCases {
            guard let binding = plan.assignments[id] else { continue }
            let action = HotKeyAction.windowCommand(id: id)
            guard hotKeys.conflictOwner(of: binding, excluding: action) == nil else {
                skipped.append(id)
                continue
            }
            hotKeys.setBinding(binding, for: action)
        }
        // 旧绑定在仍空闲时恢复，避免冲突导致可用快捷键丢失。
        for id in skipped {
            let action = HotKeyAction.windowCommand(id: id)
            if let previous = current[id],
                hotKeys.conflictOwner(of: previous, excluding: action) == nil
            {
                hotKeys.setBinding(previous, for: action)
            }
        }
        if skipped.isEmpty {
            core.showMessage(
                String(
                    format: core.settings.text(WindowKey.presetApplied),
                    preset.localizedTitle(core.settings.resolvedLanguage)))
        } else {
            core.showMessage(
                String(
                    format: core.settings.text(WindowKey.presetAppliedSkipped),
                    preset.localizedTitle(core.settings.resolvedLanguage), skipped.count),
                tone: .danger)
        }
    }

    /// 读取所有窗口命令当前的快捷键绑定。
    private func currentBindings() -> [WindowCommand.ID: HotKeyBinding] {
        var current: [WindowCommand.ID: HotKeyBinding] = [:]
        for id in WindowCommand.ID.allCases {
            current[id] = hotKeys.binding(for: .windowCommand(id: id))
        }
        return current
    }

    /// 生成覆盖确认的提示文案：列出最多 3 个命令名及其余数量。
    private func replacementMessage(
        _ ids: [WindowCommand.ID], preset: WindowShortcutPreset
    ) -> String {
        let language = core.settings.resolvedLanguage
        let names = ids.map { $0.localizedTitle(language) }
        let listed = names.prefix(3).joined(separator: ", ")
        let rest = names.count > 3
            ? String(format: core.settings.text(WindowKey.presetMore), names.count - 3)
            : ""
        return String(
            format: core.settings.text(WindowKey.presetReplacementMessage), listed, rest,
            preset.localizedTitle(language))
    }
}
