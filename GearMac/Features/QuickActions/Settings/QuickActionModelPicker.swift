// 文件职责：为单个快捷动作挑选独立的模型与推理强度（保存前暂存于编辑面板）。
// 分层：UI；仅在 Save 时回写，面板自身不持久化。
import SwiftUI

/// 单个动作自己的模型路由，由展示它的编辑面板暂存直到 Save。
struct QuickActionModelPicker: View {
    @Binding var selection: AIModelSelection?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(settings.text(QuickActionsKey.modelLabel))
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.lg) {
                AIModelSelectionRows(
                    selection: selection,
                    inheritedTitle: settings.text(QuickActionsKey.modelInherited),
                    select: { selection = $0 },
                    modelLabel: { Text(settings.text(QuickActionsKey.modelLabel)) },
                    effortLabel: { Text(settings.text(QuickActionsKey.modelEffort)) })
            }
            .labelsHidden()
        }
    }
}
