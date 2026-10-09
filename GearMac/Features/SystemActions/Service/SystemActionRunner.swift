// 文件职责：系统动作的统一执行入口，按动作 ID 分派到音量、媒体键、AppleScript、进程命令等具体实现。
// 分层：Service；所有副作用集中在此，异步失败通过 onAsyncFailure 回调，不直接展示 UI。
import AppKit
import CoreAudio
import Darwin

/// 动作成功后的反馈：本地化提示键（可带一个计数参数），以及是否属于无实际变化。
struct SystemActionFeedback: Sendable {
    let key: SystemActionsKey
    /// 需要插入提示文案的计数（如「已推出 N 个磁盘」）；无占位时为 nil。
    let count: Int?
    /// 无实际变化时置为 true，使其读起来是信息提示而不是状态变更。
    let isNoOp: Bool

    init(_ key: SystemActionsKey, count: Int? = nil, isNoOp: Bool = false) {
        self.key = key
        self.count = count
        self.isNoOp = isNoOp
    }

    /// 按指定语言解析提示文案。
    func localizedTitle(_ language: AppLanguage) -> String {
        let format = L10n.string(key, language: language)
        guard let count else { return format }
        return String(format: format, count)
    }
}

/// 系统动作的执行器：所有动作的副作用实现都集中于此，处于主 actor 上。
@MainActor
enum SystemActionRunner {
    /// `run` 返回之后才发生的失败；执行器只负责副作用、不碰 UI，此回调在 `start()` 中设置。
    static var onAsyncFailure: ((SystemAction.ID, SystemActionFailure) -> Void)?

