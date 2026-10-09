// 文件职责：计算器结果的复制与再输入编排：把内联卡片的计算写入历史、复制答案或完整算式，以及清空历史前的确认。
// 分层：Coordinator；@MainActor，历史只记录规范形式的答案，仅进入剪贴板的内容才本地化。
import AppKit

/// 负责把计算复制出去的逻辑：内联卡片会记录历史，历史行则从不重复记录。
@MainActor
final class CalculatorCoordinator {
    private let calcHistory: CalculatorHistoryStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        calcHistory: CalculatorHistoryStore, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.calcHistory = calcHistory
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// ⌃⇧X 快捷键与菜单行都汇入此处，确保两者都无法跳过确认。
    func deleteAllHistory() async {
        guard
            await core.confirm(
                title: core.settings.text(CalculatorKey.clearHistoryTitle),
                message: core.settings.text(CalculatorKey.clearHistoryMessage),
                symbol: PaletteMode.calculatorHistory.systemImage,
                confirmTitle: core.settings.text(CalculatorKey.clearHistoryConfirm))
        else { return }
        calcHistory.clearAll()
    }

    /// 历史记录保存规范形式的答案；只有进入剪贴板的内容才本地化。
    private var format: CalcNumberFormat { core.calcNumberFormat }

    /// 在内联计算器卡片上按 Enter：复制答案、记住计算并关闭面板。
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localized(copyText))
    }

    /// 卡片上的 `⌘↵`：答案成为新的查询，供下一步链式计算继续。
    @discardableResult
    func putAnswerInSearchBar(_ result: CalcResult) -> Bool {
        guard case .value(let display, let copyText) = result.payload, result.canChain,
            !core.palette.isComposing
        else { return false }
        calcHistory.record(expression: result.expression, result: display)
        core.palette.rewriteQuery(format.localized(copyText))
        return true
    }

    /// 卡片上的 `⇧⌘↵`：复制完整算式，便于粘贴到笔记或消息中。
    func copyCalculationWithExpression(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        paletteCoordinator.hidePalette(restoreFocus: false)
        let format = format
        Paster.copyPlainText(
            "\(format.localizedExpression(result.expression)) = \(format.localized(copyText))")
    }

    /// 在 Calculator History 行上按 Enter：重新复制已存答案（不再重复记录）。
    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localized(entry.copyText))
    }

    /// 复制历史记录中的表达式本身（不含结果）。
    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.localizedExpression(entry.expression))
    }
}
