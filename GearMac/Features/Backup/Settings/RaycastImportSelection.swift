// 文件职责：Raycast 导入的类别多选框，供备份面板与引导流程共用。
// 分层：UI；仅负责选项展示与选择绑定，不执行解密/导入。
import SwiftUI

/// 备份面板与引导流程共用的类别选择器。
struct RaycastImportSelection: View {
    @Binding var selection: RaycastImportOptions

    @Environment(AppSettings.self) private var settings

    /// 一个可选类别：对应的导入选项、图标与显示名称键。
    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let symbol: String
        let labelKey: BackupKey
        var id: Int { option.rawValue }
    }

    /// 可选类别列表，顺序即界面展示顺序。
    private static let categories: [Category] = [
        .init(option: .shortcuts, symbol: "command", labelKey: .optionShortcuts),
        .init(option: .favorites, symbol: "star", labelKey: .optionFavorites),
        .init(option: .aliases, symbol: "character.cursor.ibeam", labelKey: .optionAliases),
        .init(option: .emojiSkinTone, symbol: "face.smiling", labelKey: .optionEmojiSkinTone),
        .init(option: .launchAtLogin, symbol: "power", labelKey: .optionLaunchAtLogin),
        .init(option: .menuBarVisibility, symbol: "menubar.rectangle", labelKey: .optionMenuBarIcon),
        .init(
            option: .clipboardHistory, symbol: "doc.on.clipboard",
            labelKey: .optionClipboardHistory),
        .init(option: .snippets, symbol: "curlybraces", labelKey: .optionSnippets),
        .init(option: .quicklinks, symbol: Quicklink.sfSymbol, labelKey: .optionQuicklinks),
        .init(option: .popToRoot, symbol: "arrow.uturn.backward", labelKey: .optionPopToRoot),
        .init(option: .compactMode, symbol: "macwindow", labelKey: .optionCompactMode),
    ]

    /// 三列弹性网格的列定义。
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 3)

    /// 把某个选项映射为勾选状态的双向绑定。
    private func included(_ option: RaycastImportOptions) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selection = $0 ? selection.union(option) : selection.subtracting(option) })
    }

    /// 选择器主体：网格列出全部选项，底部为全选/取消全选。
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Self.categories) { category in
                    Toggle(isOn: included(category.option)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: category.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(settings.text(category.labelKey)).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(
                selection == .all
                    ? settings.text(BackupKey.deselectAll) : settings.text(BackupKey.selectAll)
            ) {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
