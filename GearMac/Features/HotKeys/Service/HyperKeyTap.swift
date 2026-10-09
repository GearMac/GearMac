// 文件职责：实现 Hyper Key 引擎：用 CGEvent 修改型事件 tap 把 Caps Lock 等物理键改写成 Hyper 修饰键，并管理 HID 重映射与按住状态机。
// 分层：Service；事件回调与 IOKit 连接都在主 actor 上，跨 actor 只传递 Sendable 的 Decision。
import AppKit
import Carbon.HIToolbox
@preconcurrency import IOKit.hidsystem

// 先快照可变的 C 全局量 `mach_task_self_`，避免 actor 代码直接读取原值。
private let machTaskSelf = mach_task_self_

/// C 入口：解析事件，跨入主 actor 取得 Sendable 的 `Decision`，再回到这里应用。
private func hyperKeyEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HyperKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == HyperKeyTap.syntheticTag
    let flags = event.flags.rawValue

    let decision = MainActor.assumeIsolated {
        tap.decide(
            type: type, keyCode: keyCode, flagsRaw: flags,
            isAutorepeat: isAutorepeat, isSynthetic: isSynthetic)
    }
    switch decision {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .suppress:
        return nil
    case .rewrite(let flags, let keyCode, let asFlagsChanged):
        if asFlagsChanged { event.type = .flagsChanged }
        if let keyCode {
            event.setIntegerValueField(.keyboardEventKeycode, value: keyCode)
        }
        event.flags = CGEventFlags(rawValue: flags)
        return Unmanaged.passUnretained(event)
    }
}

/// Caps Lock 作为 Hyper 键时通过 HID 重映射为 F18。参见 docs/features/hotkeys.md#the-hyper-key。
private enum CapsLockRemap {
    // HID 用途码：键盘页 0x07，Caps Lock 为 0x39，F18 为 0x6D。
    private static let mappingOn =
        #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    private static let mappingOff = #"{"UserKeyMapping":[]}"#

    // 串行队列，使快速的 on→off→on 切换按调用顺序生效而不是相互竞争。
    private static let queue = DispatchQueue(label: "com.gearmac.capslock-remap", qos: .utility)

    /// 异步开启或关闭 Caps Lock 的 HID 重映射。
    static func setEnabled(_ enabled: Bool) {
        let mapping = enabled ? mappingOn : mappingOff
        queue.async { apply(mapping) }
    }

    /// 供 `applicationWillTerminate` 使用的同步版本，此时分离的异步任务来不及执行。
    static func clearBlocking() {
        apply(mappingOff)
    }

    private static func apply(_ mapping: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", mapping]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.runObservingExit().wait()
            if process.terminationStatus != 0 {
                NSLog("GearMac: hidutil remap exited %d", process.terminationStatus)
            }
        } catch {
            NSLog("GearMac: hidutil caps lock remap failed: %@", error.localizedDescription)
        }
    }
}

/// Hyper Key 引擎，一个修改型事件 tap。参见 docs/features/hotkeys.md#the-hyper-key。
@MainActor
@Observable
final class HyperKeyTap: HealthCheckable {
    /// Hyper Key 的运行状态。
    enum Status: Equatable {
        case off
        case active
        case needsAccessibility
    }

    /// 回调应当执行的动作，在主 actor 上决定；`asFlagsChanged` 表示就地转换为 flagsChanged 事件。
    enum Decision: Sendable {
        case pass
        case suppress
        case rewrite(flags: UInt64, keyCode: Int64? = nil, asFlagsChanged: Bool = false)
    }

    /// 本 tap 发出的合成事件上的标记，使其不会对自身的合成事件做出反应。
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    /// 来自 IOLLEvent.h 的设备级修饰键位。参见 docs/features/hotkeys.md#the-hyper-key。
    private enum DeviceFlag {
        static let leftControl: UInt64 = 0x0000_0001
        static let leftShift: UInt64 = 0x0000_0002
        static let rightShift: UInt64 = 0x0000_0004
        static let leftCommand: UInt64 = 0x0000_0008
        static let rightCommand: UInt64 = 0x0000_0010
        static let leftOption: UInt64 = 0x0000_0020
        static let rightOption: UInt64 = 0x0000_0040
        static let rightControl: UInt64 = 0x0000_2000
    }

    private(set) var status: Status = .off

    @ObservationIgnored private var settings: AppSettings?
    // 供 tap 回调与销毁流程使用的原始 CF 句柄；不作为视图依赖。
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    @ObservationIgnored private var hidConnect: io_connect_t = IO_OBJECT_NULL

    @ObservationIgnored weak var healthTicker: HealthTicker?

    /// `settings.hyperKey` 的镜像；各开关实时读取，因此不会失效。
    @ObservationIgnored private var key: HyperKeyPhysicalKey = .none

    // 按住状态机，每次按键都由 tap 回调写入。
    @ObservationIgnored private var hyperActive = false
    @ObservationIgnored private var hyperDownAt: ContinuousClock.Instant?
    @ObservationIgnored private var otherKeyPressed = false
    private let clock = ContinuousClock()
    /// 判定「快速单击」的时长阈值。
    private static let quickPressWindow: Duration = .milliseconds(250)

