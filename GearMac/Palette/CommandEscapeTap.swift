// 文件职责：在 HID 事件流头部安装 CGEvent tap，抢在各应用之前接管裸 ⌘⎋ 组合键。
// 分层：Service（AppKit/Carbon）；@MainActor，回调经 `MainActor.assumeIsolated` 回到主线程。
import AppKit
import Carbon.HIToolbox

/// C 回调入口：判定只需对比 key code，因此在这里直接完成而不跨出边界。
private func commandEscapeTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<CommandEscapeTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard
        CommandEscapeTap.isChord(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    else { return Unmanaged.passUnretained(event) }

    let claimed = MainActor.assumeIsolated { tap.fire() }
    return claimed ? nil : Unmanaged.passUnretained(event)
}

/// ⌘⎋ 会在所有应用之前被系统认领，因此调色板要在它进入系统的地方接管。
///
/// 窗口服务器自己绑定了该组合键，所以它不会像 ⌘. 和 ⌘w 那样到达 `onCommandShortcut`：
/// 响应链运行时已经没有按键事件，而头部插入的 HID tap 是更早的唯一位置。参见 docs/features/palette.md。
@MainActor
final class CommandEscapeTap {
    /// 认领该组合键并返回 true；返回 false 则放弃，让系统其余部分继续接收。
    private let onChord: () -> Bool

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onChord: @escaping () -> Bool) {
        self.onChord = onChord
    }

    isolated deinit {
        tearDown()
    }

    /// 仅当是裸 ⌘⎋ 时为 true：再带任何其它修饰键即属于别人的组合键。
    nonisolated static func isChord(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(kVK_Escape)
            && flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                == .maskCommand
    }

    /// 每次显示时调用：因缺少辅助功能权限而被拒的 tap 会在下次重试。
    func enable() {
        guard let port = installIfNeeded() else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func disable() {
        guard let tapPort else { return }
        CGEvent.tapEnable(tap: tapPort, enable: false)
    }

    private func installIfNeeded() -> CFMachPort? {
        if let tapPort { return tapPort }
        // HID 事件流头部：再往后则系统热键已经吃掉了该组合键。
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: commandEscapeTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return nil }
        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return port
    }

    private func tearDown() {
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

    fileprivate func fire() -> Bool {
        onChord()
    }

    /// 系统会禁用它认为过慢的 tap；我们只对比两个整数。
    fileprivate func reenable() {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }
}
