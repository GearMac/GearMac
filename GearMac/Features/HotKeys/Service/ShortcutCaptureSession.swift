// 文件职责：为当前唯一进行中的录制安装本地事件监视器，捕获用户按下的组合键或纯修饰键手势并提交绑定。
// 分层：Service；仅在录制期间存在，停止时必须拆除全部监视器与观察者。
import AppKit
import Carbon.HIToolbox

/// 为唯一进行中的录制提供本地事件监视器。参见 docs/features/hotkeys.md#recorder。
@MainActor
@Observable
final class ShortcutCaptureSession {
    /// 一次被拒绝的绑定及其当前占用者。
    struct Conflict: Equatable {
        let binding: HotKeyBinding
        let owner: String
    }

    /// 当前按住的修饰键（不含 fn）。
    private(set) var heldModifiers: NSEvent.ModifierFlags = []
    /// Globe 键是否按下。
    private(set) var heldGlobe = false
    /// 当前按住的单个修饰键。
    private(set) var heldModifier: ModifierKey?
    /// 等待第二次点按的修饰键。
    private(set) var awaitingSecondModifier: ModifierKey?
    /// 最近一次冲突提示，超时后自动清除。
    private(set) var conflict: Conflict?

    /// 冲突提示的停留时长。
    private static let conflictDwell: Duration = .seconds(1.5)

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?
    @ObservationIgnored private var modifierCommit: Task<Void, Never>?
    @ObservationIgnored private weak var activeRecorderView: NSView?
    /// 与全局监视器使用同一个识别器，因此录制无需事件 tap，也无需权限授权。
    @ObservationIgnored private var detector = ModifierKeyDetector()

    /// 开始为指定动作录制，安装本地事件监视器。
    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        _ = detector.handle(
            ModifierKey.held(in: UInt64(NSEvent.modifierFlags.rawValue), globeDown: false),
            at: ProcessInfo.processInfo.systemUptime)
        detector.cancel()

        // 早于 actor 标注的主线程处理闭包；只让 Sendable 的部分跨入。
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, action: action,
                        hotKeys: hotKeys)
                }
                return nil  // 始终吞掉事件：不会发出提示音，也不会把按键泄漏给窗口
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self, weak hotKeys] event in
                let all = event.modifierFlags
                let keyCode = Int(event.keyCode)
                let flags = all.intersection([.command, .option, .control, .shift])
                let timestamp = event.timestamp
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = flags
                    if keyCode == kVK_Function { self.heldGlobe = all.contains(.function) }
                    guard let hotKeys else { return }
                    self.handleModifiers(
                        all.rawValue,
                        at: timestamp, action: action,
                        hotKeys: hotKeys)
                }
                return event
            })
        {
            monitors.append(monitor)
        }

        // 点击会先结束录制再继续传递，因此一次点击可以转移到另一行。
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { @MainActor [weak self, weak hotKeys] event in
                guard self?.activeRecorderContains(event) != true else { return event }
                hotKeys?.recordingAction = nil
                return event
            })
        {
            monitors.append(monitor)
        }

        // 窗口失去 key 状态后本地监视器会静默，因此将其视为取消并解除暂停。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
        }
    }

    /// 停止录制并拆除全部监视器、观察者与待定任务。
    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        conflictReset?.cancel()
        conflictReset = nil
        cancelModifierCommit()
        conflict = nil
        heldModifiers = []
        heldGlobe = false
        heldModifier = nil
        detector.reset()
        activeRecorderView = nil
    }

    /// 记录当前录制器视图，用于区分点击是否落在录制区域内。
    func setActiveRecorderView(_ view: NSView) {
        activeRecorderView = view
    }

    /// 清除录制器视图引用（仅当与传入视图一致时）。
    func clearActiveRecorderView(_ view: NSView) {
        if activeRecorderView === view { activeRecorderView = nil }
    }

    /// 判断事件是否发生在当前录制器视图范围内。
    private func activeRecorderContains(_ event: NSEvent) -> Bool {
        guard let view = activeRecorderView, event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    /// 处理本地 keyDown：解析组合键、处理 Esc/Delete，并提交绑定。
    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        // 一旦有按键按下，当时按住的修饰键就属于组合键的一部分，而不是纯修饰键点按。
        detector.cancel()
        cancelModifierCommit()

        // 功能键也会带 `.function`；只有真正按下物理 Globe 键才算作修饰键。
        let flags = heldGlobe ? flags.union(.function) : flags.subtracting(.function)
        let bareKey = flags.isDisjoint(with: [.command, .option, .control, .shift, .function])

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        // 单独的 Delete 会清除已有绑定。
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setBinding(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        // 不是可绑定的组合键（例如单独一个字母）：吞掉该事件并继续录制。
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }
        commit(.combo(shortcut), action: action, hotKeys: hotKeys)
    }

    /// 处理本地 flagsChanged：识别纯修饰键点按手势并提交绑定。
    private func handleModifiers(
        _ flags: UInt, at timestamp: TimeInterval,
        action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let keys = ModifierKey.held(in: UInt64(flags), globeDown: heldGlobe)
        heldModifier = keys.count == 1 ? keys.first : nil
        guard let event = detector.handle(keys, at: timestamp) else { return }
        switch event {
        case .pressed(let key):
            if key != awaitingSecondModifier { cancelModifierCommit() }
        case .released(let key, let doubleTap, let held):
            cancelModifierCommit()
            if doubleTap || held {
                commit(
                    doubleTap ? key.doubleBinding : key.singleBinding,
                    action: action, hotKeys: hotKeys)
                return
            }
            awaitingSecondModifier = key
            modifierCommit = Task { [weak self, weak hotKeys] in
                try? await Task.sleep(for: ModifierKeyDetector.resolutionWindow)
                guard !Task.isCancelled, let self, let hotKeys else { return }
                modifierCommit = nil
                awaitingSecondModifier = nil
                commit(key.singleBinding, action: action, hotKeys: hotKeys)
            }
        case .cancelled:
            cancelModifierCommit()
        }
    }

    /// 取消待定的修饰键提交并清除等待状态。
    private func cancelModifierCommit() {
        modifierCommit?.cancel()
        modifierCommit = nil
        awaitingSecondModifier = nil
    }

    /// 校验冲突后写入绑定并结束录制。
    private func commit(_ binding: HotKeyBinding, action: HotKeyAction, hotKeys: HotKeyManager) {
        if let owner = hotKeys.conflictOwner(of: binding, excluding: action) {
            flashConflict(Conflict(binding: binding, owner: owner))
            return
        }
        hotKeys.setBinding(binding, for: action)
        hotKeys.recordingAction = nil
    }

    /// 显示冲突提示，并在停留时间后自动清除。
    private func flashConflict(_ rejected: Conflict) {
        conflict = rejected
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: Self.conflictDwell)
            guard !Task.isCancelled else { return }
            self?.conflict = nil
        }
    }
}
