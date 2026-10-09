// 文件职责：通过只监听（listen-only）的 CGEvent tap 识别纯修饰键的单击、双击与按住手势，并分发对应动作。
// 分层：Service；主 actor 持有 tap 与 CF 句柄，跨 actor 只传值，且不改写任何事件。
import AppKit
import Carbon.HIToolbox

/// C 入口：先归约为 Sendable 标量，再跨入主 actor。仅监听，因此不改变任何事件。
private func modifierTapEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ModifierTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    // macOS 在单独按下 Globe 释放后会跟随一个 key-down 179；它并不是独立的按键。
    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 179 {
        return Unmanaged.passUnretained(event)
    }
    let isFlagsChanged = type == .flagsChanged
    let flagsRaw = event.flags.rawValue
    let keyCode =
        type == .keyDown || isFlagsChanged
        ? Int(event.getIntegerValueField(.keyboardEventKeycode)) : -1
    MainActor.assumeIsolated {
        monitor.process(isFlagsChanged: isFlagsChanged, flagsRaw: flagsRaw, keyCode: keyCode)
    }
    return Unmanaged.passUnretained(event)
}

/// 只监听模式的修饰键事件 tap。参见 docs/features/hotkeys.md#modifier-only-shortcuts。
@MainActor
@Observable
final class ModifierTapMonitor: HealthCheckable {
    /// 在存在绑定但无法创建 tap 时为 true；由录制器向用户展示。
    private(set) var needsAccessibility = false

    /// 在该 tap 的最终释放时触发，因此动作执行时按键已经抬起。
    @ObservationIgnored var onTrigger: ((HotKeyBinding) -> Void)?
    @ObservationIgnored var onHoldPressed: (() -> Void)?
    @ObservationIgnored var onHoldReleased: (() -> Void)?
    @ObservationIgnored var onHoldCancelled: (() -> Void)?

