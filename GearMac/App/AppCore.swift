// 文件职责：应用级核心容器，独占持有并组装所有长期存活的 store、manager 与 coordinator，并统一驱动启动、功能开关重投影与退出清理。
// 分层：App/Core（协调层）；集中做依赖装配与生命周期编排，不直接实现各功能的具体逻辑。
import AppKit

/// 所有长期存活 manager 的唯一持有者；由 app delegate 在启动时一次性完成装配。
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let quicklinks = QuicklinkStore()
    let windowLayouts = WindowLayoutStore()
    let customWindowSizes = CustomWindowSizeStore()
    let rooms = RoomStore()
    let roomMinimums = RoomMinimumSizeStore()
    let roomParking = RoomParkingLedger(
        fileURL: AppPaths.applicationSupport().appendingPathComponent("room-parking.json"))
    let roomSession = RoomSession()
    let clipboardStore = ClipboardStore()
    @ObservationIgnored private var clipboardTextIndexer: ClipboardTextIndexer?
    let clipboardManager: ClipboardManager
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(
        syntheticEventTag: Paster.gearmacEventTag)
    let textInjector: TextInjector
    let hotKeys = HotKeyManager()
    let dictationAudioDucker = DictationAudioDucker()
    @ObservationIgnored private(set) lazy var dictationModels =
        DictationModelStore(idleRelease: settings.dictationIdleRelease)
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let spaceSwitcher = SpaceSwitcher()
    let inputSourceSwitcher = InputSourceSwitcher()
    let settings: AppSettings
    /// 把设置镜像写入 settings.json；当 Backup 面板的开关关闭时为 nil。
    @ObservationIgnored private var settingsFile: SettingsFileRepository?
    /// 该文件中的启动器条目，保留下来以便对应 app 安装后应用处于等待状态的记录。
    @ObservationIgnored private var launcherSettingsFile: LauncherSettingsFile?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    /// `trackChatRoute` 最近一次采纳的判定结果；在读到第一个结果前为 nil。
    @ObservationIgnored private var chatsRunTheirOwnTools: Bool?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let fallbacks = FallbackStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let regionNumberFormat = RegionNumberFormatMonitor()
    let calendarStore = CalendarStore()
    let meetingClock = MeetingClock()
    let updateChecker = UpdateCheckStore()
    let supportReminders: SupportReminderStore
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let pinnedEmoji = PinnedEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let fileSearch = FileSearchSession()
    let dictionary = DictionarySession()
    let menuSearch = MenuSearchSession()
    let windowSwitch = WindowSwitchSession()
    let activationPolicy = ActivationPolicy()
    let uninstall = UninstallSession()
    let notesStore: NotesStore
    let extensions: ExtensionManager
    let chatHistory: ChatHistoryStore
    let aiChats: AIChatSurfacesState
    let aiSettings = AISettingsStore(
        environmentStore: .keychain,
        isAppleIntelligenceAvailable: { AppleIntelligenceProvider.status().isAvailable })
    let mcpSettings = MCPSettingsStore()
    let mcpOAuth = MCPOAuthManager()
    @ObservationIgnored private(set) lazy var mcp = MCPServerManager(oauth: mcpOAuth)
    let quickActionSettings = QuickActionSettingsStore()
    let customQuickActions = CustomQuickActionStore()
    let chatGPTSubscription = ChatGPTSubscriptionManager()
    let installedAI = InstalledAIManager()
    @ObservationIgnored private var appliedLaunchRevisions: [InstalledAIKind: Int] = [:]

    /// 当快速链接编辑器需要随「设置」一起打开时置位；由对应面板消费。
    var pendingQuicklinkEdit: QuicklinkEditRequest?
    /// 当片段编辑器需要随「设置」一起打开时置位；由对应面板消费。
    var pendingSnippetEdit: SnippetEditRequest?
    /// 当窗口布局编辑器需要随「设置」一起打开时置位；由对应面板消费。
    var pendingWindowLayoutEdit: WindowLayoutEditRequest?

    @ObservationIgnored private(set) lazy var snippetCoordinator = SnippetCoordinator(
        store: snippetsStore, listener: snippetListener, injector: textInjector,
        clipboardStore: clipboardStore, appIndex: appIndex, settings: settings,
        windowController: windowController, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        showMessage: { [unowned self] in self.showMessage($0, tone: $1) }, core: self)
    @ObservationIgnored private(set) lazy var dictationCoordinator = DictationCoordinator(
        settings: settings, hotKeys: hotKeys, models: dictationModels, injector: textInjector,
        audioDucker: dictationAudioDucker,
        confirmEnable: { [unowned self] in
            await self.confirm(
                title: "Enable Dictation?",
                message: "GearMac needs microphone access for dictation and Accessibility to paste into "
                    + "other apps. Audio is processed on this Mac.",
                symbol: "waveform", confirmTitle: "Continue", tone: .neutral,
                confirmRole: .standard)
        },
        showMessage: { [unowned self] in self.showMessage($0, tone: $1) })
    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks, settings: settings,
        appIndex: appIndex, injector: textInjector, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        windowController: windowController,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        clipboardHistory: { [unowned self] in self.snippetCoordinator.clipboardHistoryForExpansion() },
        core: self)

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        fileSearch: fileSearch, menuSearch: menuSearch, windowSwitch: windowSwitch,
        windowController: windowController)
    /// 拥有自己的窗口与生命周期：两个 coordinator 都不会显示或关闭对方的面板。
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(
        core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var extensionCoordinator = ExtensionCoordinator(
        extensions: extensions, palette: palette, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover,
        spaceSwitcher: spaceSwitcher, customSizes: customWindowSizes)
    @ObservationIgnored private(set) lazy var customWindowSizeCoordinator =
        CustomWindowSizeCoordinator(
            store: customWindowSizes, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
            favorites: favorites, visibility: visibility, ranking: launcherRanking,
            aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowShortcutPresetCoordinator =
        WindowShortcutPresetCoordinator(hotKeys: hotKeys, core: self)
    @ObservationIgnored private(set) lazy var windowLayoutCoordinator = WindowLayoutCoordinator(
        store: windowLayouts, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var roomCoordinator = RoomCoordinator(
        store: rooms, minimums: roomMinimums, ledger: roomParking, session: roomSession,
        settings: settings, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, settings: settings, appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        hotKeys: hotKeys, favorites: favorites, visibility: visibility,
        ranking: launcherRanking, aliases: aliases, activationPolicy: activationPolicy, core: self)
    @ObservationIgnored private(set) lazy var appleShortcutCoordinator = AppleShortcutCoordinator(
        settings: settings, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    /// 属于窗口状态而非用户偏好：与「当前笔记文件名」一样存放在 `UserDefaults` 中。
    private nonisolated static let noteFormattingBarKey = "notesFormattingBarExpanded"
    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        appIndex: appIndex,
        core: self,
        isFormattingBarExpanded: UserDefaults.standard.bool(forKey: Self.noteFormattingBarKey),
        saveFormattingBarExpanded: {
            UserDefaults.standard.set($0, forKey: Self.noteFormattingBarKey)
        })

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        customCommandCoordinator: customCommandCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        quicklinkCoordinator: quicklinkCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        windowLayoutCoordinator: windowLayoutCoordinator,
        snippetCoordinator: snippetCoordinator, fileSearchCoordinator: fileSearchCoordinator,
        menuSearchCoordinator: menuSearchCoordinator,
        windowSwitchCoordinator: windowSwitchCoordinator,
        notesCoordinator: notesCoordinator, extensionCoordinator: extensionCoordinator,
        calendarCoordinator: calendarCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var fallbackCoordinator = FallbackCoordinator(
        store: fallbacks, quicklinks: quicklinks, settings: settings, visibility: visibility,
        core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, clipboardManager: clipboardManager, settings: settings,
        appIndex: appIndex, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var calendarCoordinator = CalendarCoordinator(
        store: calendarStore, clock: meetingClock, appIndex: appIndex, settings: settings,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: appIndex, session: fileSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, windowController: windowController, core: self)
    @ObservationIgnored private(set) lazy var menuSearchCoordinator = MenuSearchCoordinator(
        settings: settings, appIndex: appIndex, session: menuSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var windowSwitchCoordinator = WindowSwitchCoordinator(
        settings: settings, appIndex: appIndex, session: windowSwitch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var cameraCoordinator = CameraCoordinator(core: self)
    @ObservationIgnored private(set) lazy var dictionaryCoordinator = DictionaryCoordinator(
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var updateCoordinator = UpdateCoordinator(
        store: updateChecker, core: self)
    @ObservationIgnored private(set) lazy var supportCoordinator = SupportCoordinator(
        store: supportReminders, core: self)
    @ObservationIgnored private(set) lazy var quickActionCoordinator = QuickActionCoordinator(
        settings: settings, store: quickActionSettings, customActions: customQuickActions,
        injector: textInjector, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var mcpCoordinator = MCPCoordinator(
        settings: settings, store: mcpSettings, manager: mcp, core: self)
    /// 与 Settings 一样拥有独立的窗口与生命周期；Quick AI 是同一功能在命令面板侧的另一半。
    @ObservationIgnored private(set) lazy var aiChatCoordinator = AIChatCoordinator(
        chats: aiChats, settings: settings, appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var quickAICoordinator = QuickAICoordinator(
        chats: aiChats, settings: settings, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    private(set) var isShowingDialog = false
    var isDimmingPaletteForDialog: Bool { isShowingDialog && windowController.isVisible }
    /// 所有确认、报告和提示的唯一入口；它也能阻止按住快捷键时反复堆叠弹窗。
    @ObservationIgnored private lazy var dialogs = DialogController(
        settings: settings,
        onPresentationChanged: { [weak self] isPresenting in
            guard let self else { return }
            isShowingDialog = isPresenting
        })
    private let healthTicker = HealthTicker()

    /// 初始化所有长期状态；这里只组装依赖，不启动需要权限或窗口的副作用。
    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        let chatHistory = ChatHistoryStore(directory: AppPaths.applicationSupport())
        self.launcherRanking = launcherRanking
        self.settings = settings
        self.chatHistory = chatHistory
        supportReminders = SupportReminderStore(settings: settings)
        aiChats = AIChatSurfacesState(history: chatHistory)
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        extensions = ExtensionManager(clipboardStore: clipboardStore)
        snippetsStore = SnippetsStore(repository: Self.snippetsRepository(for: settings))
        textInjector = TextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
        let noteSelectionKey = "notesActiveFileName"
        notesStore = NotesStore(
            repository: Self.notesRepository(for: settings),
            loadSelection: {
                UserDefaults.standard.string(forKey: noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: noteSelectionKey) })
    }

    /// 应用唯一的启动编排点；按依赖顺序启动索引、监听器、快捷键、窗口和设置镜像。
    func start() {
        Signposts.interval("AppCore.start") {
            // 缩短 AppKit 约 2–3 秒的 tooltip 延迟；写入 registration domain，因此用户默认值仍然优先。
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            dictationAudioDucker.recover()
            applyAppearance()
            observeEffectiveAppearance()
            pinnedEmoji.onPersistenceFailure = { [weak self] in
                self?.showMessage("Couldn't save Emoji & Symbols pins", tone: .danger)
            }

            appIndex.start(settings: settings)
            clipboardCoordinator.applyEnabled()
            extensions.start(appIndex: appIndex, coordinator: extensionCoordinator)
            extensionCoordinator.applyEnabled()
            fileSearchCoordinator.applyEnabled()
            windowSwitchCoordinator.applyEnabled()
            menuSearchCoordinator.applyEnabled()
            fileSearchCoordinator.applyPolicy()
            notesCoordinator.applyEnabled()
            installedAI.launchSettings = { [aiSettings] in aiSettings.launch(for: $0) }
            chatGPTSubscription.launchSettings = { [aiSettings] in aiSettings.launch(for: .codex) }
            aiChatCoordinator.applyEnabled()
            mcpCoordinator.applyEnabled()
            customQuickActions.onChange = { [weak self] _ in
                self?.quickActionCoordinator.applyCustomQuickActionsPresence()
            }
            // 即使该功能关闭也要在 `hotKeys.start` 之前执行：后续的快捷键清理需要读取它。
            customQuickActions.load()
            quickActionCoordinator.applyEnabled()
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            applyWindowCommandsPresence()
            customWindowSizes.onChange = { [weak self] _ in
                self?.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            }
            customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            windowLayouts.onChange = { [weak self] _ in
                self?.windowLayoutCoordinator.applyWindowLayoutsPresence()
            }
            windowLayoutCoordinator.applyWindowLayoutsPresence()
            rooms.onChange = { [weak self] _ in self?.roomCoordinator.applyRoomsPresence() }
            roomCoordinator.applyRoomsPresence()
            // 崩溃可能让窗口停留在屏幕外；先于其他一切把它们恢复回原位。
            roomCoordinator.recoverParkedWindows()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            // 即使该功能关闭也要在 `hotKeys.start` 之前执行：后续的清理需要读取它。详见 docs/features/quicklinks.md
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            appleShortcutCoordinator.applyPresence()
            paletteCoordinator.onLauncherShown = { [weak self] in
                self?.appleShortcutCoordinator.refresh()
            }
            paletteCoordinator.onScreenOpening = { [weak self] mode in
                switch mode {
                case .menuSearch: self?.menuSearchCoordinator.load()
                case .switchWindows: self?.windowSwitchCoordinator.load()
                case .rooms, .roomWindows: self?.roomCoordinator.load()
                default: break
                }
            }
            updateCoordinator.applyEnabled()
            calendarCoordinator.applyEnabled()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load(languages: Locale.preferredLanguages) }
            currencyRates.start()
            updateChecker.onUpdateAvailable = { [weak self] release in
                self?.updateCoordinator.presentIfAvailable(release) ?? true
            }
            updateCoordinator.applyAutomaticChecking()
            supportReminders.onDue = { [weak self] in self?.supportCoordinator.presentIfDue() }
            supportReminders.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.modifierTapMonitor.healthTicker = healthTicker
            snippetListener.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.dictationEnabled = settings.dictationEnabled
            hotKeys.dictationHoldToTalk = settings.dictationMode == .pushToTalk
            hotKeys.onDictationPressed = { [weak self] in self?.dictationCoordinator.pressed() }
            hotKeys.onDictationReleased = { [weak self] in self?.dictationCoordinator.released() }
            hotKeys.onDictationCancelled = { [weak self] in self?.dictationCoordinator.cancel() }
            hotKeys.onRunCommand = { [weak self] id in self?.launcherCoordinator.runCommand(id) }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onRunWindowLayout = { [weak self] id in
                self?.windowLayoutCoordinator.runWindowLayout(id: id)
            }
            hotKeys.onEnterRoom = { [weak self] id in self?.roomCoordinator.enterRoom(id: id) }
            hotKeys.onRunCustomWindowSize = { [weak self] id in
                self?.windowCommandCoordinator.runCustomWindowSize(id: id)
            }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.onRunQuickAction = { [weak self] id in
                self?.quickActionCoordinator.run(id: id)
            }
            hotKeys.onRunAppleShortcut = { [weak self] id in
                self?.appleShortcutCoordinator.run(id: id)
            }
            hotKeys.onExpandSnippet = { [weak self] id in
                self?.snippetCoordinator.expandSnippetFromHotKey(id: id)
            }
            hotKeys.onRunExtensionCommand = { [weak self] entryID in
                self?.extensionCoordinator.runExtensionCommand(entryID: entryID)
            }
            extensions.onDidUninstall = { [weak self] entryIDs in
                self?.extensionCoordinator.removeExtensionReferences(entryIDs: entryIDs)
            }
            appIndex.onScan = { [weak self] in
                guard let self else { return }
                hotKeys.removeAppBindings(where: appIndex.isUninstalled)
                // 放在首次扫描之后，这样文件中的应用与面板才有可匹配的条目。
                if settings.settingsFileEnabled, settingsFile == nil {
                    startSettingsFile(importing: true)
                } else if let launcherSettingsFile {
                    reportSettingsFileIssues(launcherSettingsFile.applyInstalled())
                }
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            hotKeys.allowsAction = { [weak self] action in
                guard let self, visibility.allowsHotKey(action) else { return false }
                if action == .dictation { return settings.dictationEnabled }
                // 功能被禁用时会从启动器移除其命令；对应的快捷键也要一并移除。
                guard case .command(let id) = action else { return true }
                return appIndex.isCommandEnabled(id)
            }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)),
                windowLayoutIDs: Set(windowLayouts.layouts.map(\.id)),
                windowRoomIDs: Set(rooms.rooms.map(\.id)),
                customWindowSizeIDs: Set(customWindowSizes.sizes.map(\.id)),
                quickActionIDs: Set(customQuickActions.actions.map(\.id)))
            // 在 Carbon 暂停期间仍需继续运行：快捷键录制依赖它改写后的修饰键标志。
            hyperKeyTap.start(settings: settings)

            snippetsStore.onSnapshot = { [weak self] snapshot in
                guard let self else { return }
                self.snippetCoordinator.applySnippetsLauncherPresence()
                self.snippetListener.update(snapshot.records)
                self.hotKeys.removeSnippetBindings(keeping: snapshot.fileIDs)
            }
            // 默认关闭，未使用的功能不会带来任何加载、文件监听或事件监听开销。
            if settings.snippetsEnabled {
                Task { await snippetsStore.start() }
                snippetCoordinator.startSnippetKeywordListener()
            }
            // 无条件执行：功能被禁用时必须同步移除其在启动器中的命令行。
            snippetCoordinator.applySnippetsLauncherPresence()

            observeFeatureSwitches()

            // 首次启动没有任何快捷键绑定，因此只引导一次；标记在展示时写入。
            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                onboardingCoordinator.showOnboarding()
            }
        }
    }

    /// 点击 Dock 图标时的处理：优先激活已打开的相关窗口，否则唤起启动器。
    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if aiChatCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        if updateCoordinator.focusExisting() { return }
        if supportCoordinator.focusExisting() { return }
        if customCommandCoordinator.focusOutputWindow() { return }
        paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// 处理通过 URL scheme 打开应用的回调：先交给扩展 OAuth 回调，再处理扩展深链。
    func handleOpenURL(_ url: URL) {
        switch ExtensionOAuthSession.handleCallbackURL(url) {
        case .delivered:
            paletteCoordinator.showPalette(mode: .extensionCommand, restoreAnyMode: true)
            return
        case .expired:
            showMessage("Sign-in expired — run the command again", tone: .danger)
            return
        case .ignored:
            break
        }
        guard ExtensionDeepLink.claims(url) else { return }
        guard let link = ExtensionDeepLink.parse(url: url) else {
            paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
            return
        }
        extensionCoordinator.runDeepLink(link)
    }

    /// 冲突提示中依赖 store 的那一半；各类目录名称由 `HotKeyManager` 自行提供。
    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .customCommand(let id):
            return customCommands.command(id: id)?.name
        case .quicklink(let id):
            return quicklinks.quicklink(id: id)?.name
        case .quickAction(let id):
            return customQuickActions.action(id: id)?.name
        case .windowLayout(let id):
            return windowLayouts.layout(id: id)?.name
        case .windowRoom(let id):
            return rooms.room(id: id)?.name
        case .customWindowSize(let id):
            return customWindowSizes.size(id: id)?.name
        case .appleShortcut(let id):
            return appleShortcutCoordinator.name(of: id)
        case .snippet(let id):
            return snippetsStore.record(id: id)?.snippet.name
        case .extensionCommand(let entryID):
            return appIndex.apps.first { $0.kind == .extensionCommand && $0.id == entryID }?.name
        case .togglePalette, .dictation, .command, .systemAction, .windowCommand:
            return nil
        }
    }

    /// 退出前把尚未落盘的笔记草稿刷写到磁盘。
    func flushNotesForTermination() async {
        await notesCoordinator.prepareForTermination()
    }

    /// 退出前停止听写：先收尾录音会话，恢复被压低的其他音频，再释放模型。
    func stopDictationForTermination() async {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        dictationAudioDucker.restoreImmediately()
        await dictationAudioDucker.waitForTransition()
        await dictationModels.stop()
    }

    /// 幂等：两个开关都被监听，任意一个变化都会重新执行整套判断。
    func applyClipboardTextSearch() {
        guard settings.clipboardEnabled, settings.clipboardTextSearchEnabled else {
            clipboardStore.onItemsChanged = nil
            clipboardStore.onSearchResultsChanged = nil
            clipboardStore.setTextSearchEnabled(false)
            clipboardTextIndexer?.stop()
            return
        }
        guard clipboardStore.setTextSearchEnabled(true) else {
            showMessage("Couldn't enable text recognition for clipboard history.", tone: .danger)
            return
        }
        clipboardStore.setTextSearchActive(palette.isVisible)
        // 禁用时保留实例：被取消的索引任务收尾后，indexer 会自行重新调度。
        let indexer =
            clipboardTextIndexer
            ?? ClipboardTextIndexer(store: clipboardStore, canRun: { ClipboardTextIndexer.isSystemIdle })
        clipboardTextIndexer = indexer
        clipboardStore.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        clipboardStore.onSearchResultsChanged = { [weak self] query, previous, current in
            self?.clipboardCoordinator.followSearchResults(query: query, previous: previous, current: current)
        }
        indexer.start()
    }

    /// 进程退出前的统一清理：落盘设置、停止后台任务并还原会存活到进程之外的系统改动。
    func prepareForTermination() {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        settingsFile?.flush()
        clipboardTextIndexer?.stop()
        // 先处理 Caps Lock：它的重映射是唯一会存活到进程之外的拆卸项。
        hyperKeyTap.prepareForTermination()
        windowLayoutCoordinator.prepareForTermination()
        roomCoordinator.prepareForTermination()
        inputSourceSwitcher.endSession()
        textInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
        aiChats.reset()
        chatGPTSubscription.stop()
        mcpOAuth.stop()
        mcp.stop()
        installedAI.stop()
    }

    /// 只重新检查自身路径或环境变量发生变化的工具；其余工具保持运行。
    private func applyInstalledLaunches() {
        let revisions = aiSettings.launchRevisions
        let enabled =
            settings.aiEnabled || settings.quickActionsEnabled
            ? aiSettings.enabledInstalledProviders : []
        for kind in InstalledAIKind.allCases where appliedLaunchRevisions[kind] != revisions[kind] {
            guard enabled.contains(kind) else { continue }
            if kind == .codex {
                chatGPTSubscription.stop()
                chatGPTSubscription.refresh()
            } else {
                installedAI.refresh(kind: kind)
            }
        }
        appliedLaunchRevisions = revisions
    }

    /// 根据当前启用情况刷新已安装 AI 工具的生命周期，并返回等待其完成的 Task。
    @discardableResult
    func applyInstalledAILifecycle() -> Task<Void, Never> {
        let enabledKinds =
            settings.aiEnabled || settings.quickActionsEnabled
            ? aiSettings.enabledInstalledProviders : []
        var tasks: [Task<Void, Never>] = []
        if enabledKinds.contains(.codex) {
            tasks.append(
                chatGPTSubscription.phase == .idle
                    ? chatGPTSubscription.refresh()
                    : chatGPTSubscription.currentRefreshTask())
        } else {
            chatGPTSubscription.stop()
        }
        tasks.append(installedAI.ensure(enabledKinds: enabledKinds))
        return Task { for task in tasks { await task.value } }
    }

    /// 采用宽松的内容护栏：被改写的文本是用户自己的内容，`.default` 策略会拒绝处理这类输入。
    func quickActionProvider(for action: QuickAction) throws -> any AIProvider {
        quickActionSettings.repairModel(
            against: aiSettings.connections, fallback: aiSettings.defaultModel)
        guard let selection = quickActionSettings.model(for: action) ?? aiSettings.defaultModel
        else {
            throw AIProviderError.unavailable("Choose a model in Settings \u{2192} Quick Actions.")
        }
        return try AIProviderFactory.make(
            selection: selection, settings: aiSettings, subscription: chatGPTSubscription,
            installedAI: installedAI,
            guardrails: .permissiveContentTransformations)
    }

    /// Decide 动作与 Decisions 模型聊天共用的路由：从启用的 API 连接里找 Decisions 模型，
    /// 端点与密钥都取自该连接，因此不再有独立的网关配置。
    func decisionsClient() throws -> DecisionsClient {
        guard let route = aiSettings.decisionsRoute() else {
            throw DecisionsClient.ClientError.noRoute
        }
        let endpoint: URL
        do {
            endpoint = try AIEndpointPolicy.validate(
                DecisionsRouting.normalizeBase(route.connection.baseURL))
        } catch let error as AIEndpointPolicy.ValidationError {
            throw DecisionsClient.ClientError.badEndpoint(error.localizedDescription)
        }
        let key: String
        do {
            key = try KeychainSecretStore.aiAPIKeys.secret(for: route.connection.id) ?? ""
        } catch {
            throw DecisionsClient.ClientError.keychainRead
        }
        guard !key.isEmpty || AIEndpointPolicy.isLoopback(route.connection.baseURL) else {
            throw DecisionsClient.ClientError.missingKey
        }
        return DecisionsClient(endpoint: endpoint, model: route.model, apiKey: key)
    }

    // MARK: - Feature switches

    /// 监听各功能开关，并在开关变化时重新投影到对应的 coordinator。
    private func observeFeatureSwitches() {
        track(
            { _ = $0.automaticallyCheckForUpdates },
            reproject: { $0.updateCoordinator.applyAutomaticChecking() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            },
            reproject: {
                $0.applyWindowCommandsPresence()
                $0.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowLayoutsShowInLauncher
            }, reproject: { $0.windowLayoutCoordinator.applyWindowLayoutsPresence() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowRoomsShowInLauncher
            }, reproject: { $0.roomCoordinator.applyEnabled() })
        track(
            {
                _ = $0.customCommandsEnabled
                _ = $0.customCommandsShowInLauncher
            }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track(
            {
                _ = $0.quicklinksEnabled
                _ = $0.quicklinksShowInLauncher
            }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track(
            { _ = $0.appleShortcutsEnabled },
            reproject: { $0.appleShortcutCoordinator.applyPresence() })
        track(
            { _ = $0.clipboardEnabled }, reproject: { $0.clipboardCoordinator.applyEnabled() })
        track(
            { _ = $0.clipboardTextSearchEnabled }, reproject: { $0.applyClipboardTextSearch() })
        track({ _ = $0.fileSearchEnabled }, reproject: { $0.fileSearchCoordinator.applyEnabled() })
        // 一个开关控制两个功能：每个 coordinator 只负责开启自己的命令与模式。
        track(
            { _ = $0.navigationEnabled },
            reproject: {
                $0.windowSwitchCoordinator.applyEnabled()
                $0.menuSearchCoordinator.applyEnabled()
            })
        track({ _ = $0.notesEnabled }, reproject: { $0.notesCoordinator.applyEnabled() })
        track({ _ = $0.aiEnabled }, reproject: { $0.aiChatCoordinator.applyEnabled() })
        track(
            { _ = $0.dictationIdleRelease },
            reproject: {
                $0.dictationModels.setIdleRelease($0.settings.dictationIdleRelease)
            })
        track(
            {
                _ = $0.dictationEnabled
                _ = $0.dictationMode
            },
            reproject: {
                $0.hotKeys.dictationHoldToTalk = $0.settings.dictationMode == .pushToTalk
                $0.hotKeys.dictationEnabled = $0.settings.dictationEnabled
            })
        track(
            {
                _ = $0.aiEnabled
                _ = $0.mcpEnabled
            }, reproject: { $0.mcpCoordinator.applyEnabled() })
        track(
            { _ = $0.quickActionsEnabled },
            reproject: { $0.quickActionCoordinator.applyEnabled() })
        track({ _ = $0.calendarEnabled }, reproject: { $0.calendarCoordinator.applyEnabled() })
        track(
            {
                _ = $0.calendarShowInLauncher
                _ = $0.calendarLauncherLimit
            }, reproject: { $0.calendarCoordinator.publishEntries() })
        track(
            { _ = $0.calendarSpan },
            reproject: { $0.calendarCoordinator.applySpan() })
        track(
            {
                _ = $0.autoJoinMeetings
                _ = $0.menuBarEvents
                _ = $0.calendarMenuBarDisplay
                _ = $0.menuBarLinkedEventsOnly
                _ = $0.hideCurrentEvent
            }, reproject: { $0.calendarCoordinator.applyClock() })
        track(
            {
                _ = $0.fileSearchScopes
                _ = $0.fileSearchIgnorePatterns
            }, reproject: { $0.fileSearchCoordinator.applyPolicy() })
        track({ _ = $0.snippetsEnabled }, reproject: { $0.snippetCoordinator.applySnippetsEnabled() })
        // 不是功能开关，但同样需要重投影：组合键里已经固化了组合串的 ⇧ 位。
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track(
            { _ = $0.snippetsShowInLauncher },
            reproject: { $0.snippetCoordinator.applySnippetsLauncherPresence() })
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.interfaceSize }, reproject: { $0.windowController.applyInterfaceSize() })
        // 这些先前由设置面板在变更时处理；现在 settings.json 也可以在没有任何面板打开时改动它们。
        track(
            { _ = $0.clipboardRetention },
            reproject: { $0.clipboardCoordinator.applyRetention($0.settings.clipboardRetention) })
        track(aiSettings, { _ = $0.retention }, reproject: { $0.aiChatCoordinator.applyRetention() })
        track(aiSettings, { _ = $0.launchRevisions }, reproject: { $0.applyInstalledLaunches() })
        track(
            { _ = $0.extensionsShowInLauncher },
            reproject: { $0.extensionCoordinator.applyExtensionsLauncherPresence() })
        track({ _ = $0.snippetsFolder }, reproject: { $0.applySnippetsFolder() })
        track({ _ = $0.notesFolder }, reproject: { $0.applyNotesFolder() })
        trackChatRoute()
    }

    /// `.system` 会解析为 `nil`，因此 AppKit 直接跟随 macOS，无需任何轮询。
    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// 在这里通知 IconCache，而不是在 `applyAppearance()` 中：后者在 `.system` 下永远不会触发。
    private func observeEffectiveAppearance() {
        // 在主线程同步回调，因此不会出现某一行用旧外观的 key 缓存图标的情况。
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    /// 针对 `AppSettings` 的便捷重载：把读取闭包直接转发给通用 `track`。
    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        track(settings, reads, reproject: reproject)
    }

    /// 在主线程同步触发且早于写入落盘，因此任务会重新挂载并重读一次。
    private func track<Store: AnyObject & Sendable>(
        _ store: Store,
        _ reads: @escaping @Sendable @MainActor (Store) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(store)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(store, reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    /// 当某个聊天路由自带 MCP 客户端时，需要由它决定 GearMac 自己运行哪些服务器。
    private func trackChatRoute() {
        let runsOwnTools = withObservationTracking {
            aiChatCoordinator.everyChatRunsItsOwnTools
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackChatRoute() }
        }
        // 每次流式刷新都会重读，因此只有判定结果真正改变时才会通知服务器。
        defer { chatsRunTheirOwnTools = runsOwnTools }
        guard let previous = chatsRunTheirOwnTools, previous != runsOwnTools else { return }
        mcpCoordinator.applyEnabled()
    }

    /// 未启用 Hyper Key 时该组合串没有意义，因此按字面记录的 ⌃⌥⌘ 组合保持原样。
    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    /// 片段目录设置变化后，把片段存储迁移到新的仓库位置。
    private func applySnippetsFolder() {
        let repository = Self.snippetsRepository(for: settings)
        Task { await snippetsStore.relocate(to: repository) }
    }

    /// 笔记目录设置变化后，把笔记存储迁移到新的仓库位置。
    private func applyNotesFolder() {
        let repository = Self.notesRepository(for: settings)
        Task { await notesStore.relocate(to: repository) }
    }

    /// 根据设置构造片段仓库，目录解析到应用支持目录下的 Snippets 内容文件夹。
    private static func snippetsRepository(for settings: AppSettings) -> SnippetRepository {
        SnippetRepository(
            snippetsDirectory: AppPaths.contentFolder(settings.snippetsFolder, named: "Snippets"))
    }

    /// 根据设置构造笔记仓库，目录解析到应用支持目录下的 Notes 内容文件夹。
    private static func notesRepository(for settings: AppSettings) -> NotesRepository {
        NotesRepository(notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes"))
    }

    /// 根据窗口管理开关与「在启动器显示」开关，同步窗口命令在应用索引中的可见性。
    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Settings file

    /// 从此开始把设置镜像到 settings.json；`importing` 为真时先应用文件自身的设置。
    func startSettingsFile(importing: Bool) {
        guard settingsFile == nil else { return }
        let shortcuts = HotKeySettingsFile(hotKeys: hotKeys)
        let launcher = LauncherSettingsFile(
            appIndex: appIndex, aliases: aliases, visibility: visibility, shortcuts: shortcuts)
        let file = SettingsFileRepository(
            fileURL: AppPaths.settingsFile(),
            bindings: SettingsFileSchema.bindings(
                settings: settings, ai: aiSettings, quickActions: quickActionSettings,
                shortcuts: shortcuts, launcher: launcher,
                windowManagement: WindowManagementSettingsFile(
                    sizes: customWindowSizes, layouts: windowLayouts, rooms: rooms, aliases: aliases,
                    shortcuts: shortcuts)),
            commit: shortcuts.commit)
        file.onIssues = { [weak self] issues in self?.reportSettingsFileIssues(issues) }
        settingsFile = file
        launcherSettingsFile = launcher
        settings.settingsFileEnabled = true
        file.start(importing: importing)
    }

    /// 停止镜像；文件按最后一次写入的内容保留在磁盘上。
    func stopSettingsFile() {
        settingsFile?.flush()
        settingsFile = nil
        launcherSettingsFile = nil
        settings.settingsFileEnabled = false
    }

    /// 汇总 settings.json 解析出的问题，并以危险语气提示用户。
    private func reportSettingsFileIssues(_ issues: [SettingsFileIssue]) {
        guard let summary = SettingsFileIssue.summary(issues) else { return }
        showMessage(summary, tone: .danger)
    }

    // MARK: - Interruption

    /// 应用当前正在进行的活动；更新提示与支持提醒都会先查询它。
    var currentActivity: UpdateActivity {
        UpdateActivity(
            isExpandingSnippet: textInjector.isDelivering,
            isRunningExtension: extensions.running != nil,
            isUninstalling: uninstall.isTrashing,
            isRecordingHotKey: hotKeys.recordingAction != nil,
            isShowingDialog: isShowingDialog,
            isPaletteVisible: paletteCoordinator.isVisible)
    }

    /// 窗口是否可以取得焦点，而不打断用户正在进行的操作。
    var canInterruptUser: Bool { UpdateReadiness.evaluate(currentActivity) == nil }

    // MARK: - Dialogs, routed here so `dialogs` stays the single owner

    /// 展示只读通知；所有对话框统一由 `dialogs` 拥有。
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// `tone` 决定图标样式，`confirmRole` 决定按钮角色，二者刻意分离。
    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = "Cancel"
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    /// 选项多于两个的提问；返回的下标对应 `options` 数组。
    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction],
        defaultIndex: Int, tone: DialogTone = .neutral
    ) async -> Int {
        await dialogs.choose(
            title: title, message: message, symbol: symbol, tone: tone, options: options,
            defaultIndex: defaultIndex)
    }

    /// 报告失败并提供一个可用的备选操作；用户选择该操作时返回 `true`。
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// 短暂的成功/信息提示胶囊；与 `dialogs` 一样保持 `messageHUD` 的单一所有权。
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// 带转圈指示的同款胶囊，用于用户已启动但无法从别处看到进度的任务。
    func showProgress(_ message: String, onCancel: (() -> Void)? = nil) {
        messageHUD.showProgress(message: message, onCancel: onCancel)
    }

    /// 关闭当前正在展示的进度胶囊。
    func hideProgress() {
        messageHUD.dismiss()
    }

    /// 音量滑块；同样是为了让 `dialogs` 保持应用内所有提示的唯一所有者。
    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }

    /// 新建日程的提示框，出于同样的原因放在这里。
    func createEvent() async -> EventDraft? {
        await dialogs.createEvent()
    }

    /// 片段参数填写提示框，出于同样的原因放在这里。
    func fillSnippetArguments(
        snippetName: String, arguments: [SnippetTemplateEngine.MissingArgument]
    ) async -> [String: String]? {
        await dialogs.fillSnippetArguments(snippetName: snippetName, arguments: arguments)
    }
}