    // 使用 isolated 销毁，以便释放主 actor 上的 IOKit 连接。
    isolated deinit {
        if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
    }

    /// 绑定设置、应用 Hyper 键配置并开始监听其变化。
    func start(settings: AppSettings) {
        self.settings = settings
        applyKey(settings.hyperKey)
        observeKey()

        // 快速用户切换：丢弃按键中途的状态，并在切回前停止事件改写。
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidResign() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidBecomeActive() }
                }, center: center)
        ]
    }

    /// 在写入落盘前于主线程同步触发，因此任务重新注册监听后再应用变更。
    private func observeKey() {
        withObservationTracking {
            _ = settings?.hyperKey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeKey()
                self.applyKey(self.settings?.hyperKey ?? .none)
            }
        }
    }

    // MARK: - Hyper chord flags

    /// Hyper 按住时按位或入的 flags：通用掩码加上左侧设备位。
    private var hyperFlagsRaw: UInt64 {
        var raw =
            CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            | DeviceFlag.leftControl | DeviceFlag.leftOption | DeviceFlag.leftCommand
        if settings?.hyperKeyIncludesShift ?? true {
            raw |= CGEventFlags.maskShift.rawValue | DeviceFlag.leftShift
        }
        return raw
    }

    /// Hyper 键自身的残留 flag，会从每个被改写的事件上清除。
    private var strippedFlagsRaw: UInt64 {
        if key == .capsLock { return CGEventFlags.maskAlphaShift.rawValue }
        guard let own = key.ownFlag, hyperFlagsRaw & own.rawValue == 0 else { return 0 }
        return own.rawValue | Self.deviceBits(for: own)
    }

    /// 返回某个修饰键 flag 对应的左右设备位。
    private static func deviceBits(for flag: CGEventFlags) -> UInt64 {
        switch flag {
        case .maskControl: return DeviceFlag.leftControl | DeviceFlag.rightControl
        case .maskShift: return DeviceFlag.leftShift | DeviceFlag.rightShift
        case .maskAlternate: return DeviceFlag.leftOption | DeviceFlag.rightOption
        case .maskCommand: return DeviceFlag.leftCommand | DeviceFlag.rightCommand
        default: return 0
        }
    }

    /// F18 与普通功能键一样带有 fn，若 `flagsChanged` 也这样上报会被识别为真实的 fn 按键。
    private static let functionKeyFlagRaw = CGEventFlags.maskSecondaryFn.rawValue

    /// 把 Hyper 和弦并入给定 flags，并清除 Hyper 键自身的残留位。
    private func hyperized(_ flagsRaw: UInt64) -> UInt64 {
        (flagsRaw & ~strippedFlagsRaw) | hyperFlagsRaw
    }

    // MARK: - Event decisions

    /// 根据事件类型与按键判定对其放行、抑制还是改写。
    func decide(
        type: CGEventType, keyCode: Int, flagsRaw: UInt64, isAutorepeat: Bool, isSynthetic: Bool
    ) -> Decision {
        guard !isSynthetic, let tapCode = key.tapKeyCode else { return .pass }

        if keyCode == tapCode {
            return decideHyperKeyEvent(type: type, flagsRaw: flagsRaw, isAutorepeat: isAutorepeat)
        }
        // 重映射生效前该键仍是 Caps Lock，因此走修饰键路径。
        if key == .capsLock, keyCode == kVK_CapsLock, type == .flagsChanged {
            return decideModifierTransition(flagsRaw: flagsRaw, swapKeyCode: true)
        }
        guard hyperActive else { return .pass }
        // Hyper 按住期间任何其他按键或修饰键按下，都说明这是组合键而非单击。
        if type == .keyDown || type == .flagsChanged { otherKeyPressed = true }
        return .rewrite(flags: hyperized(flagsRaw))
    }

    /// 判定 Hyper 键自身按键事件的处理方式。
    private func decideHyperKeyEvent(
        type: CGEventType, flagsRaw: UInt64, isAutorepeat: Bool
    ) -> Decision {
        if key.tapUsesKeyEvents {
            // F18 以 keyDown/keyUp 到达；把两端都转换为 flagsChanged 转换。
            let flagsRaw = flagsRaw & ~Self.functionKeyFlagRaw
            switch type {
            case .keyDown:
                if isAutorepeat { return .suppress }
                if !hyperActive { beginHold() }
                return .rewrite(
                    flags: hyperized(flagsRaw), keyCode: Int64(kVK_Control), asFlagsChanged: true)
            case .keyUp:
                if hyperActive { endHold() }
                return .rewrite(
                    flags: flagsRaw & ~strippedFlagsRaw, keyCode: Int64(kVK_Control),
                    asFlagsChanged: true)
            default:
                return .pass
            }
        }
        guard type == .flagsChanged else { return .pass }
        return decideModifierTransition(flagsRaw: flagsRaw, swapKeyCode: false)
    }

    /// docs/features/hotkeys.md#press-tracking-uses-toggle-semantics
    private func decideModifierTransition(flagsRaw: UInt64, swapKeyCode: Bool) -> Decision {
        let keyCode: Int64? = swapKeyCode ? Int64(kVK_Control) : nil
        if !hyperActive {
            beginHold()
            return .rewrite(flags: hyperized(flagsRaw), keyCode: keyCode)
        }
        endHold()
        return .rewrite(flags: flagsRaw & ~strippedFlagsRaw, keyCode: keyCode)
    }

    // MARK: - Hold state machine

    /// 开始一次 Hyper 按住，记录起始时间。
    private func beginHold() {
        hyperActive = true
        hyperDownAt = clock.now
        otherKeyPressed = false
    }

    /// 结束一次 Hyper 按住；若判定为快速单击则触发对应动作。
    private func endHold() {
        let isQuick =
            !otherKeyPressed && hyperDownAt.map { clock.now - $0 < Self.quickPressWindow } ?? false
        hyperActive = false
        hyperDownAt = nil
        guard isQuick else { return }
        let action = settings?.hyperKeyQuickPress ?? .none
        let key = key
        // 在回调内投递事件或访问 IOKit 有重入风险，因此延后一轮执行。
        Task { @MainActor [weak self] in self?.fireQuickPress(action, for: key) }
    }

    /// 执行快速单击所配置的动作。
    private func fireQuickPress(_ action: HyperKeyQuickPress, for key: HyperKeyPhysicalKey) {
        switch action {
        case .none:
            break
        case .originalKey:
            if key == .capsLock { setCapsLockState(!capsLockState()) }
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        }
    }

    /// 复位按住状态机。
    private func cancelHold() {
        hyperActive = false
        hyperDownAt = nil
        otherKeyPressed = false
    }

    // MARK: - Configuration

    /// 应用新的 Hyper 物理键配置，必要时开关 Caps Lock 的 HID 重映射。
    private func applyKey(_ newKey: HyperKeyPhysicalKey) {
        guard newKey != key else { return }
        cancelHold()
        let wasCapsLock = key == .capsLock
        key = newKey
        if newKey == .capsLock {
            // 重映射会夺走该键原有的功能，因此先解除锁定状态。
            setCapsLockState(false)
            CapsLockRemap.setEnabled(true)
        } else if wasCapsLock {
            CapsLockRemap.setEnabled(false)
        }
        syncTapPresence()
    }

    /// HID 重映射的生命周期长于进程，因此退出前要把按键恢复原状。
    func prepareForTermination() {
        if key == .capsLock { CapsLockRemap.clearBlocking() }
    }

    // MARK: - Tap lifecycle

    /// 根据当前配置决定安装或拆除事件 tap，并同步健康检查订阅。
    private func syncTapPresence() {
        if key == .none {
            tearDownTap()
            healthTicker?.unsubscribe(self)
            status = .off
        } else {
            healthTicker?.subscribe(self)
            installTapIfNeeded()
        }
    }

    /// 尚未安装且已配置按键时创建事件 tap（需要辅助功能权限）。
    private func installTapIfNeeded() {
        guard tapPort == nil, key != .none else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hyperKeyEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // 修改型 tap 需要辅助功能权限；健康检查定时器会重试直到授权。
            status = .needsAccessibility
            return
        }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        status = .active
    }

    /// 移除事件 tap 及其 run loop source。
    private func tearDownTap() {
        cancelHold()
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

    /// 系统禁用 tap 时调用；此时任何记录到一半的按住状态都已失效。
    fileprivate func reenable() {
        cancelHold()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    /// 配置了按键时每秒执行一次的看门狗。参见 docs/features/hotkeys.md#lifecycle。
    func healthCheck() {
        guard key != .none else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            status = .needsAccessibility
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }

    }

    /// 会话失活时复位按住状态并暂停 tap。
    private func sessionDidResign() {
        cancelHold()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
    }

    /// 会话恢复时重新启用或安装 tap。
    private func sessionDidBecomeActive() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        } else {
            installTapIfNeeded()
        }
    }

    // MARK: - Synthetics & caps state

    /// 为 Quick Press 合成一次单独的按键，并打上标记使 `decide` 忽略它。
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            // 会话事件源仍带着我们注入的和弦，而被修饰的 Escape 会被吞掉。
            event?.flags = []
            event?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// 用于读取/设置 Caps Lock 指示灯与锁定状态的 IOHIDSystem 连接。
    private func hidConnection() -> io_connect_t {
        if hidConnect != IO_OBJECT_NULL { return hidConnect }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return IO_OBJECT_NULL }
        var connect: io_connect_t = IO_OBJECT_NULL
        IOServiceOpen(service, machTaskSelf, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        hidConnect = connect
        return connect
    }

    /// 读取 Caps Lock 当前的锁定状态。
    private func capsLockState() -> Bool {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return false }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        return on
    }

    /// 设置 Caps Lock 的锁定状态。
    private func setCapsLockState(_ on: Bool) {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }
}
