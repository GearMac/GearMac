// 文件职责：计算器历史列表视图：按日期分段渲染历史记录，并在列表顶部展示当前搜索内容对应的答案卡片。
// 分层：UI（SwiftUI）；@MainActor 视图，行索引 0 恒为答案卡片。
import SwiftUI

/// 历史计算列表，形态与 `ClipboardList` 相似；每行两侧都有内容，因此不需要预览面板。
struct CalculatorHistoryList: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let results: [CalcHistoryEntry]
    let selectedID: CalcHistoryEntry.ID?
    /// 仅在应当滚动时才变化，避免鼠标选中时列表位置被抽动。
    let scroll: ScrollIntent
    /// 历史搜索框中实时输入的答案；与启动器一样采用平铺索引 0 的约定。
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onSelect: (CalcHistoryEntry) -> Void
    let onActivate: () -> Void
    let onActions: (CalcHistoryEntry) -> Void

    private nonisolated static let calcRowID = "calc-card"

    /// 列表行：分段标题、答案卡片或历史条目。
    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case entry(CalcHistoryEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return CalculatorHistoryList.calcRowID
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    /// 当前选中项对应的滚动目标行 id。
    private var selectedRowID: String? {
        calcSelected ? Self.calcRowID : selectedID?.uuidString
    }

    /// 选中是否位于平铺索引 0：有卡片时为卡片，否则为第一条历史。
    private var firstRowSelected: Bool {
        calc != nil ? calcSelected : selectedID != nil && selectedID == results.first?.id
    }

    /// 最新的在最前，因此每当日期分段变化时就插入一个标题行。
    private var rows: [Row] {
        var rows: [Row] = []
        if let calc {
            rows = [.header(settings.text(CalculatorKey.sectionCalculator)), .calc(calc)]
        }
        var currentBucket: DateBucket?
        for entry in results {
            let bucket = DateBucket(for: entry.createdAt)
            if bucket != currentBucket {
                rows.append(.header(bucket.localizedTitle(settings.language)))
                currentBucket = bucket
            }
            rows.append(.entry(entry))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .calc(let result):
                            CalculatorCard(result: result, selected: calcSelected)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onActivateCalc)
                                .onRightClick(perform: onCalcActions)
                                .padding(.bottom, metrics.spacing.xs)
                                .selectionFrame(calcSelected)
                        case .entry(let entry):
                            CalcHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .selectionFrame(entry.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(entry) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(entry)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(entry) }
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // 第一行时也把滚动位置对齐到顶端，让它的分段标题一并可见。
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// 单条历史记录的行视图：显示表达式与结果，并随选中/悬停状态变化背景。
private struct CalcHistoryRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppCore.self) private var core
    let entry: CalcHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var format: CalcNumberFormat { core.calcNumberFormat }

    /// 行的背景色：选中时用选中色，悬停时用悬停色，否则透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: "plus.forwardslash.minus")).resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(format.localizedExpression(entry.expression))
                .font(metrics.typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: metrics.spacing.xl)
            Text(format.localized(entry.result))
                .font(metrics.typography.rowTitle.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
