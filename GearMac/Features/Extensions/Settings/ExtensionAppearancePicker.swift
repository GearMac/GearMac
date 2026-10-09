// 文件职责：扩展启动器图标的换肤选择器：色板加可搜索的图标网格，选择后立即生效。
// 分层：UI（SwiftUI 视图）；只负责展示与回调，不持有扩展数据。
import SwiftUI

/// 色板加可搜索的图标网格。选择立即生效：真正的预览就是启动器本身。
struct ExtensionAppearancePicker: View {
    let current: ExtensionAppearance
    /// 是否已被换肤；只有换过肤时「重置」才有意义。
    let isCustom: Bool
    let onPick: (ExtensionAppearance) -> Void
    let onReset: () -> Void

    /// 先使用精选集合：约 700 KB 的 plist 会让弹出面板首帧卡顿。
    @State private var catalog = SymbolCatalog.fallback
    @State private var category = SymbolCategory.suggested
    @State private var query = ""

    /// 网格统一的一套列尺寸，让每一行共享同一组边距，而不是各自计算。
    private enum Metrics {
        static let tile: CGFloat = 30
        static let columns = 10
        static let gap: CGFloat = 8
        static let inset: CGFloat = Theme.Spacing.xl
        static let swatchesPerRow = 9
        static let swatch: CGFloat = 20
        /// 完整显示的行数，再多露出下一行的半个格子，作为有意的可滚动提示。
        static let visibleRows = 6

        /// 网格内容区宽度：列数 × 格子宽加列间距。
        static var contentWidth: CGFloat {
            CGFloat(columns) * tile + CGFloat(columns - 1) * gap
        }
        /// 弹出面板宽度：内容宽度加上两侧内边距。
        static var popoverWidth: CGFloat { contentWidth + inset * 2 }
        /// 网格可视高度：按可见行数计算，并额外留出半格作为滚动提示。
        static var gridHeight: CGFloat {
            CGFloat(visibleRows) * (tile + gap) - gap + tile / 2
        }
        /// 色块在相同宽度上均分，使第一个和最后一个色块正好落在网格两侧边缘。
        static var swatchGap: CGFloat {
            (contentWidth - CGFloat(swatchesPerRow) * swatch) / CGFloat(swatchesPerRow - 1)
        }
    }

    /// 色板网格的列定义：固定尺寸的色块列。
    private let swatches = Array(
        repeating: GridItem(.fixed(Metrics.swatch), spacing: Metrics.swatchGap),
        count: Metrics.swatchesPerRow)
    /// 图标网格的列定义：固定尺寸的图标列。
    private let icons = Array(
        repeating: GridItem(.fixed(Metrics.tile), spacing: Metrics.gap), count: Metrics.columns)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: swatches, alignment: .leading, spacing: Metrics.gap) {
                ForEach(ExtensionTint.allCases) { tint in
                    Button {
                        onPick(ExtensionAppearance(symbol: current.symbol, tint: tint))
                    } label: {
                        Circle()
                            .fill(tint.color.gradient)
                            .frame(width: Metrics.swatch, height: Metrics.swatch)
                            .overlay(
                                Circle().strokeBorder(
                                    .white.opacity(tint == current.tint ? 0.9 : 0), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tint.title)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("Search symbols…"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .pointerStyle(.horizontalText)
                Picker("", selection: $category) {
                    ForEach(catalog.categories) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            let results = catalog.search(query, in: category)
            if results.isEmpty {
                Text("No symbols match \u{201C}\(query)\u{201D}.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // 保持整行：只显示半行并被底部裁切，看起来像渲染错误。
                    .frame(width: Metrics.contentWidth, height: Metrics.gridHeight)
            } else {
                ScrollView {
                    // 前导对齐：否则固定列数的 `LazyVGrid` 会在多余宽度里居中自己。
                    LazyVGrid(columns: icons, alignment: .leading, spacing: Metrics.gap) {
                        ForEach(results, id: \.self) { symbol in
                            Button {
                                onPick(ExtensionAppearance(symbol: symbol, tint: current.tint))
                            } label: {
                                SymbolTile(symbol: symbol, tint: current.tint, side: Metrics.tile)
                                    .opacity(symbol == current.symbol ? 1 : 0.55)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                .white.opacity(symbol == current.symbol ? 0.9 : 0),
                                                lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                        }
                    }
                    .frame(width: Metrics.contentWidth, alignment: .leading)
                    .hideNativeScrollers()
                }
                .overflowFade()
                .thinScrollbar()
                // 用列的宽度而非弹出面板的宽度，否则网格会越过共享的内边距。
                .frame(width: Metrics.contentWidth, height: Metrics.gridHeight)
            }

            HStack {
                Text(footnote(results.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use Original Icon", action: onReset)
                    .disabled(!isCustom)
                    .help("Go back to the icon the extension ships.")
            }
        }
        .padding(Metrics.inset)
        .frame(width: Metrics.popoverWidth)
        .task {
            // 只有兜底目录只有一个分类；此时不必重复读取真实目录。
            guard catalog.categories.count == 1 else { return }
            catalog = await Task.detached(priority: .userInitiated) { SymbolCatalog.load() }.value
        }
    }

    /// 底部统计文案：按当前是否有关键词与当前分类拼出计数说明。
    private func footnote(_ count: Int) -> String {
        let noun = count == 1 ? "symbol" : "symbols"
        return query.isEmpty ? "\(count) \(noun) in \(category.title)" : "\(count) \(noun) matching"
    }
}

/// 用 SwiftUI 绘制，使选择器预览的效果与 `IconCache` 渲染的完全一致。
struct SymbolTile: View {
    let symbol: String
    let tint: ExtensionTint
    let side: CGFloat

    /// 扩展自带的图标：系统没有对应的 SF Symbol，它们以 template 方式绘制，因此能像符号一样着色。
    @ViewBuilder
    private var glyph: some View {
        if SymbolCatalog.isBundled(symbol) {
            Image(symbol)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side * 0.5, height: side * 0.5)
                .foregroundStyle(.white)
        } else {
            Image(systemName: symbol)
                .font(.system(size: side * 0.46, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
            .fill(tint.color)
            .frame(width: side, height: side)
            .overlay(glyph)
    }
}