    /// 录制器捕获期间置位，避免编辑绑定本身触发动作。
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            resetDetectors()
        }
    }

    /// 当前需要监听的修饰键绑定集合。
    private var bound: Set<HotKeyBinding> = []
    /// 由 tap 回调在每次修饰键转变时推进；拆除时释放。
    @ObservationIgnored private var doubleTapDetector = DoubleTapDetector()
    @ObservationIgnored private var modifierDetector = ModifierKeyDetector()
    @ObservationIgnored private var pendingSingle: Task<Void, Never>?
    @ObservationIgnored private var pendingHold: Task<Void, Never>?
    @ObservationIgnored private var pendingBinding: HotKeyBinding?
    private var globeDown = false
    private var holdKey: ModifierKey?
    private var holding = false
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true
    private var loggedTapFailure = false

    @ObservationIgnored weak var healthTicker: HealthTicker?

    // tap 持有未保留的 `self`，因此其生命周期不能超过本对象。
    isolated deinit {
        tearDownTap()
    }

    /// 安装会话观察者并同步 tap 的安装状态。
    func start() {
        installObserversIfNeeded()
        syncTapPresence()
    }

    /// 当前已分配的纯修饰键绑定；空集合会完全拆除 tap。
    func update(bound: Set<HotKeyBinding>, holdKey: ModifierKey? = nil) {
        guard bound != self.bound || holdKey != self.holdKey else { return }
        self.bound = bound
        self.holdKey = holdKey
        resetDetectors()
        syncTapPresence()
    }

    // MARK: - Detection

    fileprivate func process(isFlagsChanged: Bool, flagsRaw: UInt64, keyCode: Int) {
        guard !isPaused else { return }
        // `systemUptime` 是单调的，因此系统时钟调整不会把单击误判为按住。
        let now = ProcessInfo.processInfo.systemUptime
        let input: DoubleTapDetector.Input
        if isFlagsChanged {
            let flags = CGEventFlags(rawValue: flagsRaw)
            let modifiers = Self.modifiers(in: flags)
            if keyCode == kVK_Function { globeDown = flags.contains(.maskSecondaryFn) }
            let keys = ModifierKey.held(in: flagsRaw, globeDown: globeDown)
            if let event = modifierDetector.handle(keys, at: now) {
                handleModifier(event)
            }
            input = .modifiers(modifiers, hasOtherModifiers: Self.hasOtherModifiers(in: flags))
        } else {
            // 按住进行中时，Return 与 Escape 属于听写面板。
            if holding,
                keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
                    || keyCode == kVK_Escape
            {
                return
            }
            modifierDetector.cancel()
            cancelPendingSingle()
            cancelHold()
            input = .otherInput
        }
        guard let modifier = doubleTapDetector.handle(input, at: now),
            bound.contains(.doubleTap(modifier))
        else { return }
        cancelPendingSingle()
        onTrigger?(.doubleTap(modifier))
    }

    /// 处理修饰键检测器上报的按下/释放/取消事件。
    private func handleModifier(_ event: ModifierKeyDetector.Event) {
        switch event {
        case .pressed(let key):
            if let holdKey, key == holdKey {
                pendingHold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(DoubleTapDetector.maxHold))
                    guard !Task.isCancelled, let self else { return }
                    pendingHold = nil
                    holding = true
                    onHoldPressed?()
                }
            } else if key.singleBinding != pendingBinding {
                cancelPendingSingle()
            }
        case .released(let key, let doubleTap, let held):
            if key == holdKey {
                pendingHold?.cancel()
                pendingHold = nil
                if holding {
                    holding = false
                    onHoldReleased?()
                }
                return
            }
            guard !held else { cancelPendingSingle(); return }
            if doubleTap, bound.contains(key.doubleBinding) {
                cancelPendingSingle()
                onTrigger?(key.doubleBinding)
            } else if bound.contains(key.singleBinding) {
                cancelPendingSingle()
                let hasDoubleTap =
                    bound.contains(key.doubleBinding)
                    || key.modifier.map { bound.contains(.doubleTap($0)) } == true
                guard hasDoubleTap else {
                    modifierDetector.cancel()
                    onTrigger?(key.singleBinding)
                    return
                }
                pendingBinding = key.singleBinding
                pendingSingle = Task { [weak self] in
                    try? await Task.sleep(for: ModifierKeyDetector.resolutionWindow)
                    guard !Task.isCancelled, let self else { return }
                    pendingSingle = nil
                    pendingBinding = nil
                    onTrigger?(key.singleBinding)
                }
            }
        case .cancelled:
            cancelPendingSingle()
            cancelHold()
        }
    }

    /// 取消待定的单击判定。
    private func cancelPendingSingle() {
        pendingSingle?.cancel()
        pendingSingle = nil
        pendingBinding = nil
    }

    /// 取消进行中或待定的按住状态。
    private func cancelHold() {
        pendingHold?.cancel()
        pendingHold = nil
        guard holding else { return }
        holding = false
        onHoldCancelled?()
    }

    /// 复位全部检测器与待定任务。
    private func resetDetectors() {
        doubleTapDetector.reset()
        modifierDetector.reset()
        globeDown = false
        cancelPendingSingle()
        cancelHold()
    }

    /// 提取当前 flags 中按下的修饰键集合（供双击检测使用）。
    private static func modifiers(in flags: CGEventFlags) -> Set<DoubleTapModifier> {
        var held: Set<DoubleTapModifier> = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }

    // 绝不含 `maskAlphaShift`：它跟踪的是锁定状态，会让 Caps Lock 开启时的所有点按失效。
    private static func hasOtherModifiers(in flags: CGEventFlags) -> Bool {
        flags.contains(.maskSecondaryFn)
    }

    // MARK: - Tap lifecycle

    /// 按需安装会话切换通知观察者。
    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        // 快速用户切换：键盘归另一个会话所有，因此停止监听。
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    /// 会话激活状态变化时复位检测器并同步 tap。
    private func sessionDidChange(active: Bool) {
        sessionActive = active
        resetDetectors()
        syncTapPresence()
    }

    /// 根据绑定与会话状态决定安装或拆除 tap。
    private func syncTapPresence() {
        guard !bound.isEmpty, sessionActive else {
            tearDownTap()
            healthTicker?.unsubscribe(self)
            needsAccessibility = false
            return
        }
        healthTicker?.subscribe(self)
        installTapIfNeeded()
    }

    /// 尚未安装时创建只监听的事件 tap（需要辅助功能权限）。
    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                // 追加在末尾，使 `HyperKeyTap` 的改写先落地。参见 docs/features/hotkeys.md。
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: modifierTapEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // 即使是只监听的 tap 也需要辅助功能权限；健康检查定时器会重试直到授权。
            if !loggedTapFailure {
                NSLog("GearMac: Failed to create modifier event tap")
                loggedTapFailure = true
            }
            needsAccessibility = true
            return
        }
        loggedTapFailure = false
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        needsAccessibility = false
    }

    /// 移除事件 tap 及其 run loop source。
    private func tearDownTap() {
        resetDetectors()
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

    /// 系统禁用 tap 时调用；此时任何记录到一半的按键都已失效。
    fileprivate func tapWasDisabled() {
        resetDetectors()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    /// 存在绑定时每秒执行一次的看门狗。参见 docs/features/hotkeys.md#lifecycle。
    func healthCheck() {
        guard !bound.isEmpty, sessionActive else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            needsAccessibility = true
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            resetDetectors()
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }
}
