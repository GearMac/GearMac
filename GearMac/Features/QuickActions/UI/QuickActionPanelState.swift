// 文件职责：承载 Quick Action 结果面板的可观察状态，包括阶段、输出文本、目标语言与文本差异。
// 分层：UI；@MainActor 的 @Observable 状态对象，由面板控制器持有，不直接操作窗口。
import Foundation
import Observation

/// 面板持有的判定结果载荷：答案列表与用量。
struct QuickActionDecisionsOutcome {
    let answers: [DecisionsAnswer]
    let usage: DecisionsUsage?
}

/// 由控制器而非视图持有，因此 SwiftUI 重绘期间回复仍能持续到达。
@MainActor
@Observable
final class QuickActionPanelState {
    /// 面板的当前阶段：进行中、完成、失败，或需要下载语言包。
    enum Phase: Equatable {
        case running
        case finished
        case failed(String)
        /// 该语言对受支持但尚未下载；用户需在系统设置中获取。
        case needsLanguageDownload
    }

    let action: QuickAction
    let original: String
    private(set) var output = ""
    private(set) var phase: Phase = .running
    var targetLanguage: Locale.Language

    /// Decide 的结构化结果；非 nil 时面板按判定结果渲染，Copy 序列化为文本。
    private(set) var decisions: QuickActionDecisionsOutcome?

    /// 差异计算结果的缓存。
    @ObservationIgnored private var cachedDiff: [TextDiffEngine.Chunk]?

    /// 原文与结果之间的文本差异，仅在该动作启用差异显示且已完成时返回。
    var diff: [TextDiffEngine.Chunk] {
        guard action.showsDiff, phase == .finished else { return [] }
        if let cachedDiff { return cachedDiff }
        let chunks = TextDiffEngine.diff(original: original, modified: output)
        cachedDiff = chunks
        return chunks
    }

    /// 是否仍在进行中。
    var isRunning: Bool { phase == .running }

    /// 是否已完成且有输出，可以执行替换。
    var canReplace: Bool { phase == .finished && !output.isEmpty && decisions == nil }

    /// 是否已有可复制的内容：判定结果或普通输出。
    var canCopy: Bool { decisions != nil || canReplace }

    /// 以动作、原始文本与目标语言初始化面板状态。
    init(action: QuickAction, original: String, targetLanguage: Locale.Language) {
        self.action = action
        self.original = original
        self.targetLanguage = targetLanguage
    }

    /// 追加一段流式输出片段。
    func append(_ delta: String) {
        output += delta
    }

    /// 重置为初始的进行中状态，清空输出与差异缓存。
    func restart() {
        output = ""
        phase = .running
        cachedDiff = nil
        decisions = nil
    }

    /// 以最终文本结束本次执行。
    func finish(_ text: String) {
        output = text
        phase = .finished
    }

    /// 以判定结果结束本次执行；面板主体改按概率渲染，不再走文本分支。
    func finishDecisions(_ answers: [DecisionsAnswer], usage: DecisionsUsage?) {
        decisions = QuickActionDecisionsOutcome(answers: answers, usage: usage)
        output = ""
        phase = .finished
    }

    /// 面板 Copy 的文本：判定结果按界面语言序列化，其余动作为输出本身。
    func copyText(language: AppLanguage) -> String {
        if let decisions {
            return DecisionsResultText.serialize(
                decisions.answers, usage: decisions.usage, language: language)
        }
        return output
    }

    /// 记录失败信息并进入失败阶段。
    func fail(_ message: String) {
        phase = .failed(message)
    }

    /// 进入需要下载语言包的阶段。
    func requireLanguageDownload() {
        phase = .needsLanguageDownload
    }
}
