// 文件职责：基于 CGEventTap 的全局关键词监听——捕获按键输入、匹配 snippet 关键词并触发注入回调。
// 分层：Service；@MainActor，依赖 AppKit/Carbon 与辅助功能授权，事件 tap 仅监听不拦截。
import AppKit
import Carbon.HIToolbox

/// CGEventTap 回调：在事件进入应用前分类转发给监听器，并通过 userInfo 取回监听器实例。
private func snippetKeywordCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let listener = Unmanaged<SnippetKeywordListener>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { listener.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    // 点击会移动插入点，因此已缓存的输入前缀不再描述光标前内容。
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        MainActor.assumeIsolated {
            listener.userActivity()
            listener.clearBuffer()
        }
        return Unmanaged.passUnretained(event)
    }

    let eventUserData = event.getIntegerValueField(.eventSourceUserData)
    let secureEventInputEnabled = IsSecureEventInputEnabled()
    let typeRaw = type.rawValue
    let flagsRaw = event.flags.rawValue
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    var length = 0
    var characters = [UniChar](repeating: 0, count: 16)
    event.keyboardGetUnicodeString(
        maxStringLength: characters.count,
        actualStringLength: &length,
        unicodeString: &characters)
    let text = length > 0 ? String(utf16CodeUnits: characters, count: length) : nil

    MainActor.assumeIsolated {
        listener.processEvent(
            typeRaw: typeRaw,
            keyCode: keyCode,
            flagsRaw: flagsRaw,
            text: text,
            eventUserData: eventUserData,
            secureEventInputEnabled: secureEventInputEnabled)
    }
    return Unmanaged.passUnretained(event)
}

/// 事件 tap 的安装/恢复/拆除抽象，便于测试替换。
@MainActor
protocol SnippetKeywordTapControlling: AnyObject {
    var state: SnippetKeywordLifecyclePolicy.TapState { get }
    func install(listener: SnippetKeywordListener) -> Bool
    func reenable() -> Bool
    func tearDown()
}

/// 基于 CGEventTap 的真实实现，安装仅监听的事件 tap。
@MainActor
private final class SystemSnippetKeywordTapController: SnippetKeywordTapControlling {
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var state: SnippetKeywordLifecyclePolicy.TapState {
        guard let tapPort else { return .absent }
        return CGEvent.tapIsEnabled(tap: tapPort) ? .active : .disabled
    }

    func install(listener: SnippetKeywordListener) -> Bool {
        guard tapPort == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: snippetKeywordCallback,
                userInfo: Unmanaged.passUnretained(listener).toOpaque())
        else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }

        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    func reenable() -> Bool {
        guard let tapPort else { return false }
        CGEvent.tapEnable(tap: tapPort, enable: true)
        return CGEvent.tapIsEnabled(tap: tapPort)
    }

    func tearDown() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }
}

/// 监听全局按键并匹配 snippet 关键词，随辅助功能授权与前台会话状态动态启停。
@MainActor
@Observable
final class SnippetKeywordListener: HealthCheckable {
    typealias Status = SnippetKeywordListenerStatus

    private(set) var status: Status = .off

    @ObservationIgnored weak var healthTicker: HealthTicker?

    @ObservationIgnored private var observers: [NotificationToken] = []
    /// 按键缓冲区：事件 tap 回调会逐事件修改它，因此不参与观察追踪。
    @ObservationIgnored private var policy = SnippetKeywordPolicy()
    @ObservationIgnored private var onUserActivity: (() -> Void)?
    @ObservationIgnored
    private var onMatch: ((StoredSnippet.ID, String, Int, InjectionTarget?) -> Void)?
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    var isPromptingForArguments = false {
        didSet { clearBuffer() }
    }
    private var sessionActive = true
    private var loggedTapFailure = false

    private let tapController: any SnippetKeywordTapControlling
    private let accessibilityTrusted: () -> Bool
    private let secureEventInputEnabled: () -> Bool
    private let now: () -> Date
    private let syntheticEventTag: Int64
    private let logsTapFailures: Bool

    init(
        tapController: (any SnippetKeywordTapControlling)? = nil,
        accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        secureEventInputEnabled: @escaping () -> Bool = IsSecureEventInputEnabled,
        now: @escaping () -> Date = Date.init,
        syntheticEventTag: Int64,
        logsTapFailures: Bool = true
    ) {
        self.tapController = tapController ?? SystemSnippetKeywordTapController()
        self.accessibilityTrusted = accessibilityTrusted
        self.secureEventInputEnabled = secureEventInputEnabled
        self.now = now
        self.syntheticEventTag = syntheticEventTag
        self.logsTapFailures = logsTapFailures
    }

    /// 用当前启用的 snippet 重建关键词匹配表。
    func update(_ records: [StoredSnippet]) {
        policy.update(
            records.compactMap { record in
                guard record.snippet.isEnabled, let keyword = record.snippet.keyword else { return nil }
                return SnippetKeywordPolicy.Keyword(snippetID: record.id, value: keyword)
            })
    }

    /// 启动监听：保存回调、注册工作区通知观察者并同步 tap 状态。
    func start(
        onUserActivity: @escaping () -> Void,
        onMatch: @escaping (StoredSnippet.ID, String, Int, InjectionTarget?) -> Void
    ) {
        self.onUserActivity = onUserActivity
        self.onMatch = onMatch
        installObserversIfNeeded()
        healthTicker?.subscribe(self)
        syncTapPresence()
    }

