// 文件职责：提供 SF Symbols 图标选择网格（含 Automatic 选项行），供设置界面挑选图标。
// 分层：UI（DesignSystem）；可选符号列表由调用方提供，组件只把选择结果写回 Binding 并触发 onPick。
import SwiftUI

/// SF Symbols 选择网格，并提供 Automatic 兜底选项；可选符号由调用方给出。
struct SymbolPicker: View {
    @Binding var selection: String?
    /// 绘制在 Automatic 行上；未选择任何符号时该行也回退显示此图标。
    let fallback: String
    let symbols: [String]
    let onPick: () -> Void

    private static let cell: CGFloat = 30
    private static let cellHeight: CGFloat = 26
    private static let columnCount = 6

    /// 固定列宽的网格列定义，列数为 `columnCount`。
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cell), spacing: Theme.Spacing.sm), count: Self.columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                selection = nil
                onPick()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: fallback, size: 14)
                    Text("Automatic")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        onPick()
                    } label: {
                        SymbolImage(name: symbol, size: 15)
                            .frame(width: Self.cell, height: Self.cellHeight)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                                    .fill(selection == symbol ? Theme.Colors.selection : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: Self.width)
    }

    private static let width: CGFloat = 244
}
