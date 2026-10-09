// 文件职责：文本注入的核心实现——定义注入文本模型、替换策略、投递队列与剪贴板租约，并按进程内、辅助功能、键盘事件三个层级把文本投递到目标。
// 分层：Service（TextInjection）；集中承担 AppKit、Carbon、辅助功能（AX）与剪贴板副作用，Model 层不得依赖。
import AppKit
import Carbon.HIToolbox

/// 自带独立的数据形状，而非复用调用方的结果类型，使注入器不归属于任何单一功能。
struct InjectedText: Equatable, Sendable {
    let text: String
    /// 让光标停在距文本末尾该字符数之前；为 nil 时停在文本之后。
    let cursorOffsetFromEnd: Int?

    init(_ text: String, cursorOffsetFromEnd: Int? = nil) {
        self.text = text
        self.cursorOffsetFromEnd = cursorOffsetFromEnd
    }

    /// 从插入文本起点到光标落点的 UTF-16 距离。
    var caretPrefixLength: Int {
        let offset = min(max(cursorOffsetFromEnd ?? 0, 0), text.count)
        return text[..<text.index(text.endIndex, offsetBy: -offset)].utf16.count
    }
}

/// 一次辅助功能（AX）替换的结果。
enum AccessibilityReplacement: Equatable {
    case delivered
    case unavailable
    case rejected

    /// `.rejected` 表示文档已不是我们测量过的那一份，此时用事件写入会改到错误的文本。
    var fallsBackToEvents: Bool { self == .unavailable }
}

/// 替换过程要做的两个判断；保持纯函数，以便测试 harness 能同时驱动两个投递层。
enum TextReplacementPolicy {
    /// 关键词在目标文本中的判定结果。
    enum KeywordState: Equatable {
        case matched(NSRange)
        case pending
        case rejected
    }

    /// 文本还太少说明渲染器尚未跟上；文本足够却不匹配才是真正的失配。
    static func keywordState(
        value: String, selectedRange: NSRange, keyword: String
    ) -> KeywordState {
        guard selectedRange.length == 0,
            let selectedStringRange = Range(selectedRange, in: value)
        else { return .rejected }
        let beforeCursor = value[..<selectedStringRange.lowerBound]
        guard beforeCursor.count >= keyword.count else { return .pending }
        let start = beforeCursor.index(beforeCursor.endIndex, offsetBy: -keyword.count)
        guard beforeCursor[start...].lowercased() == keyword.lowercased() else { return .rejected }
        return .matched(NSRange(start..<beforeCursor.endIndex, in: value))
    }

    /// Chromium 会返回 `.success` 却什么都没做，因此必须回读确认取值与我们的写入一致。
    static func confirmsReplacement(
        originalValue: String,
        replacementRange: NSRange,
        insertedText: String,
        observedValue: String?
    ) -> Bool {
        guard let observedValue,
            let stringRange = Range(replacementRange, in: originalValue)
        else { return false }
        var expected = originalValue
        expected.replaceSubrange(stringRange, with: insertedText)
        return observedValue == expected
    }
}

/// 一次投递的完成状态收敛器：只结算一次，先到达者胜出。
@MainActor
final class DeliveryCompletion {
    private let onDelivered: @MainActor () -> Void
    private let onFailed: @MainActor () -> Void
    private(set) var isConfirmed = false
    private var isSettled = false

    init(
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        self.onDelivered = onDelivered
        self.onFailed = onFailed
    }

    /// 标记本次投递已确认成功。
    func confirm() {
        guard !isSettled else { return }
        isSettled = true
        isConfirmed = true
        onDelivered()
    }

    /// 由 `defer` 驱动；即使投递提前返回也会如实上报失败，而不是无声消失。
    func settle() {
        guard !isSettled else { return }
        isSettled = true
        onFailed()
    }
}

/// 文本注入器：按目标选择进程内、辅助功能或键盘事件三层投递，并管理投递队列与剪贴板租约。
@MainActor
final class TextInjector {
    typealias AutomaticGeneration = UInt

    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let deliveryQueue: DeliveryQueue
    private var automaticGeneration: AutomaticGeneration = 0
    private var activePasteboardLease: TemporaryPasteboardLease?