    /// 停止监听：取消任务、移除观察者并拆除事件 tap。
    func stop() {
        matchTask?.cancel()
        matchTask = nil
        onUserActivity = nil
        onMatch = nil
        healthTicker?.unsubscribe(self)
        observers.removeAll()
        policy.reset()
        tapController.tearDown()
        sessionActive = true
        status = .off
    }

    /// 清空按键缓冲区。
    func clearBuffer() {
        policy.reset()
    }

    /// 非 GearMac 合成的按键意味着插入点重新属于读者，而非我们。
    func userActivity() {
        guard !isPromptingForArguments else { return }
        matchTask?.cancel()
        matchTask = nil
        onUserActivity?()
    }

    /// 健康检查：安全输入启用时重置缓冲区，并重新同步 tap 状态。
    func healthCheck() {
        if secureEventInputEnabled() { policy.reset() }
        syncTapPresence()
    }

    /// 是否已被请求监听（即存在匹配回调）。
    private var isRequested: Bool { onMatch != nil }

    /// 仅监听（listen-only）的事件 tap 只需要辅助功能授权，别无其他。
    private var hasAccessibility: Bool { accessibilityTrusted() }

    /// 首次安装工作区通知观察者（应用切换、会话激活/失活）。
    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearBuffer() }
                },
                center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidResign() }
                },
                center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidBecomeActive() }
                },
                center: center)
        ]
    }

    /// 依据生命周期决策同步事件 tap 的存在状态与对外状态。
    private func syncTapPresence() {
        let decision = lifecycleDecision()
        switch decision.tapAction {
        // tap 状态未变化，决策仍然有效：无需再计算一次。
        case .none:
            status = decision.status
            return
        case .install:
            installTapIfNeeded()
        case .reenable:
            reenableTap()
        case .tearDown:
            policy.reset()
            tapController.tearDown()
        }
        status = lifecycleDecision().status
    }

    /// 条件满足时安装事件 tap；失败时只记录一次日志。
    private func installTapIfNeeded() {
        guard tapController.state == .absent,
            isRequested,
            sessionActive,
            hasAccessibility
        else { return }
        guard tapController.install(listener: self) else {
            if !loggedTapFailure {
                if logsTapFailures {
                    NSLog("GearMac: Failed to create snippet keyword event tap")
                }
                loggedTapFailure = true
            }
            return
        }
        loggedTapFailure = false
    }

    /// 计算当前应处的状态与需要对 tap 执行的动作。
    private func lifecycleDecision() -> SnippetKeywordLifecyclePolicy.Decision {
        SnippetKeywordLifecyclePolicy.decide(
            isRequested: isRequested,
            isSessionActive: sessionActive,
            hasAccessibility: accessibilityTrusted(),
            tapState: tapController.state)
    }

    /// 重新启用被系统禁用的 tap；失败则拆除重装。
    private func reenableTap() {
        policy.reset()
        guard tapController.reenable() else {
            tapController.tearDown()
            installTapIfNeeded()
            return
        }
    }

    /// 系统禁用 tap 后的回调：重置缓冲区并重新同步。
    fileprivate func tapWasDisabled() {
        policy.reset()
        syncTapPresence()
    }

    /// 会话失活：暂停监听并重置缓冲区。
    private func sessionDidResign() {
        sessionActive = false
        policy.reset()
        syncTapPresence()
    }

    /// 会话恢复：重新开启监听并重置缓冲区。
    private func sessionDidBecomeActive() {
        sessionActive = true
        policy.reset()
        syncTapPresence()
    }

    /// 处理一次按键事件：分类输入、维护缓冲区，命中时触发回调。
    func processEvent(
        typeRaw: UInt32,
        keyCode: Int,
        flagsRaw: UInt64,
        text: String?,
        eventUserData: Int64,
        secureEventInputEnabled: Bool
    ) {
        guard isRequested, status == .active, !isPromptingForArguments else { return }
        let flags = CGEventFlags(rawValue: flagsRaw)
        let input = SnippetKeywordPolicy.classifyInput(
            text: text,
            isSynthetic: eventUserData == syntheticEventTag,
            secureEventInputEnabled: secureEventInputEnabled,
            isFlagsChanged: typeRaw == CGEventType.flagsChanged.rawValue,
            isKeyDown: typeRaw == CGEventType.keyDown.rawValue,
            hasCommandOrControl: flags.contains(.maskCommand) || flags.contains(.maskControl),
            isResetKey: Self.resetKeyCodes.contains(keyCode),
            isDeleteBackward: keyCode == kVK_Delete)
        if input != .ignored { userActivity() }
        guard let match = policy.process(input, at: now()) else { return }
        // 在此处随按键一起采样：等到回调送达时，读者可能已经换了目标。
        let target = InjectionTarget.current()
        // 在模态提示抢占焦点之前，先把触发键交还给前台应用。
        matchTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.matchTask = nil
            self.onMatch?(match.snippetID, match.keyword, match.deletionCount, target)
        }
    }

    /// 会清空缓冲区的复位按键集合。
    private static let resetKeyCodes: Set<Int> = [
        kVK_Return,
        kVK_ANSI_KeypadEnter,
        kVK_Escape,
        kVK_Tab,
        kVK_LeftArrow,
        kVK_RightArrow,
        kVK_UpArrow,
        kVK_DownArrow,
        kVK_Home,
        kVK_End,
        kVK_PageUp,
        kVK_PageDown,
        kVK_ForwardDelete
    ]
}
