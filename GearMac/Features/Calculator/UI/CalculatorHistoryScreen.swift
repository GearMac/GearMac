// 文件职责：计算器历史面板（PaletteScreen）：以当前搜索框内容实时求得的答案卡片为首行，下方列出可筛选的历史记录，并处理选中、复制、删除等快捷键。
// 分层：UI；@MainActor，平铺选择索引与 `rows` 一一对应，卡片占索引 0。
import SwiftUI

/// 过去的历史计算，顶部是搜索框当前输入实时求得的答案卡片。
struct CalculatorHistoryScreen: PaletteScreen {
    let history: CalculatorHistoryStore
    let currencyRates: CurrencyRateStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// 卡片与普通行一样占一个位置，所以平铺选择索引直接对应 `rows`，无需偏移。
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case entry(CalcHistoryEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    private var format: CalcNumberFormat { core.calcNumberFormat }
    private var calc: CalcResult? {
        CalcMemo.evaluate(
            vm.query, rates: currencyRates.rates, format: format,
            language: core.settings.language)
    }
    /// 历史以规范形式存储，因此本地化的查询串也要按同样写法去搜索。
    private var entries: [CalcHistoryEntry] { history.search(format.canonical(vm.query) ?? vm.query) }

    /// 供选择与渲染使用的完整行列表：答案卡片（若可计算）+ 各条历史记录。
    var rows: [Row] {
        let entries = entries.map(Row.entry)
        guard let calc else { return entries }
        return [.calc(calc)] + entries
    }

    /// 回车主操作按钮的标题。
    var primaryActionTitle: String { core.settings.text(CalculatorKey.copyAnswer) }

    /// 取指定平铺索引对应的行，越界时返回 nil。
    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 取指定索引处的历史记录，若该位置不是历史行则返回 nil。
    private func entry(at selection: Int) -> CalcHistoryEntry? {
        guard case .entry(let entry) = row(at: selection) else { return nil }
        return entry
    }

    /// 指定索引是否落在答案卡片上。
    private func isCardSelected(_ selection: Int) -> Bool {
        if case .calc = row(at: selection) { return true }
        return false
    }

    /// 错误卡片可选但不可复制，因此它既不驱动底部提示也不影响 ⌘K。
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    /// 返回指定索引行的操作菜单内容：卡片用 CalcActionsMenu，历史行用 CalcHistoryActionsMenu。
    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .entry(let entry):
            return CalcHistoryActionsMenu.content(entry: entry, core: core, calcHistory: history)
        case nil:
            return nil
        }
    }

    /// 双击/回车激活指定行：卡片复制并记录，历史行重新复制答案。
    func activate(at selection: Int) {
        switch row(at: selection) {
        // 新计算：与启动器卡片一致地复制并记录；错误卡片不做任何事。
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .entry(let entry): core.calculatorCoordinator.copyHistoryEntry(entry)
        case nil: break
        }
    }

    /// ⌘↵：内联卡片的答案转为查询；已存历史条目则复制其表达式。
    func secondary(at selection: Int) -> Bool {
        if case .calc(let result) = row(at: selection) {
            return core.calculatorCoordinator.putAnswerInSearchBar(result)
        }
        guard let entry = entry(at: selection) else { return false }
        core.calculatorCoordinator.copyHistoryExpression(entry)
        return true
    }

    /// 处理本屏特有的快捷键：删除单条、清空全部、复制完整算式。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            delete(at: selection)
            return true
        case .deleteAll:
            deleteAll()
            return true
        case .copyCalculation:
            guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
            core.calculatorCoordinator.copyCalculationWithExpression(result)
            return true
        default: return false
        }
    }

    /// ⌘⌫ / ⌃X —— 本屏处理该快捷键，但内联卡片不可删除。
    private func delete(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        history.remove(entry)
    }

    /// ⌃⇧X —— 与 Actions 菜单行为一致，含确认弹窗；实时内联卡片不属于历史。
    private func deleteAll() {
        Task { await core.calculatorCoordinator.deleteAllHistory() }
    }

    /// 构建本屏内容视图并抹除具体类型返回。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? core.settings.text(CalculatorKey.emptyNoCalculations)
                    : core.settings.text(CalculatorKey.emptyNoMatches))
        } else {
            CalculatorHistoryList(
                results: entries,
                selectedID: entry(at: selection)?.id,
                scroll: scroll,
                calc: calc,
                calcSelected: isCardSelected(selection),
                onActivateCalc: {
                    vm.selection = 0
                    activate(at: 0)
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onSelect: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                    openActions()
                }
            )
        }
    }
}

/// 计算器历史条目的操作菜单内容，与其他模式一样在右下角弹出。
@MainActor
enum CalcHistoryActionsMenu {
    /// 构造历史条目的操作菜单：复制答案/表达式、删除单条、清空全部。
    static func content(
        entry: CalcHistoryEntry, core: AppCore, calcHistory: CalculatorHistoryStore
    )
        -> PopoverMenuContent
    {
        PopoverMenuContent(
            header: core.calcNumberFormat.localizedExpression(entry.expression),
            items: [
                PopoverMenuItem(
                    title: core.settings.text(CalculatorKey.copyAnswer),
                    systemImage: "doc.on.doc", shortcut: "↵"
                ) {
                    core.calculatorCoordinator.copyHistoryEntry(entry)
                },
                PopoverMenuItem(
                    title: core.settings.text(CalculatorKey.copyExpression),
                    systemImage: "doc.on.doc.fill", shortcut: "⌘↵"
                ) {
                    core.calculatorCoordinator.copyHistoryExpression(entry)
                },
                PopoverMenuItem(
                    title: core.settings.text(CalculatorKey.deleteEntry), systemImage: "trash",
                    startsSection: true, shortcut: "⌃X", isDestructive: true
                ) {
                    calcHistory.remove(entry)
                },
                PopoverMenuItem(
                    title: core.settings.text(CalculatorKey.deleteAllEntries), systemImage: "trash",
                    shortcut: "⌃⇧X", isDestructive: true
                ) {
                    Task { await core.calculatorCoordinator.deleteAllHistory() }
                }
            ]
        )
    }
}
