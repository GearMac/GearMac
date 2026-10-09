// 文件职责：集中管理全部快捷键绑定：持久化、向 Carbon 与修饰键监听两套引擎注册、冲突检测与动作分发。
// 分层：Service；绑定状态的唯一来源，`revision` 变化代表索引缓存失效。
import Foundation

/// 掌管所有绑定：持久化、向两套引擎注册、冲突检测与动作分发。
@MainActor
@Observable
final class HotKeyManager {
    /// 切换启动器面板的显示/隐藏。
    var onTogglePalette: (() -> Void)?
    /// 听写按键按下时的回调。
    var onDictationPressed: (() -> Void)?
    /// 听写按键抬起时的回调。
    var onDictationReleased: (() -> Void)?
    /// 听写被取消时的回调。
    var onDictationCancelled: (() -> Void)?
    var dictationEnabled = false {
        didSet {
            guard dictationEnabled != oldValue else { return }
            if !dictationEnabled { onDictationCancelled?() }
            syncModifierTaps()
        }
    }
    var dictationHoldToTalk = false {
        didSet {
            guard dictationHoldToTalk != oldValue else { return }
            onDictationCancelled?()
            syncModifierTaps()
        }
    }
    /// 启动器自身的命令入口，使快捷键与面板行执行的是同一条路径。
    var onRunCommand: ((CommandID) -> Void)?
    /// 运行自定义命令。
    var onRunCustomCommand: ((UUID) -> Void)?
    /// 运行系统动作。
    var onRunSystemAction: ((SystemAction.ID) -> Void)?
    /// 运行窗口命令。
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    /// 应用窗口布局。
    var onRunWindowLayout: ((UUID) -> Void)?
    /// 进入窗口房间（Room）。
    var onEnterRoom: ((UUID) -> Void)?
    /// 应用自定义窗口尺寸。
    var onRunCustomWindowSize: ((UUID) -> Void)?
    /// 打开快捷链接。
    var onOpenQuicklink: ((UUID) -> Void)?
    /// 运行快捷操作。
    var onRunQuickAction: ((UUID) -> Void)?
    /// 运行 Apple 快捷指令。
    var onRunAppleShortcut: ((UUID) -> Void)?
    /// 展开文本片段。
    var onExpandSnippet: ((StoredSnippet.ID) -> Void)?
    /// 运行扩展命令。
    var onRunExtensionCommand: ((String) -> Void)?
    /// 为只有各存储才知道的对象取显示名；固定目录在这里解析。在 `AppCore.start()` 中赋值。
    var displayName: ((HotKeyAction) -> String?)?
    /// 该动作所属的启动器分类是否已开启。在 `AppCore.start()` 中赋值。
    var allowsAction: ((HotKeyAction) -> Bool)?

    /// 当前正在录制的动作；录制期间会同时暂停两套引擎。
    var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            let recording = recordingAction != nil
            if recording, dictationEnabled, dictationHoldToTalk { onDictationCancelled?() }
            center.isPaused = recording
            modifierTapMonitor.isPaused = recording
            if let recordingAction {
                capture.start(action: recordingAction, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    let modifierTapMonitor = ModifierTapMonitor()
    /// 打开的录制器的实时状态，供其 callout 读取。
    let capture = ShortcutCaptureSession()

    private let center = HotKeyCenter()
    private var modifierTaps: [HotKeyBinding: HotKeyAction] = [:]
    /// 全部绑定，在 `start()` 中一次性载入，变更时直接写回。
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    /// 作为 `AppIndex` 缓存键的一部分：已绑定的条目会从启动器 Suggestions 中移除。
    private(set) var revision = 0
    @ObservationIgnored private var candidateActionsCache: [HotKeyAction]?
    // 复用同一实例：启动加载时每个候选动作只解码一次。
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCustomCommandKey = "boundCustomCommandIDs"
    private let boundQuicklinkKey = "boundQuicklinkIDs"
    private let boundQuickActionKey = "boundQuickActionIDs"
    private let boundWindowLayoutKey = "boundWindowLayoutIDs"
    private let boundWindowRoomKey = "boundWindowRoomIDs"
    private let boundCustomWindowSizeKey = "boundCustomWindowSizeIDs"
    private let boundAppleShortcutKey = "boundAppleShortcutIDs"
    private let boundSnippetKey = "boundSnippetIDs"
    private let boundExtensionCommandKey = "boundExtensionCommandEntryIDs"

    /// 启动时载入绑定、清理失效记录、注册热键并启动修饰键监听。
    func start(
        customCommandIDs: Set<UUID>, quicklinkIDs: Set<UUID>, windowLayoutIDs: Set<UUID>,
        windowRoomIDs: Set<UUID>, customWindowSizeIDs: Set<UUID>, quickActionIDs: Set<UUID>
    ) {
        prune(key: boundCustomCommandKey, live: customCommandIDs) { .customCommand(id: $0) }
        prune(key: boundQuicklinkKey, live: quicklinkIDs) { .quicklink(id: $0) }
        prune(key: boundWindowLayoutKey, live: windowLayoutIDs) { .windowLayout(id: $0) }
        prune(key: boundWindowRoomKey, live: windowRoomIDs) { .windowRoom(id: $0) }
        prune(key: boundCustomWindowSizeKey, live: customWindowSizeIDs) {
            .customWindowSize(id: $0)
        }
        prune(key: boundQuickActionKey, live: quickActionIDs) { .quickAction(id: $0) }
        // 放在 prune 之后，避免已删除的记录在本会话内存中残留。
        for action in candidateActions { bindings[action] = storedBinding(for: action) }
        revision &+= 1

        // `register` 对未绑定的项是空操作，因此固定目录不需要自己的索引。
        for action in candidateActions { register(action) }

        modifierTapMonitor.onTrigger = { [weak self] binding in
            guard let self, let action = modifierTaps[binding] else { return }
            perform(action)
        }
        modifierTapMonitor.onHoldPressed = { [weak self] in self?.perform(.dictation) }
        modifierTapMonitor.onHoldReleased = { [weak self] in self?.onDictationReleased?() }
        modifierTapMonitor.onHoldCancelled = { [weak self] in self?.onDictationCancelled?() }
        modifierTapMonitor.start()
        syncModifierTaps()
    }

    /// 启动时不做 prune：那时「尚未安装」与「已被删除」无法区分。
    var boundExtensionCommandEntryIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundExtensionCommandKey) ?? []
    }

