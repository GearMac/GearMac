// 文件职责：备份面板与引导流程共用的备份类别多选框，按文件实际包含的类别展示并支持全选/取消全选。
// 分层：UI；纯展示与选择状态绑定，不执行导出/导入副作用。
import SwiftUI

/// 与 `RaycastImportSelection` 并列的实现，而非其泛化：只有本视图会把文件中缺失的类别置灰。
struct BackupCategorySelection: View {
    @Binding var selection: Set<BackupCategory>
    /// 文件实际包含的类别及各自数量；nil 表示提供全部类别。
    var available: [BackupCategory: Int]?

    @Environment(AppSettings.self) private var settings

    /// 两列弹性网格的列定义，供选项下拉排列。
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 2)

    /// 需要展示的类别：有 available 时只列出其中确实存在的类别。
    private var offered: [BackupCategory] {
        guard let available else { return BackupCategory.allCases }
        return BackupCategory.allCases.filter { available[$0] != nil }
    }

    /// 把某个类别映射为勾选状态的双向绑定，供 Toggle 使用。
    private func included(_ category: BackupCategory) -> Binding<Bool> {
        Binding(
            get: { selection.contains(category) },
            set: { isOn in
                if isOn { selection.insert(category) } else { selection.remove(category) }
            })
    }

    /// 类别的副标题（如「12 items」）；缺少量词或数量时返回 nil。
    private func subtitle(_ category: BackupCategory) -> String? {
        guard let noun = category.descriptor.countNoun(settings.language),
            let count = available?[category]
        else {
            return nil
        }
        return String(format: settings.text(BackupKey.categoryCount), count, noun)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(offered) { category in
                    Toggle(isOn: included(category)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: category.descriptor.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(category.descriptor.label(settings.language)).lineLimit(1)
                            if let subtitle = subtitle(category) {
                                Text(subtitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(
                selection.isEmpty
                    ? settings.text(BackupKey.selectAll) : settings.text(BackupKey.deselectAll)
            ) {
                selection = selection.isEmpty ? Set(offered) : []
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
