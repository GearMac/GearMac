// 文件职责：绘制文本插入符（caret），供搜索框之外的自绘控件模拟字段编辑器的光标闪烁。
// 分层：UI；闪烁由时间线驱动，不持有状态，仅作为视觉表现。
import SwiftUI

/// 自绘插入符：系统中唯一的字段编辑器属于搜索框，这些控件没有，因此需要自行绘制。
struct ExtensionCaret: View {
    @Environment(\.metrics) private var metrics
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    /// 每次编辑都从此时间点重新计时，使输入时光标表现与字段编辑器一致。
    let phase: Date

    var body: some View {
        // 由时间线驱动而非存储的计时器：每次按键都会重建 `body`，那样会让计时器重启。
        TimelineView(.periodic(from: phase, by: form.caretBlink)) { context in
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Theme.Colors.textPrimary)
                .frame(width: form.caretWidth)
                .frame(height: form.caretHeight)
                .opacity(Self.isLit(context.date, from: phase) ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    /// 与 AppKit 相同的节奏：每个周期的前半段点亮，后半段熄灭。
    private static func isLit(_ now: Date, from phase: Date) -> Bool {
        let period = ExtensionFormMetrics.base.caretBlink * 2
        let elapsed = now.timeIntervalSince(phase).truncatingRemainder(dividingBy: period)
        return elapsed < ExtensionFormMetrics.base.caretBlink
    }
}

/// 带列表控件用于搜索的文本；插入符叠加在插入点位置。
struct ExtensionQueryText: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let query: String
    let prompt: String
    /// 查询变化时由控件更新，用于重新点亮插入符。
    let phase: Date

    var body: some View {
        // 不单独占位：字段编辑器的插入符叠加在文本边缘之上，而不是位于其旁边。
        Text(query.isEmpty ? prompt : query)
            .font(metrics.typography.rowTitle)
            .foregroundStyle(query.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.head)
            .overlay(alignment: query.isEmpty ? .leading : .trailing) {
                ExtensionCaret(phase: phase)
                    .offset(x: query.isEmpty ? -form.caretPromptGap : 0)
            }
    }
}