    init(
        clipboardManager: ClipboardManager, settings: AppSettings,
        deliveryQueue: DeliveryQueue = DeliveryQueue()
    ) {
        self.clipboardManager = clipboardManager
        self.settings = settings
        self.deliveryQueue = deliveryQueue
    }

    /// 仍有粘贴在途，或我们仍持有借用的剪贴板。
    var isDelivering: Bool { !deliveryQueue.isIdle || activePasteboardLease != nil }

    /// 交互式展开前的准入检查：自家编辑器可直接写入，外部 App 需先确保辅助功能授权。
    func prepareInteractiveExpansion(target: InjectionTarget?) -> Bool {
        if let editor = target?.ownEditor { return editor.isEditable }
        guard targetAcceptsInjection(target?.externalApp), Permissions.ensureAccessibility() else {
            target?.restoreFocus()
            return false
        }
        return true
    }

    /// 开始一次自动展开，返回本次的代次编号；不允许展开时返回 nil。
    func beginAutomaticExpansion(target: InjectionTarget?) -> AutomaticGeneration? {
        cancelAutomaticExpansion()
        guard expansionIsAllowed(generation: automaticGeneration, target: target) else { return nil }
        return automaticGeneration
    }

    /// 取消自动展开：代次递增使在途投递失效，并把光标交还目标。
    func cancelAutomaticExpansion(target: InjectionTarget? = nil) {
        automaticGeneration &+= 1
        deliveryQueue.cancelAutomatic()
        target?.restoreFocus()
    }

    /// 应用退出前的清理：作废自动展开、取消全部投递并归还剪贴板。
    func prepareForTermination() {
        automaticGeneration &+= 1
        deliveryQueue.cancelAll()
        finishPendingPasteboardOwnership()
    }

    /// 取消参数提示：自动展开场景走取消流程，交互场景只交还光标。
    func cancelArgumentPrompt(
        automaticGeneration: AutomaticGeneration?,
        target: InjectionTarget?
    ) {
        if automaticGeneration != nil {
            cancelAutomaticExpansion(target: target)
        } else {
            target?.restoreFocus()
        }
    }

    /// 热键的目标取自 `frontmostApplication`，而它可能就是 GearMac 自己。
    private func targetAcceptsInjection(_ targetApp: NSRunningApplication?) -> Bool {
        guard let targetApp,
            !targetApp.isTerminated,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier,
            !IsSecureEventInputEnabled()
        else { return false }
        return true
    }

    private func automaticExpansionIsAllowed(
        generation: AutomaticGeneration,
        targetApp: NSRunningApplication?
    ) -> Bool {
        guard generation == automaticGeneration,
            settings.snippetsEnabled,
            Permissions.isAccessibilityTrusted(),
            targetAcceptsInjection(targetApp)
        else { return false }
        return true
    }

    /// 进程内无需授权、激活或投递事件：自家视图本身就是全部约定。
    private func expansionIsAllowed(
        generation: AutomaticGeneration,
        target: InjectionTarget?
    ) -> Bool {
        switch target {
        case .ownEditor(let editor):
            return generation == automaticGeneration && settings.snippetsEnabled && editor.isEditable
        case .external(let app):
            return automaticExpansionIsAllowed(generation: generation, targetApp: app)
        case nil:
            return false
        }
    }

