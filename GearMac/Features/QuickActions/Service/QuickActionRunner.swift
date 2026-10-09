// 文件职责：读取当前选中文本并调用 AI provider 完成快捷动作处理。
// 分层：Service；只负责读取与转换，是否回写替换由 Coordinator 决定。
import AppKit

/// 读取选区并做转换；是否把结果写回文档是 Coordinator 的决定，不是这里的。
@MainActor
final class QuickActionRunner {
    /// 上限放在这里，而不是 provider 那里（放那里会以不透明的 context 错误返回）。
    static let maxSelectionBytes = 32_768

    /// 借来的 ⌘C 会向别人的应用合成按键，因此绝不能作为首选方案。
    static func selection(
        in targetApp: NSRunningApplication?, using injector: TextInjector
    ) async throws -> String {
        // 快捷键按下是明确的用户手势，因此可以弹权限提示，如同片段展开那样。
        guard Permissions.ensureAccessibility() else { throw QuickActionFailure.needsAccessibility }
        guard let targetApp,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier
        else { throw QuickActionFailure.noTarget }

        let reported = AccessibilityText.read(in: targetApp)
        if case .text(let text) = reported { return try accepted(text) }
        if let copied = await injector.copySelection(from: targetApp) {
            return try accepted(copied)
        }
        // 只有当 Accessibility 确实看到文本元素时，“确实没选中内容”才是诚实的回答。
        throw reported == .empty
            ? QuickActionFailure.noSelection
            : .unreadableApp(targetApp.localizedName ?? "That app")
    }

    /// 校验拿到的文本：去除空白后非空、且不超过字节上限，否则抛出对应失败。
    static func accepted(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickActionFailure.noSelection
        }
        guard text.utf8.count <= maxSelectionBytes else { throw QuickActionFailure.tooLong }
        return text
    }

    /// 无需维护完整记录，需要进度的调用方监听 `onDelta`，其余只需 await 结果。
    static func run(
        _ action: QuickAction, selection: String, using provider: any AIProvider,
        instructionOverride: String?,
        onDelta: @MainActor (String) -> Void = { _ in }
    ) async throws -> String {
        let request = AIRequest(
            instructions: QuickActionPrompt.instructions(
                for: action, override: instructionOverride),
            messages: [
                AIMessage(
                    role: .user,
                    text: QuickActionPrompt.message(for: action, selection: selection))
            ],
            maxOutputTokens: maxOutputTokens(for: action, selection: selection))
        var text = ""
        for try await event in provider.stream(request) {
            guard case .text(let delta) = event else { continue }
            text += delta
            onDelta(delta)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIProviderError.responseFailed("The model returned nothing.")
        }
        return trimmed
    }

    /// 端侧上下文窗口把 prompt 和回复计入同一预算，因此两者都要设上限。
    private static func maxOutputTokens(for action: QuickAction, selection: String) -> Int {
        let approximateTokens = max(selection.count / 3, 64)
        return action == .summarize
            ? min(approximateTokens, 512) : min(approximateTokens * 2, 2_048)
    }
}