    /// 持有按 App 快捷键的 bundle ID，供 `start()` 判断需要加载哪些记录。
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// 绑定了快捷键的设置面板 bundle ID——作用同 `boundBundleIDs`，使用独立命名空间。
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    /// 已绑定快捷键的自定义命令 UUID，单独建索引以便启动时重新注册。
    var boundCustomCommandIDs: [UUID] { boundIDs(key: boundCustomCommandKey) }

    /// 已绑定的 Quicklink UUID——同一套索引机制，独立命名空间。
    var boundQuicklinkIDs: [UUID] { boundIDs(key: boundQuicklinkKey) }

    /// 已绑定的窗口布局 UUID；属于用户自建记录，因此需要独立索引。
    var boundWindowLayoutIDs: [UUID] { boundIDs(key: boundWindowLayoutKey) }

    /// 已绑定的窗口房间（Room）UUID 索引。
    var boundWindowRoomIDs: [UUID] { boundIDs(key: boundWindowRoomKey) }

    /// 已绑定的自定义窗口尺寸 UUID 索引。
    var boundCustomWindowSizeIDs: [UUID] { boundIDs(key: boundCustomWindowSizeKey) }

    /// 已绑定的快捷操作（Quick Action）UUID 索引。
    var boundQuickActionIDs: [UUID] { boundIDs(key: boundQuickActionKey) }

    /// 由 `AppleShortcutCoordinator` 在成功读取后清理，启动时不在这里处理。
    var boundAppleShortcutIDs: [UUID] { boundIDs(key: boundAppleShortcutKey) }

    /// 每次加载由 `removeSnippetBindings` 清扫，启动时不处理：片段存储可能处于关闭状态。
    var boundSnippetIDs: [StoredSnippet.ID] {
        UserDefaults.standard.stringArray(forKey: boundSnippetKey) ?? []
    }

    /// App 被删除时其设置行也会一起消失，因此没有其他时机能清理它的绑定。
    func removeAppBindings(where isUninstalled: (String) -> Bool) {
        for bundleID in boundBundleIDs where isUninstalled(bundleID) {
            let action = HotKeyAction.app(bundleID: bundleID)
            if recordingAction == action { recordingAction = nil }
            setBinding(nil, for: action)
        }
    }

    /// 覆盖在 GearMac 之外被删除或重命名的文件，这类情况没有设置行可以清理。
    func removeSnippetBindings(keeping liveIDs: Set<StoredSnippet.ID>) {
        for id in boundSnippetIDs where !liveIDs.contains(id) {
            let action = HotKeyAction.snippet(id: id)
            if recordingAction == action { recordingAction = nil }
            setBinding(nil, for: action)
        }
    }