    /// 采集展开所需上下文：剪贴板历史、选区、当前时间、日历与区域设置。
    func captureExpansionContext(
        target: InjectionTarget?,
        clipboardHistory: [String]
    ) -> SnippetTemplateEngine.ExpansionContext {
        SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: clipboardHistory,
            selection: selection(in: target),
            now: Date(),
            calendar: Calendar.current,
            locale: Locale.current,
            timeZone: .current)
    }

    /// 调用方必须明确确实存在选区：长度为 0 的选区会在光标处插入。
    func replaceSelection(
        with text: String,
        in targetApp: NSRunningApplication?,
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        deliver(
            InjectedText(text), target: targetApp.map(InjectionTarget.external),
            expectedKeyword: nil, keywordLength: 0,
            automaticGeneration: nil, onDelivered: onDelivered, onFailed: onFailed)
    }

    /// `changeCount` 始终不变意味着没有选中任何内容，而不是旧剪贴板赢了。
    func copySelection(from targetApp: NSRunningApplication?) async -> String? {
        await deliveryQueue.drain()
        guard finishPendingPasteboardOwnership(),
            await activateAndWaitForTarget(targetApp, automaticGeneration: nil),
            deliveryIsAllowed(
                automaticGeneration: nil, targetApp: targetApp,
                promptForInteractiveAccessibility: true)
        else { return nil }
        return await copySelection(from: targetApp, pasteboard: NSPasteboard.general)
    }

    /// 拆出这个重载是为了让 harness 用桩剪贴板驱动，而无需真的操作另一个 App。
    func copySelection(
        from targetApp: NSRunningApplication?, pasteboard: any PasteboardAccess
    ) async -> String? {
        clipboardManager.prepareForGearMacPasteboardMutation()
        guard let original = PasteboardSnapshot(pasteboard: pasteboard) else { return nil }
        defer { restore(original, to: pasteboard) }

        Paster.postCommandC(toPid: targetApp?.processIdentifier)
        for _ in 0..<Self.copyPollAttempts {
            guard await wait(for: Self.copyPollInterval) else { return nil }
            guard pasteboard.changeCount != original.changeCount else { continue }
            guard let copied = PasteboardSnapshot(pasteboard: pasteboard),
                let data = copied.firstStringData
            else { return nil }
            return String(bytes: data, encoding: .utf8)
        }
        return nil
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: any PasteboardAccess) {
        guard let items = snapshot.pasteboardItems() else { return }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { return }
        clipboardManager.synchronizeAfterGearMacPasteboardMutation(
            changeCount: pasteboard.changeCount)
    }

    /// 复制操作远在 1 秒内即可完成；超过这个时间说明目标 App 根本不会响应。
    private static let copyPollAttempts = 40
    private static let copyPollInterval = Duration.milliseconds(25)

    /// 按目标类型投递文本：串行进入投递队列，并通过完成回调上报结果。
    func deliver(
        _ injected: InjectedText,
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?,
        isValid: @escaping @MainActor () -> Bool = { true },
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        let targetApp = target?.externalApp
        activate(targetApp)
        if let automaticGeneration {
            guard expansionIsAllowed(generation: automaticGeneration, target: target) else { return }
        } else {
            guard prepareInteractiveExpansion(target: target) else {
                onFailed()
                return
            }
        }

        deliveryQueue.enqueue(isAutomatic: automaticGeneration != nil) { [weak self] in
            guard let self else { return }
            let completion = DeliveryCompletion(onDelivered: onDelivered, onFailed: onFailed)
            guard isValid() else { completion.settle(); return }
            if let editor = target?.ownEditor {
                await self.deliverInProcess(
                    injected,
                    into: editor,
                    expectedKeyword: expectedKeyword,
                    keywordLength: keywordLength,
                    automaticGeneration: automaticGeneration,
                    isValid: isValid,
                    completion: completion)
                return
            }
            await self.performDelivery(
                injected,
                targetApp: targetApp,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                completion: completion)
        }
    }

    /// 无需授权、激活或剪贴板，但关键词匹配仍遵循规则 2 的收敛等待。
    private func deliverInProcess(
        _ injected: InjectedText,
        into editor: any InjectableTextView,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?,
        isValid: @MainActor () -> Bool,
        completion: DeliveryCompletion
    ) async {
        defer { completion.settle() }
        for _ in 0..<Self.convergenceAttempts {
            // 事件 tap 跑在 AppKit 之前，若在等待前读取，会把过时的视图状态误判为未命中。
            if keywordLength > 0 {
                guard await wait(for: Self.convergenceInterval) else { return }
            }
            guard isValid(),
                inProcessDeliveryIsAllowed(automaticGeneration: automaticGeneration, editor: editor)
            else { return }
            switch editor.keywordReplacementState(
                expectedKeyword: expectedKeyword, keywordLength: keywordLength)
            {
            case .matched(let range):
                editor.inject(injected, over: range)
                completion.confirm()
                return
            case .rejected:
                return
            case .pending:
                continue
            }
        }
    }

    private func inProcessDeliveryIsAllowed(
        automaticGeneration: AutomaticGeneration?,
        editor: any InjectableTextView
    ) -> Bool {
        guard let automaticGeneration else { return editor.isEditable }
        return expansionIsAllowed(generation: automaticGeneration, target: .ownEditor(editor))
    }

    private func performDelivery(
        _ injected: InjectedText,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?,
        completion: DeliveryCompletion
    ) async {
        defer { completion.settle() }
        guard finishPendingPasteboardOwnership(),
            await activateAndWaitForTarget(
                targetApp,
                automaticGeneration: automaticGeneration),
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: true)
        else { return }

        let accessibilityReplacement = await replaceUsingAccessibility(
            injected,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration)
        if accessibilityReplacement == .delivered {
            completion.confirm()
            return
        }
        guard accessibilityReplacement.fallsBackToEvents else { return }

        guard
            await deliverUsingEvents(
                injected.text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        else { return }

        guard let offset = injected.cursorOffsetFromEnd, offset > 0 else {
            completion.confirm()
            return
        }
        for index in 0..<offset {
            guard
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false),
                postKey(code: CGKeyCode(kVK_LeftArrow), targetApp: targetApp)
            else { return }
            if index < offset - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return
            }
        }
        completion.confirm()
    }

    private func deliverUsingEvents(
        _ text: String,
        keywordLength: Int,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        let isShortSingleLine =
            text.count <= 100
            && !text.contains("\n")
            && !text.contains("\r")
        if isShortSingleLine {
            return await deliverUsingUnicodeEvents(
                text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        }

        guard let lease = beginTemporaryPasteboardLease(text) else {
            return await deliverUsingUnicodeEvents(
                text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        }
        activePasteboardLease = lease
        defer { finish(lease) }

        guard let deletionEvents = makeDeletionEvents(count: keywordLength),
            await wait(for: .milliseconds(80)),
            lease.isOwned,
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false),
            await postEventGroups(
                deletionEvents,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration),
            await waitAfterKeywordDeletion(keywordLength),
            lease.isOwned,
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false)
        else { return false }

        let stateBeforePaste = accessibilityTextState(in: targetApp)
        Paster.postCommandV(toPid: targetApp?.processIdentifier)
        return await waitForPasteConfirmation(
            previousState: stateBeforePaste,
            pasteboardLease: lease,
            targetApp: targetApp,
            automaticGeneration: automaticGeneration)
    }

    private func deliverUsingUnicodeEvents(
        _ text: String,
        keywordLength: Int,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        guard let insertionEvents = makeUnicodeEvents(text),
            let deletionEvents = makeDeletionEvents(count: keywordLength),
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false),
            await postEventGroups(
                deletionEvents,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration),
            await waitAfterKeywordDeletion(keywordLength),
            await postEventGroups(
                insertionEvents,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        else { return false }

        return await wait(for: .milliseconds(100))
    }

    /// 每组事件是一次按键，组间留出间隔，使不再接受按键的目标能中止后续投递。
    private func postEventGroups(
        _ events: [[CGEvent]],
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        for index in events.indices {
            guard
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }
            post(events[index], targetApp: targetApp)
            if index < events.count - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return false
            }
        }
        return true
    }

    private func waitAfterKeywordDeletion(_ keywordLength: Int) async -> Bool {
        if keywordLength == 0 { return true }
        return await wait(for: .milliseconds(40))
    }

    private func beginTemporaryPasteboardLease(_ text: String) -> TemporaryPasteboardLease? {
        clipboardManager.prepareForGearMacPasteboardMutation()
        return TemporaryPasteboardLease.begin(
            text: text,
            pasteboard: NSPasteboard.general
        ) { [clipboardManager] changeCount in
            clipboardManager.synchronizeAfterGearMacPasteboardMutation(
                changeCount: changeCount)
        }
    }

    @discardableResult
    private func finishPendingPasteboardOwnership() -> Bool {
        guard let lease = activePasteboardLease else { return true }
        for _ in 0..<3 where lease.isOwned { finish(lease) }
        return !lease.isOwned
    }

    private func finish(_ lease: TemporaryPasteboardLease) {
        switch lease.restoreIfOwned() {
        case .restored(let changeCount):
            // 避免剪贴板轮询器把恢复后的原内容误记为第二次复制。
            clipboardManager.synchronizeAfterGearMacPasteboardMutation(changeCount: changeCount)
        case .superseded:
            break
        case .failed:
            // 剪贴板仍归我们所有，因此保留 `activePasteboardLease` 供下方重试。
            if lease.isOwned { return }
        }
        if activePasteboardLease === lease { activePasteboardLease = nil }
    }

    private func deliveryIsAllowed(
        automaticGeneration: AutomaticGeneration?,
        targetApp: NSRunningApplication?,
        promptForInteractiveAccessibility: Bool
    ) -> Bool {
        if let automaticGeneration {
            guard
                automaticExpansionIsAllowed(
                    generation: automaticGeneration,
                    targetApp: targetApp),
                let targetApp,
                targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            else { return false }
            return true
        }
        // 每次投递前都会重新校验，使已退出或进入安全输入状态的目标及时中止投递。
        guard targetAcceptsInjection(targetApp), let targetApp,
            targetApp.isActive,
            NSWorkspace.shared.frontmostApplication?.processIdentifier
                == targetApp.processIdentifier
        else { return false }
        return promptForInteractiveAccessibility
            ? Permissions.ensureAccessibility()
            : Permissions.isAccessibilityTrusted()
    }

    private struct AccessibilityTextState: Equatable {
        let value: String
        let selectedRange: NSRange
    }

    private func activateAndWaitForTarget(
        _ targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        guard let targetApp else {
            return deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: nil,
                promptForInteractiveAccessibility: false)
        }
        activate(targetApp)
        for _ in 0..<50 {
            if targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            {
                return true
            }
            if let automaticGeneration,
                !automaticExpansionIsAllowed(
                    generation: automaticGeneration,
                    targetApp: targetApp)
            {
                return false
            }
            guard await wait(for: .milliseconds(20)) else { return false }
        }
        return false
    }

    private struct AccessibilityTarget {
        let element: AXUIElement
        let value: String
        let originalRange: NSRange
        let replacementRange: NSRange
    }

    private enum AccessibilityTargetState {
        case ready(AccessibilityTarget)
        case pending
        case unavailable
        case rejected
    }

    /// 规则 1：渲染器表面回答的是它自己的模型，因此绝不通过 AX 写入。
    private func replaceUsingAccessibility(
        _ injected: InjectedText,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?
    ) async -> AccessibilityReplacement {
        guard let targetApp else { return .unavailable }
        let state = await accessibilityTarget(
            in: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration)
        guard case .ready(let target) = state else {
            if case .rejected = state { return .rejected }
            return .unavailable
        }

        guard setSelectedRange(target.replacementRange, in: target.element) else {
            return .unavailable
        }
        guard
            AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextAttribute as CFString,
                injected.text as CFString) == .success
        else {
            _ = setSelectedRange(target.originalRange, in: target.element)
            return .unavailable
        }

        let observed = stringValue(in: target.element)
        guard
            TextReplacementPolicy.confirmsReplacement(
                originalValue: target.value,
                replacementRange: target.replacementRange,
                insertedText: injected.text,
                observedValue: observed)
        else {
            _ = setSelectedRange(target.originalRange, in: target.element)
            // 取值未变说明该层什么也没做；否则就是动到了我们无法命名的文本。
            return observed == target.value ? .unavailable : .rejected
        }

        _ = setSelectedRange(
            NSRange(
                location: target.replacementRange.location + injected.caretPrefixLength, length: 0),
            in: target.element)
        return .delivered
    }

    /// 规则 2：渲染器先应用按键再对外声明，因此短暂的滞后不算失配。
    private func accessibilityTarget(
        in targetApp: NSRunningApplication,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?
    ) async -> AccessibilityTargetState {
        for attempt in 0..<Self.convergenceAttempts {
            let state = inspectAccessibilityTarget(
                in: targetApp,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength)
            guard case .pending = state else { return state }
            guard attempt < Self.convergenceAttempts - 1,
                automaticGeneration != nil,
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false),
                await wait(for: Self.convergenceInterval)
            else { return .unavailable }
        }
        return .unavailable
    }

    private func inspectAccessibilityTarget(
        in targetApp: NSRunningApplication,
        expectedKeyword: String?,
        keywordLength: Int
    ) -> AccessibilityTargetState {
        guard let element = AccessibilityText.focusedElement(in: targetApp),
            !usesTextMarkerSelection(element),
            isAttributeSettable(kAXSelectedTextRangeAttribute, in: element),
            isAttributeSettable(kAXSelectedTextAttribute, in: element),
            let value = stringValue(in: element),
            let originalRange = selectedRange(in: element)
        else { return .unavailable }

        guard keywordLength > 0 else {
            // 连自己的取值都无法定位的偏移量说明该层已损坏，而不是文档发生变化的证据。
            guard Range(originalRange, in: value) != nil else { return .unavailable }
            return .ready(
                AccessibilityTarget(
                    element: element, value: value, originalRange: originalRange,
                    replacementRange: originalRange))
        }
        guard let expectedKeyword, expectedKeyword.count == keywordLength else { return .rejected }
        switch TextReplacementPolicy.keywordState(
            value: value, selectedRange: originalRange, keyword: expectedKeyword)
        {
        case .matched(let replacementRange):
            return .ready(
                AccessibilityTarget(
                    element: element, value: value, originalRange: originalRange,
                    replacementRange: replacementRange))
        case .pending: return .pending
        case .rejected: return .rejected
        }
    }

    /// 网页内容与 Monaco 只用 marker 暴露选区；它们的 `AXValue` 滞后或为空。
    private func usesTextMarkerSelection(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &value) == .success,
            let value
        else { return false }
        return CFGetTypeID(value) == AXTextMarkerRangeGetTypeID()
    }

    /// 渲染器，或 AppKit 把自家按键交还给我们，都在个位数毫秒内收敛。
    private static let convergenceAttempts = 8
    private static let convergenceInterval = Duration.milliseconds(5)

    private func waitForPasteConfirmation(
        previousState: AccessibilityTextState?,
        pasteboardLease: TemporaryPasteboardLease,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        var readStateAfterPaste = false
        for attempt in 0..<80 {
            guard pasteboardLease.isOwned,
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }

            if let previousState,
                let currentState = accessibilityTextState(in: targetApp)
            {
                readStateAfterPaste = true
                if currentState != previousState { return true }
            }
            if PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: attempt,
                hadPreviousState: previousState != nil,
                readStateAfterPaste: readStateAfterPaste)
            {
                return true
            }
            guard await wait(for: .milliseconds(25)) else { return false }
        }
        return false
    }

    private func accessibilityTextState(
        in targetApp: NSRunningApplication?
    ) -> AccessibilityTextState? {
        guard let targetApp,
            let element = AccessibilityText.focusedElement(in: targetApp),
            !usesTextMarkerSelection(element),
            let value = stringValue(in: element),
            let selectedRange = selectedRange(in: element)
        else { return nil }
        return AccessibilityTextState(value: value, selectedRange: selectedRange)
    }

    private func stringValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value) == .success
        else { return nil }
        return value as? String
    }

    private func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func setSelectedRange(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value) == .success
    }

    private func isAttributeSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                element,
                attribute as CFString,
                &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func activate(_ targetApp: NSRunningApplication?) {
        guard targetApp?.isTerminated == false else { return }
        targetApp?.activate()
    }

    private func selection(in target: InjectionTarget?) -> String {
        switch target {
        case .ownEditor(let editor): return editor.injectableSelection
        case .external(let app): return selectedText(in: app) ?? ""
        case nil: return ""
        }
    }

    private func selectedText(in targetApp: NSRunningApplication?) -> String? {
        guard Permissions.isAccessibilityTrusted(), let targetApp else { return nil }
        return AccessibilityText.selection(in: targetApp)
    }

    private func makeUnicodeEvents(_ text: String) -> [[CGEvent]]? {
        guard !text.isEmpty else { return [] }
        var groups: [[CGEvent]] = []
        for chunk in UnicodeTypingChunk.split(text) {
            guard let pair = makeUnicodeEvent(chunk) else { return nil }
            groups.append(pair)
        }
        return groups
    }

    private func makeUnicodeEvent(_ chunk: [UniChar]) -> [CGEvent]? {
        let source = CGEventSource(stateID: .combinedSessionState)
        var characters = chunk
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false)
        else { return nil }
        // 事件源会继承按住的修饰键，而热键的修饰键在打字时仍处于按下状态。
        down.flags = []
        up.flags = []
        tag(down)
        tag(up)
        down.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        up.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        return [down, up]
    }

    private func makeDeletionEvents(count: Int) -> [[CGEvent]]? {
        var events: [[CGEvent]] = []
        events.reserveCapacity(count)
        for _ in 0..<count {
            guard let pair = makeKeyEvents(code: CGKeyCode(kVK_Delete)) else { return nil }
            events.append(pair)
        }
        return events
    }

    private func makeKeyEvents(
        code: CGKeyCode,
        flags: CGEventFlags = []
    ) -> [CGEvent]? {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: false)
        else { return nil }
        down.flags = flags
        up.flags = flags
        tag(down)
        tag(up)
        return [down, up]
    }

    private func postKey(code: CGKeyCode, targetApp: NSRunningApplication?) -> Bool {
        guard let events = makeKeyEvents(code: code) else { return false }
        post(events, targetApp: targetApp)
        return true
    }

    private func tag(_ event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Paster.gearmacEventTag)
    }

    private func post(_ events: [CGEvent], targetApp: NSRunningApplication?) {
        for event in events { post(event, targetApp: targetApp) }
    }

    private func post(_ event: CGEvent, targetApp: NSRunningApplication?) {
        if let pid = targetApp?.processIdentifier {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    /// 可取消的等待；任务被取消时返回 false。
    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// 把待输入文本切分为 Blink 单次按键可接受的 UTF-16 单元块：Blink 用固定 4 个 UTF-16 单元的数组承载单次按键文本，超出部分会被 Chromium 丢弃。
enum UnicodeTypingChunk {
    static let maxUTF16Units = 4

    /// 按 Unicode 标量边界切分：孤立的代理项半截不成文本，而单个标量一定能放进 4 个单元。
    static func split(_ text: String) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        current.reserveCapacity(maxUTF16Units)
        for scalar in text.unicodeScalars {
            if current.count + UTF16.width(scalar) > maxUTF16Units {
                chunks.append(current)
                current = []
            }
            UTF16.encode(scalar) { current.append($0) }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// 判断在无法读到目标状态时，是否仍接受一次未经确认的粘贴。
enum PasteConfirmationPolicy {
    /// 尝试次数足够、或始终读不到目标状态时，接受未经确认的粘贴结果。
    static func acceptsUnconfirmedDelivery(
        attempt: Int,
        hadPreviousState: Bool,
        readStateAfterPaste: Bool
    ) -> Bool {
        attempt >= 15 && (!hadPreviousState || !readStateAfterPaste)
    }
}

/// 串行投递队列：保证同一时刻只有一个投递在途，并区分自动投递以便单独取消。
@MainActor
final class DeliveryQueue {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tail: (id: UUID, task: Task<Void, Never>)?
    private var automaticTaskID: UUID?

    var isIdle: Bool { tasks.isEmpty }

    /// 追加一次投递任务，串行排在队尾等待前一个完成。
    func enqueue(
        isAutomatic: Bool,
        operation: @escaping @MainActor () async -> Void
    ) {
        let id = UUID()
        let predecessor = tail?.task
        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer { self.finish(id: id) }
            guard !Task.isCancelled else { return }
            await operation()
        }
        tasks[id] = task
        tail = (id, task)
        if isAutomatic { automaticTaskID = id }
    }

    /// 取消当前的自动投递任务。
    func cancelAutomatic() {
        guard let automaticTaskID else { return }
        tasks[automaticTaskID]?.cancel()
        self.automaticTaskID = nil
    }

    /// 取消全部投递任务并清空队列。
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tail = nil
        automaticTaskID = nil
    }

    /// 等待当前队尾投递结束。
    func drain() async {
        await tail?.task.value
    }

    private func finish(id: UUID) {
        tasks.removeValue(forKey: id)
        if automaticTaskID == id { automaticTaskID = nil }
        if tail?.id == id { tail = nil }
    }
}

/// 剪贴板的最小抽象接口，便于测试注入桩实现。
@MainActor
protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardAccess {}

/// 临时剪贴板租约：借出剪贴板写入待投递文本，投递结束后归还原始内容。
@MainActor
final class TemporaryPasteboardLease {
    /// 归还剪贴板的结果。
    enum RestoreResult: Equatable {
        case restored(changeCount: Int)
        case superseded
        case failed
    }

    private let pasteboard: any PasteboardAccess
    private let ownedChangeCount: Int
    private let original: PasteboardSnapshot
    private var isFinished = false

    var isOwned: Bool {
        !isFinished && pasteboard.changeCount == ownedChangeCount
    }

    private init(
        pasteboard: any PasteboardAccess,
        ownedChangeCount: Int,
        original: PasteboardSnapshot
    ) {
        self.pasteboard = pasteboard
        self.ownedChangeCount = ownedChangeCount
        self.original = original
    }

    /// 借出剪贴板：先快照原内容，再写入待投递文本；任一步失败时尽力恢复原内容。
    static func begin(
        text: String,
        pasteboard: any PasteboardAccess,
        onMutation: (Int) -> Void = { _ in }
    ) -> TemporaryPasteboardLease? {
        guard let snapshot = PasteboardSnapshot(pasteboard: pasteboard),
            let temporaryItem = PasteboardSnapshot.temporaryItem(carrying: text),
            let originalItems = snapshot.pasteboardItems(),
            pasteboard.changeCount == snapshot.changeCount
        else { return nil }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([temporaryItem]) else {
            if originalItems.isEmpty || pasteboard.writeObjects(originalItems) {
                onMutation(pasteboard.changeCount)
            }
            return nil
        }
        let ownedChangeCount = pasteboard.changeCount
        onMutation(ownedChangeCount)
        return TemporaryPasteboardLease(
            pasteboard: pasteboard,
            ownedChangeCount: ownedChangeCount,
            original: snapshot)
    }

    /// 借出的剪贴板不保留原内容，因此恢复时需要按快照整体重写。
    func restoreIfOwned() -> RestoreResult {
        guard !isFinished else { return .superseded }
        guard pasteboard.changeCount == ownedChangeCount else {
            isFinished = true
            return .superseded
        }
        guard let items = original.pasteboardItems() else { return .failed }
        pasteboard.clearContents()
        isFinished = true
        guard items.isEmpty || pasteboard.writeObjects(items) else { return .failed }
        return .restored(changeCount: pasteboard.changeCount)
    }
}

/// 剪贴板内容的不可变快照，用于借出与恢复时的整体重写。
@MainActor
struct PasteboardSnapshot {
    /// 快照中的单个剪贴板条目：类型与数据的列表。
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]
    let changeCount: Int

    /// 快照中第一个纯文本类型的数据。
    var firstStringData: Data? {
        items.first?.values.first { $0.type == .string }?.data
    }

    /// 读取剪贴板全部条目；读取过程中 `changeCount` 变化则返回 nil，避免记录到不一致的内容。
    init?(pasteboard: any PasteboardAccess) {
        let changeCount = pasteboard.changeCount
        var items: [Item] = []
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else { return nil }
                values.append((type: type, data: data))
            }
            items.append(Item(values: values))
        }
        guard pasteboard.changeCount == changeCount else { return nil }
        self.items = items
        self.changeCount = changeCount
    }

    /// 保留的 `public.html` 正是 Chromium 编辑器偏好的类型，因此我们只借出纯文本。
    static func temporaryItem(carrying text: String) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
            item.setData(Data(), forType: ClipboardManager.internalType)
        else { return nil }
        return item
    }

    /// 按快照重建 NSPasteboardItem 列表；任一条目写入失败则返回 nil。
    func pasteboardItems() -> [NSPasteboardItem]? {
        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(items.count)
        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                guard pasteboardItem.setData(value.data, forType: value.type) else { return nil }
            }
            pasteboardItems.append(pasteboardItem)
        }
        return pasteboardItems
    }
}
