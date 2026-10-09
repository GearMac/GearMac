// 文件职责：基于 Carbon 事件热键 API 注册/注销全局快捷键，并把按下/抬起事件回调转发给上层。
// 分层：Service；只负责 Carbon 这一层，具体存在哪些快捷键由 HotKeyManager 决定。
import Carbon.HIToolbox

/// Carbon 热键事件回调：从事件中取出热键 ID，再交给 `HotKeyCenter` 处理。
@MainActor
private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let kind = GetEventKind(event)
    return center.handle(hotKeyID, kind: kind)
}

/// 只封装 Carbon 这一层；具体存在哪些快捷键由 `HotKeyManager` 负责。
@MainActor
final class HotKeyCenter {
    /// 单个已注册热键的注册信息与回调。
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
        let onKeyUp: (() -> Void)?
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    /// 按稳定 id 索引的在用注册项，以及 Carbon 回调所需的反向查找表。
    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5459_4354  // FourCC 签名 "TYCT"

    /// 为 true 时所有热键都处于软注销状态，以便录制器捕获组合键。
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for key in entries.keys {
                if isPaused { deactivate(key) } else { activate(key) }
            }
        }
    }

    /// 以 `id` 注册 `shortcut`，先移除同一 id 的旧注册，避免组合键残留。
    func register(
        id: String, shortcut: KeyShortcut, onKeyDown: @escaping () -> Void,
        onKeyUp: (() -> Void)? = nil
    ) {
        unregister(id: id)
        nextCarbonID += 1
        entries[id] = Entry(
            shortcut: shortcut, onKeyDown: onKeyDown, onKeyUp: onKeyUp,
            carbonID: nextCarbonID, ref: nil)
        idToKey[nextCarbonID] = id
        if !isPaused { activate(id) }
    }

    /// 注销指定 id 的热键，并释放其 Carbon 注册引用。
    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
        idToKey.removeValue(forKey: entry.carbonID)
    }

    /// 将指定 id 的热键真正注册到 Carbon。
    private func activate(_ id: String) {
        guard var entry = entries[id], entry.ref == nil else { return }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(entry.shortcut.carbonKeyCode),
            UInt32(entry.shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: entry.carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // 该组合键可能已被其他 App 占用；此时绑定仍保留可见，但不会触发。
        guard error == noErr, let ref else {
            NSLog("GearMac: could not register hotkey for %@ (OSStatus %d)", id, error)
            return
        }
        entry.ref = ref
        entries[id] = entry
    }

    /// 从 Carbon 注销指定 id 的热键，但保留其条目以便之后恢复。
    private func deactivate(_ id: String) {
        guard var entry = entries[id], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[id] = entry
    }

    /// 按需安装全局热键事件处理器（只会安装一次）。
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(
            dispatcher,
            { @MainActor call, event, userData in
                hotKeyCarbonEventHandler(call, event: event, userData: userData)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    /// 处理 Carbon 热键事件；签名或 id 不匹配时返回「未处理」状态。
    fileprivate func handle(_ hotKeyID: EventHotKeyID, kind: UInt32) -> OSStatus {
        guard
            hotKeyID.signature == signature,
            let key = idToKey[hotKeyID.id],
            let entry = entries[key]
        else { return OSStatus(eventNotHandledErr) }
        if kind == kEventHotKeyPressed {
            entry.onKeyDown()
        } else if kind == kEventHotKeyReleased {
            guard let onKeyUp = entry.onKeyUp else { return OSStatus(eventNotHandledErr) }
            onKeyUp()
        } else {
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
