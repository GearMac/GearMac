// 文件职责：计算器内联答案卡片的渲染与交互：展示表达式与结果、高亮连接词，并提供复制答案、把答案置入搜索框等操作菜单。
// 分层：UI（SwiftUI）；@MainActor，所有展示值都经当前数字格式本地化后再渲染。
import SwiftUI

extension AppCore {
    /// 同时读取两个 observables，使设置或地区格式变更时重建所有计算器界面。
    var calcNumberFormat: CalcNumberFormat { regionNumberFormat.format(for: settings.calcNumberStyle) }
}

/// 对 `CalcEngine.evaluate` 的深度为 1 的备忘，以汇率快照的 `fetchedAt` 作为键。
@MainActor
enum CalcMemo {
    /// 缓存的一项，记录键与实际的计算结果。
    private struct Cache {
        let query: String
        let stamp: Date?
        let region: String?
        let format: CalcNumberFormat
        /// 语言也是键的一部分：徽章与错误文字随语言变化。
        let language: AppLanguage
        let result: CalcResult?
    }

    private static var cache: Cache?

    /// 结果始终保持规范形式，使历史记录无论格式如何变化都只存一种写法。
    static func evaluate(
        _ query: String, rates: CurrencyRates?, format: CalcNumberFormat,
        language: AppLanguage = .english
    ) -> CalcResult? {
        let region = RegionCurrency.code
        if let cache, cache.query == query, cache.stamp == rates?.fetchedAt, cache.region == region,
            cache.format == format, cache.language == language
        {
            return cache.result
        }
        let result = CalcEngine.evaluate(
            query, now: Date(), calendar: .current, rates: rates, region: region, format: format,
            language: language)
        cache = Cache(
            query: query, stamp: rates?.fetchedAt, region: region, format: format,
            language: language, result: result)
        return result
    }
}

/// 应用结果上方的内联答案卡片；可像普通行一样选中，按 Enter 复制。
struct CalculatorCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppCore.self) private var core
    let result: CalcResult
    let selected: Bool

    var body: some View {
        let result = core.calcNumberFormat.localized(result)
        return Group {
            switch result.payload {
            case .value(let display, _):
                HStack(spacing: 0) {
                    LeadCardColumn(
                        text: CalcSyntax.highlighted(result.expression),
                        badge: result.sourceBadge)
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    LeadCardColumn(
                        text: CalcSyntax.highlighted(display), badge: result.targetBadge,
                        weight: .semibold)
                }
                .fixedSize(horizontal: false, vertical: true)
            case .error(let message):
                HStack(spacing: metrics.spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxxl)
        .leadCard(selected: selected)
    }
}

/// 将表达式中起连接作用的单词置淡，使它们连接的值优先被阅读。
private enum CalcSyntax {
    /// 按空格逐词重建带属性的字符串，并置淡其中的连接词。
    static func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString()
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        // 逐词重建，使连接词只能整词匹配——`min` 不会被误认为 `in`。
        for (index, word) in words.enumerated() {
            if index > 0 { attributed.append(AttributedString(" ")) }
            var piece = AttributedString(String(word))
            if isConnector(word, at: index, of: words) {
                piece.foregroundColor = Theme.Colors.textTertiary
            }
            attributed.append(piece)
        }
        return attributed
    }

    /// `in` 会连接两个单位并跟在其中一个之后；在 `10 in in cm` 中只有第二个 `in` 起连接作用。
    private static func isConnector(
        _ word: Substring, at index: Int, of words: [Substring]
    ) -> Bool {
        let lowered = word.lowercased()
        if connectors.contains(lowered) { return true }
        guard lowered == "in", index > 0, index + 1 < words.count else { return false }
        return words[index + 1].lowercased() != "in"
    }

    /// 仅指单词，不含单位：`min` 与 `in` 同时也是单位，所以只能按位置判定。
    private static let connectors: Set<String> = [
        "to", "of", "off", "on", "as", "from", "ago", "at", "tip", "ratio", "average", "avg",
        "mean", "sum", "total", "round", "nearest", "and", "is", "what", "the", "next", "last",
        "+", "-", "×", "÷", "^", "→", "->", "mod"
    ]
}

/// 卡片上的操作菜单；只有答案可复制，因此错误卡片不会用到它。
@MainActor
enum CalcActionsMenu {
    /// 构造卡片的弹出菜单内容：复制答案、置回搜索栏、复制完整算式。
    static func content(result: CalcResult, core: AppCore) -> PopoverMenuContent {
        var items = [
            PopoverMenuItem(
                title: core.settings.text(CalculatorKey.copyAnswer), systemImage: "doc.on.doc",
                shortcut: "↵"
            ) {
                core.calculatorCoordinator.copyCalculatorResult(result)
            }
        ]
        if result.canChain {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(CalculatorKey.putAnswerInSearchBar),
                    systemImage: "text.cursor", shortcut: "⌘↵"
                ) {
                    core.calculatorCoordinator.putAnswerInSearchBar(result)
                })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(CalculatorKey.copyCalculation),
                systemImage: "doc.on.doc.fill", shortcut: "⇧⌘↵"
            ) {
                core.calculatorCoordinator.copyCalculationWithExpression(result)
            })
        return PopoverMenuContent(
            header: core.calcNumberFormat.localizedExpression(result.expression), items: items)
    }
}