    /// 返回某动作当前的绑定，未绑定则为 nil。
    func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action] }

    /// 从 UserDefaults 读取并解码某动作已存储的绑定。
    private func storedBinding(for action: HotKeyAction) -> HotKeyBinding? {
        // 存储值是 JSON 字符串；其他任何情况都视为未绑定。
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(HotKeyBinding.self, from: data)
    }

    /// 持久化或清除绑定，并同步替换实时注册。
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        if action == .dictation, binding != self.binding(for: action) { onDictationCancelled?() }
        let previous = bindings[action]
        if let binding,
            let data = try? encoder.encode(binding),
            let json = String(data: data, encoding: .utf8)
        {
            bindings[action] = binding
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
        } else {
            bindings[action] = nil
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        revision &+= 1
        // 无条件注销：之前的绑定可能是一个组合键。
        center.unregister(id: action.defaultsKey)
        register(action)

        switch action {
        case .app(let bundleID):
            index(bundleID, bound: binding != nil, key: boundKey)
        case .settingsPane(let bundleID):
            index(bundleID, bound: binding != nil, key: boundPaneKey)
        case .customCommand(let id):
            index(id, bound: binding != nil, key: boundCustomCommandKey)
        case .quicklink(let id):
            index(id, bound: binding != nil, key: boundQuicklinkKey)
        case .quickAction(let id):
            index(id, bound: binding != nil, key: boundQuickActionKey)
        case .windowLayout(let id):
            index(id, bound: binding != nil, key: boundWindowLayoutKey)
        case .windowRoom(let id):
            index(id, bound: binding != nil, key: boundWindowRoomKey)
        case .customWindowSize(let id):
            index(id, bound: binding != nil, key: boundCustomWindowSizeKey)
        case .appleShortcut(let id):
            index(id, bound: binding != nil, key: boundAppleShortcutKey)
        case .snippet(let id):
            index(id, bound: binding != nil, key: boundSnippetKey)
        case .extensionCommand(let entryID):
            index(entryID, bound: binding != nil, key: boundExtensionCommandKey)
        case .togglePalette, .dictation, .command, .systemAction, .windowCommand:
            break
        }
        candidateActionsCache = nil
        // 重建会遍历所有候选；只有纯修饰键绑定才会影响这张映射。
        if previous?.usesModifierTapMonitor == true || binding?.usesModifierTapMonitor == true {
            syncModifierTaps()
        }
    }

    /// 是否包含 Shift 会改变和弦定义，而已存储的组合键里写入的是旧定义。
    func retargetHyperBindings(includesShift: Bool) {
        for action in candidateActions {
            guard let shortcut = bindings[action]?.shortcut else { continue }
            let retargeted = shortcut.retargetingHyper(includesShift: includesShift)
            guard retargeted != shortcut else { continue }
            let binding = HotKeyBinding.combo(retargeted)
            // 遇到冲突就跳过而不是覆盖：第二次注册会静默失败。
            guard conflictOwner(of: binding, excluding: action) == nil else { continue }
            setBinding(binding, for: action)
        }
    }

    /// 按住模式会在两种点按手势之间占用其物理修饰键。
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions where candidate != action {
            guard let other = self.binding(for: candidate) else { continue }
            let holdsModifier =
                dictationHoldToTalk
                && (action == .dictation && binding.holdKey != nil
                    || candidate == .dictation && other.holdKey != nil)
            if binding.conflicts(with: other, holdsModifier: holdsModifier) {
                return displayName(of: candidate)
            }
        }
        return nil
    }

    /// 所有可能持有绑定的动作：冲突检测与映射遍历的搜索空间。
    private var candidateActions: [HotKeyAction] {
        if let candidateActionsCache { return candidateActionsCache }
        var actions = HotKeyAction.builtInActions
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCustomCommandIDs.map { .customCommand(id: $0) }
        actions += boundQuicklinkIDs.map { .quicklink(id: $0) }
        actions += boundQuickActionIDs.map { .quickAction(id: $0) }
        actions += boundWindowLayoutIDs.map { .windowLayout(id: $0) }
        actions += boundWindowRoomIDs.map { .windowRoom(id: $0) }
        actions += boundCustomWindowSizeIDs.map { .customWindowSize(id: $0) }
        actions += boundAppleShortcutIDs.map { .appleShortcut(id: $0) }
        actions += boundSnippetIDs.map { .snippet(id: $0) }
        actions += boundExtensionCommandEntryIDs.map { .extensionCommand(entryID: $0) }
        actions += SystemAction.ID.allCases.map { .systemAction(id: $0) }
        actions += WindowCommand.ID.allCases.map { .windowCommand(id: $0) }
        candidateActionsCache = actions
        return actions
    }

    /// 返回动作的显示名，用于冲突提示。
    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .dictation:
            return "Dictation"
        case .command(let id):
            return id.name
        case .app(let bundleID), .settingsPane(let bundleID):
            return displayName?(action) ?? bundleID
        case .customCommand:
            return displayName?(action) ?? "Custom Command"
        case .systemAction(let id):
            return SystemActionCatalog.action(id: id).name
        case .windowCommand(let id):
            return WindowCommandCatalog.command(id: id)?.name ?? "Window Command"
        case .windowLayout:
            return displayName?(action) ?? "Window Layout"
        case .windowRoom:
            return displayName?(action) ?? "Room"
        case .customWindowSize:
            return displayName?(action) ?? "Custom Size"
        case .quicklink:
            return displayName?(action) ?? "Quicklink"
        case .quickAction:
            return displayName?(action) ?? "Quick Action"
        case .appleShortcut:
            return displayName?(action) ?? "Apple Shortcut"
        case .snippet:
            return displayName?(action) ?? "Snippet"
        case .extensionCommand:
            return displayName?(action) ?? "Extension Command"
        }
    }

    /// 把组合键交给 Carbon；纯修饰键绑定不做逐个动作的注册。
    private func register(_ action: HotKeyAction) {
        guard let shortcut = binding(for: action)?.shortcut else { return }
        center.register(
            id: action.defaultsKey, shortcut: shortcut,
            onKeyDown: { [weak self] in self?.perform(action) },
            onKeyUp: action == .dictation ? { [weak self] in self?.onDictationReleased?() } : nil)
    }

    /// 整体重建，避免映射与磁盘上的内容产生偏差。
    private func syncModifierTaps() {
        modifierTaps = [:]
        let dictationBinding = binding(for: .dictation)
        let holdKey = dictationHoldToTalk ? dictationBinding?.holdKey : nil
        for action in candidateActions {
            guard let binding = binding(for: action), binding.usesModifierTapMonitor else { continue }
            if action == .dictation, !dictationEnabled { continue }
            if action == .dictation, dictationHoldToTalk {
                guard holdKey != nil, conflictOwner(of: binding, excluding: action) == nil else {
                    continue
                }
            }
            modifierTaps[binding] = action
        }
        modifierTapMonitor.update(
            bound: Set(modifierTaps.keys),
            holdKey: dictationBinding.flatMap { modifierTaps[$0] == .dictation ? holdKey : nil })
    }

    /// 执行动作对应的命令入口（受分类开关约束）。
    private func perform(_ action: HotKeyAction) {
        // 分类开关；与各功能开关各自守护自身入口的方式一致。
        guard allowsAction?(action) ?? true else { return }
        switch action {
        case .togglePalette: onTogglePalette?()
        case .dictation: onDictationPressed?()
        case .command(let id): onRunCommand?(id)
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        case .systemAction(let id): onRunSystemAction?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        case .windowLayout(let id): onRunWindowLayout?(id)
        case .windowRoom(let id): onEnterRoom?(id)
        case .customWindowSize(let id): onRunCustomWindowSize?(id)
        case .quicklink(let id): onOpenQuicklink?(id)
        case .quickAction(let id): onRunQuickAction?(id)
        case .appleShortcut(let id): onRunAppleShortcut?(id)
        case .snippet(let id): onExpandSnippet?(id)
        case .extensionCommand(let entryID): onRunExtensionCommand?(entryID)
        }
    }

    // MARK: - UUID-keyed indexes

    /// 读取 UserDefaults 中存储的 UUID 字符串数组。
    private func boundIDs(key: String) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    /// 更新 UUID 类型的绑定索引。
    private func index(_ id: UUID, bound: Bool, key: String) {
        var set = Set(boundIDs(key: key))
        if bound { set.insert(id) } else { set.remove(id) }
        persist(set, key: key)
    }

    /// 更新字符串类型（如 bundle ID、entry ID）的绑定索引。
    private func index(_ id: String, bound: Bool, key: String) {
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if bound { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// 清除对应项已消失（在 GearMac 未运行时被删除）的绑定。
    private func prune(key: String, live: Set<UUID>, action: (UUID) -> HotKeyAction) {
        let stored = Set(boundIDs(key: key))
        for id in stored.subtracting(live) {
            UserDefaults.standard.removeObject(forKey: action(id).defaultsKey)
        }
        persist(stored.intersection(live), key: key)
    }

    /// 以排序后的 UUID 字符串数组写回索引。
    private func persist(_ ids: Set<UUID>, key: String) {
        UserDefaults.standard.set(ids.map { $0.uuidString.lowercased() }.sorted(), forKey: key)
    }
}