    /// 子进程执行结果：退出码与标准输出/错误。
    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// 执行指定系统动作；返回可选的成功反馈，失败抛出 SystemActionFailure。
    static func run(
        _ id: SystemAction.ID, previousApp: NSRunningApplication?
    ) async throws
        -> SystemActionFeedback?
    {
        switch id {
        case .lockScreen:
            try lockScreen()
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .restart:
            try await runAppleScript("tell application \"System Events\" to restart")
        case .shutDown:
            try await runAppleScript("tell application \"System Events\" to shut down")
        case .logOut:
            try await runAppleScript("tell application \"System Events\" to log out")
        case .showScreenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SystemActionFailure(.failScreenSaverMissing)
            }
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    onAsyncFailure?(
                        .showScreenSaver,
                        SystemActionFailure(text: error.localizedDescription))
                }
            }
        case .playPause:
            try postMediaKey(16)
        case .nextTrack:
            try postMediaKey(17)
        case .previousTrack:
            try postMediaKey(18)
        case .toggleMute:
            try toggleMute()
        case .toggleMicrophoneMute:
            let muted = try await Task.detached {
                try await toggleMicrophoneMute()
            }.value
            return SystemActionFeedback(muted ? .feedbackMicrophoneMuted : .feedbackMicrophoneUnmuted)
        case .volumeUp:
            try stepVolume(up: true)
        case .volumeDown:
            try stepVolume(up: false)
        case .setVolume:
            break  // AppCore 负责取值对话框，并直接调用 setVolume。
        case .volume0:
            try setVolume(0)
        case .volume25:
            try setVolume(0.25)
        case .volume50:
            try setVolume(0.5)
        case .volume75:
            try setVolume(0.75)
        case .volume100:
            try setVolume(1)
        case .showDesktop:
            // 直接执行该二进制会被 SIGKILL；只能通过 LaunchServices 启动。
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["1"]
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                configuration: configuration)
        case .toggleAppearance:
            // 脚本会返回切换后的状态，因此确认提示可以直接点名它。
            let result = try await runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            )
            let dark = result.flag
            return SystemActionFeedback(dark ? .feedbackDarkAppearance : .feedbackLightAppearance)
        case .toggleStageManager:
            let on = try await toggleDefault(
                domain: "com.apple.WindowManager", key: "GloballyEnabled")
            return SystemActionFeedback(on ? .feedbackStageManagerOn : .feedbackStageManagerOff)
        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard NSWorkspace.shared.open(trash) else {
                throw SystemActionFailure(.failTrashOpen)
            }
        case .emptyTrash:
            // 先计数：Finder 对空废纸篓会报错，且 `~/.Trash` 受 TCC 保护。
            let items =
                try await runAppleScript("tell application \"Finder\" to count items of trash")
                .number
            guard items > 0 else {
                return SystemActionFeedback(.feedbackTrashAlreadyEmpty, isNoOp: true)
            }
            try await runAppleScript("tell application \"Finder\" to empty trash")
            return SystemActionFeedback(.feedbackTrashEmptied)
        case .ejectAllDisks:
            let ejected = try ejectAllDisks()
            guard ejected > 0 else {
                return SystemActionFeedback(.feedbackNoDisksToEject, isNoOp: true)
            }
            return SystemActionFeedback(
                ejected == 1 ? .feedbackDiskEjected : .feedbackDisksEjected, count: ejected)
        case .toggleHiddenFiles:
            let shown = try await toggleDefault(
                domain: "com.apple.finder", key: "AppleShowAllFiles")
            let output = try await process("/usr/bin/killall", arguments: ["Finder"])
            if output.status != 0 && output.status != 1 {
                throw processFailure(output, executable: "killall")
            }
            return SystemActionFeedback(shown ? .feedbackHiddenFilesShown : .feedbackHiddenFilesHidden)
        case .hideOtherApps:
            hideOtherApps(except: previousApp)
        case .unhideAllApps:
            let hidden = NSWorkspace.shared.runningApplications.filter(\.isHidden)
            for app in hidden { app.unhide() }
            guard !hidden.isEmpty else {
                return SystemActionFeedback(.feedbackNothingWasHidden, isNoOp: true)
            }
            return SystemActionFeedback(.feedbackAllAppsUnhidden)
        case .quitAllApps:
            for app in AppLauncher.quitAllTargets() { app.terminate() }
        case .dismissNotifications:
            let dismissed = try await dismissNotifications()
            guard dismissed > 0 else {
                return SystemActionFeedback(.feedbackNoNotifications, isNoOp: true)
            }
            return SystemActionFeedback(.feedbackNotificationsDismissed)
        case .toggleBluetooth:
            let on = try await toggleBluetooth()
            return SystemActionFeedback(on ? .feedbackBluetoothOn : .feedbackBluetoothOff)
        }
        return nil
    }

    /// Finder 只在该复选框被改动时才写入该键，因此键不存在时取其默认值：开启。
    static var finderWarnsBeforeEmptyingTrash: Bool {
        let key = "WarnOnEmptyTrash"
        guard let finder = UserDefaults(suiteName: "com.apple.finder"),
            finder.object(forKey: key) != nil
        else { return true }
        return finder.bool(forKey: key)
    }

    /// 读取默认输出设备的当前音量（0...1）。
    static func currentVolume() throws -> Float32 {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        // 没有主控元素时对多声道取平均，使左右声道读作一个音量值。
        var total: Float32 = 0
        for element in elements {
            var address = volumeAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
                throw SystemActionFailure(
                    .failNoSoftwareVolume)
            }
            total += value
        }
        return total / Float32(elements.count)
    }

    /// HUD 渲染所需的状态；没有静音控制时，音量为零即视为静音。
    static func outputState() throws -> (level: Float32, muted: Bool) {
        let level = try currentVolume()
        let device = try defaultOutputDevice()
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else {
            return (level, level == 0)
        }
        return (level, muted != 0)
    }

    /// 设置默认输出设备音量，并在音量大于零时解除静音。
    static func setVolume(_ requested: Float32) throws {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        let value = min(max(requested, 0), 1)
        for element in elements {
            var address = volumeAddress(element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                settable.boolValue
            else {
                throw SystemActionFailure(
                    .failVolumeControlledExternally)
            }
            var applied = value
            let status = AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied)
            guard status == noErr else {
                throw SystemActionFailure(
                    .failVolumeChange, argument: String(status))
            }
        }
        if value > 0 { try? setMuted(false, on: device) }
    }

    /// 优先使用主控元素，没有则使用首选立体声声道的元素。
    private static func volumeElements(on device: AudioDeviceID) throws -> [AudioObjectPropertyElement] {
        var main = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) { return [kAudioObjectPropertyElementMain] }

        var stereoAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        if AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &size, &channels) != noErr {
            channels = (1, 2)
        }
        let elements = [channels.0, channels.1].filter { channel in
            var address = volumeAddress(element: channel)
            return AudioObjectHasProperty(device, &address)
        }
        guard !elements.isEmpty else {
            throw SystemActionFailure(.failNoSoftwareVolume)
        }
        return elements
    }

    /// 构造指定元素的音量属性地址。
    private static func volumeAddress(
        element: AudioObjectPropertyElement
    )
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    /// 输出范围的静音属性地址。
    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// 读取默认输出设备 ID，失败时抛出无法获取输出设备。
    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw SystemActionFailure(.failNoOutputDevice)
        }
        return device
    }

    /// 按档位上下调节音量。
    private static func stepVolume(up: Bool) throws {
        try setVolume(Float32(VolumeLevel.stepped(Double(try currentVolume()), up: up)))
    }

    /// 切换静音；设备没有静音控制时用零音量兜底。
    private static func toggleMute() throws {
        let device = try defaultOutputDevice()
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        {
            try setMuted(muted == 0, on: device)
            return
        }
        // 没有静音控制：把音量压到零，之后再恢复。
        let current = try currentVolume()
        guard current > 0 else {
            try setVolume(lastNonZeroVolume)
            return
        }
        lastNonZeroVolume = current
        try setVolume(0)
    }

    /// 静音兜底方案用于恢复的音量，仅在某次静音把音量降到零时写入。
    private static var lastNonZeroVolume: Float32 = 0.5

    /// 在指定设备上设置静音状态；设备不支持时退化为把音量置零。
    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) throws {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else {
            guard muted else { return }
            let current = try currentVolume()
            if current > 0 { lastNonZeroVolume = current }
            try setVolume(0)
            return
        }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw SystemActionFailure(.failMuteChange, argument: String(status))
        }
    }

    /// 通过私有框架调用立即锁屏。
    private static func lockScreen() throws {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw SystemActionFailure(.failScreenLockUnavailable)
        }
        defer { dlclose(handle) }
        typealias LockScreen = @convention(c) () -> Int32
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            throw SystemActionFailure(.failScreenLockNotExposed)
        }
        _ = unsafeBitCast(symbol, to: LockScreen.self)()
    }

    /// 模拟按下媒体键。
    private static func postMediaKey(_ key: Int32) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                .failAccessibility,
                settings: .accessibility)
        }
        // 与键盘媒体键相同的路径；0xA/0xB 分别表示按下与抬起。
        for state in [0xA, 0xB] {
            let data1 = Int((key << 16) | (Int32(state) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// 隐藏除自身与 previousApp 之外的常规应用，并重新激活 previousApp。
    private static func hideOtherApps(except previousApp: NSRunningApplication?) {
        let ownPID = NSRunningApplication.current.processIdentifier
        let keptPID = previousApp?.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular
            && app.processIdentifier != ownPID
            && app.processIdentifier != keptPID
        {
            app.hide()
        }
        previousApp?.unhide()
        previousApp?.activate()
    }

    /// 推出所有可推出的外置宗卷，返回成功数量，失败时汇总抛出。
    @discardableResult
    private static func ejectAllDisks() throws -> Int {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey
        ]
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let ejectable = urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            guard values.volumeIsLocal != false,
                values.volumeIsInternal != true,
                values.volumeIsRootFileSystem != true
            else { return false }
            // 扩展坞中的固定介质硬盘虽是外置但不可推出，因此「外置」单独也可作为判据。
            return values.volumeIsEjectable == true || values.volumeIsInternal == false
        }
        var failures: [String] = []
        var ejected = 0
        for url in ejectable {
            // 推出一个宗卷会带走整个设备，因此同级宗卷消失即视为已完成。
            guard mountedVolumeExists(url) else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                ejected += 1
            } catch {
                // 报错但已无挂载点的推出，实际上仍成功使该宗卷离线。
                guard mountedVolumeExists(url) else {
                    ejected += 1
                    continue
                }
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw SystemActionFailure(
                text: "Some disks could not be ejected:\n\n" + failures.joined(separator: "\n"))
        }
        return ejected
    }

    /// 判断给定宗卷当前是否仍处于挂载状态。
    private static func mountedVolumeExists(_ url: URL) -> Bool {
        let mounted =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    /// 切换布尔型偏好设置并返回切换后的状态，调用方无需再读一次。
    @discardableResult
    private static func toggleDefault(domain: String, key: String) async throws -> Bool {
        let read = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let normalized = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current: Bool
        if read.status == 0 {
            guard let parsed = booleanDefault(normalized) else {
                throw SystemActionFailure(.failUnexpectedValue)
            }
            current = parsed
        } else if read.stderr.contains("does not exist") {
            // 键不存在确实等同于关闭；其它失败属于状态未知，不做改动。
            current = false
        } else {
            throw processFailure(read, executable: "defaults")
        }
        let requested = !current
        try await runProcess(
            "/usr/bin/defaults",
            arguments: ["write", domain, key, "-bool", requested ? "true" : "false"])
        let verify = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let verified = verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard verify.status == 0, booleanDefault(verified) == requested else {
            throw SystemActionFailure(.failNotSaved)
        }
        return requested
    }

    /// 解析 defaults 命令输出的布尔值，无法识别时返回 nil。
    private static func booleanDefault(_ value: String) -> Bool? {
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    /// 返回关闭的通知数量，使空屏幕也能作为信息展示。
    private static func dismissNotifications() async throws -> Int {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                .failAccessibility,
                settings: .accessibility)
        }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else { return 0 }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var dismissed = 0
        for _ in 0..<100 {
            // 每轮都重建树：关闭一条通知会使其同级节点失效。
            guard let notification = firstNotification(in: root, depth: 0) else { return dismissed }
            guard let action = dismissAction(of: notification) else {
                throw SystemActionFailure(
                    .failNotificationDismissControl)
            }
            let result = AXUIElementPerformAction(notification, action as CFString)
            guard result == .success || result == .invalidUIElement else {
                throw SystemActionFailure(.failNotificationDismiss)
            }
            dismissed += 1
            try await Task.sleep(for: .milliseconds(150))
        }
        throw SystemActionFailure(.failNotificationsRemain)
    }

    /// 依据 AX subrole 匹配，使查找不依赖界面语言。
    private static func firstNotification(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 20 else { return nil }
        let subrole = axString(element, attribute: kAXSubroleAttribute as CFString)?.lowercased()
        if let subrole, subrole.contains("notificationcenter") { return element }
        for child in axChildren(element) {
            if let found = firstNotification(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// 横幅提供 "Close"、通知组提供 "Clear All" 作为自定义动作；两者都没有按钮。
    private static func dismissAction(of notification: AXUIElement) -> String? {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(notification, &actions) == .success,
            let names = actions as? [String]
        else { return nil }
        return names.first { $0.hasPrefix("Name:Close\n") || $0.hasPrefix("Name:Clear All\n") }
    }

    /// 读取指定 AX 元素的子元素列表。
    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success,
            let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    /// 读取指定 AX 元素的字符串属性。
    private static func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// 返回最终稳定到的状态；setter 没有返回值，只能靠轮询确认。
    private static func toggleBluetooth() async throws -> Bool {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw SystemActionFailure(.failBluetoothUnavailable)
        }
        defer { dlclose(handle) }
        typealias Available = @convention(c) () -> Int32
        typealias GetPower = @convention(c) () -> Int32
        typealias SetPower = @convention(c) (Int32) -> Void
        guard let availableSymbol = dlsym(handle, "IOBluetoothPreferencesAvailable"),
            let getSymbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
            let setSymbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { throw SystemActionFailure(.failBluetoothNotExposed) }
        let available = unsafeBitCast(availableSymbol, to: Available.self)
        let getPower = unsafeBitCast(getSymbol, to: GetPower.self)
        let setPower = unsafeBitCast(setSymbol, to: SetPower.self)
        guard available() != 0 else {
            throw SystemActionFailure(.failNoBluetoothController, settings: .bluetooth)
        }
        let requested: Int32 = getPower() == 0 ? 1 : 0
        setPower(requested)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if getPower() == requested { return requested == 1 }
        }
        throw SystemActionFailure(
            .failBluetoothNoChange,
            settings: .bluetooth)
    }

    /// `NSAppleEventDescriptor` 不是 `Sendable`，因此只把调用方需要读取的两个字段跨线程传递。
    private struct AppleScriptResult: Sendable {
        let number: Int32
        let flag: Bool
    }

    /// 冷启动的 Finder 需要数秒才响应，因此发送动作不在主 actor 上执行。
    @discardableResult
    private static func runAppleScript(_ source: String) async throws -> AppleScriptResult {
        try await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else {
                throw SystemActionFailure(.failAutomationPrepare)
            }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            guard let errorInfo else {
                return AppleScriptResult(number: result.int32Value, flag: result.booleanValue)
            }
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            if number == -1743 {
                throw SystemActionFailure(.failAutomationPermission, settings: .automation)
            }
            let detail =
                errorInfo[NSAppleScript.errorMessage] as? String
                ?? L10n.string(SystemActionsKey.failAutomationUnknown, language: .english)
            throw SystemActionFailure(text: detail)
        }.value
    }

    /// 运行进程并在退出码非零时抛出 SystemActionFailure。
    private static func runProcess(_ executable: String, arguments: [String]) async throws {
        let output = try await process(executable, arguments: arguments)
        guard output.status == 0 else { throw processFailure(output, executable: executable) }
    }

    /// 在后台 task 中运行进程，返回退出码与标准输出/错误。
    private static func process(_ executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.runObservingExit().wait() } catch {
                throw SystemActionFailure(
                    text:
                        "\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)"
                )
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errorData, encoding: .utf8) ?? "")
        }.value
    }

    /// 把子进程输出转换为面向用户的失败信息。
    private static func processFailure(_ output: ProcessOutput, executable: String) -> SystemActionFailure {
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return SystemActionFailure(
            text: detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
    }
}
