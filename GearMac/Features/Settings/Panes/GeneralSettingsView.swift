// 文件职责：设置面板「通用」页，汇集启动器快捷键、通用选项、外观、Hyper Key、计算器与搜索等控件。
// 分层：UI；仅读写 AppSettings 与 @Environment，副作用交由 Coordinator 处理。
import SwiftUI

/// 「通用」设置页：集中展示启动器、外观、Hyper Key、计算器与搜索相关设置。
struct GeneralSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var hyperTap: HyperKeyTap { core.hyperKeyTap }
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    /// 以符号形式表示的 Hyper 修饰键组合，跟随 Include Shift 开关变化。
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// 只有在此处做出的选择才会重置 Quick Press：settings.json 可能同时设置两个键。
    private var hyperKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.hyperKey },
            set: { key in
                guard key != settings.hyperKey else { return }
                settings.hyperKey = key
                // Quick Press 的选择换到其他键上便失去意义。
                settings.hyperKeyQuickPress = .none
                if key != .none { Permissions.ensureAccessibility() }
            })
    }

    /// 缺少权限的那半部分自成一整行，以便携带修复它的按钮。
    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else { return "Remap one key to \(hyperGlyphs) held together." }
        return "\(settings.hyperKey.title) sends \(hyperGlyphs), shown as ✦ in shortcuts."
    }

    /// 选择器里各语言的自称；「跟随系统」用当前界面语言表述。
    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system: return settings.text(SettingsKey.languageSystem)
        case .english: return settings.text(SettingsKey.languageEnglish)
        case .chinese: return settings.text(SettingsKey.languageChinese)
        }
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "App Launcher", anchor: .generalGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.generalGlobalShortcuts)
            }

            Section {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageTitle(language)).tag(language)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, settings.text(SettingsKey.languageTitle))
                    Text(settings.text(SettingsKey.languageCaption))
                }
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                }
                Toggle(isOn: $settings.showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Shortcuts still work when hidden.")
                }
                Toggle(isOn: $settings.automaticallyCheckForUpdates) {
                    SettingsRowTitle(.generalGeneral, "Automatically check for updates")
                    Text("Check for Updates remains available when off.")
                }
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Pop to Root Search")
                    Text("After the launcher closes.")
                }
                Picker(selection: $settings.escapeKeyBehavior) {
                    ForEach(EscapeKeyBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Escape Key Behavior")
                    Text("When the search field is empty.")
                }
                // 只有在 TIS 失败时才为空；只要还有一个输入法列出，该行就保留。
                if !inputSources.isEmpty {
                    Picker(selection: $settings.autoSwitchInputSourceID) {
                        Text("None").tag(nil as String?)
                        ForEach(inputSources) { source in
                            Text(source.title).tag(Optional(source.id))
                        }
                    } label: {
                        SettingsRowTitle(.generalGeneral, "Auto-switch input source")
                        Text("While the launcher is open.")
                    }
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
            }

            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Theme")
                }
                InterfaceSizeRow()
                WindowModeRow()
                Toggle(isOn: $settings.showFavoritesInCompactMode) {
                    SettingsRowTitle(.generalAppearance, "Show favorites in compact mode")
                    Text("Launch them with ⌘1–⌘5.")
                }
                .settingsEnabled(settings.compactMode)
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to reposition")
                    Text("Drag the strip above the search field.")
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            Section {
                Picker(selection: hyperKeySelection) {
                    ForEach(HyperKeyPhysicalKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Hyper Key")
                    Text(hyperSubtitle)
                }

                if hyperTap.status == .needsAccessibility {
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .frame(width: Theme.Size.settingsRowIcon)
                        Text("Remapping needs Accessibility access.")
                            .foregroundStyle(.orange)
                        Spacer(minLength: Theme.Spacing.lg)
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                }

                if settings.hyperKey.hasOriginalFunction {
                    Picker(selection: $settings.hyperKeyQuickPress) {
                        Text("Does Nothing").tag(HyperKeyQuickPress.none)
                        if let original = settings.hyperKey.quickPressOriginalTitle {
                            Text(original).tag(HyperKeyQuickPress.originalKey)
                        }
                        Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                    } label: {
                        SettingsRowTitle(.generalHyperKey, "Quick Press")
                        Text("When \(settings.hyperKey.title) is pressed alone.")
                    }
                }

                Toggle(isOn: $settings.hyperKeyIncludesShift) {
                    SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
                }
                // 切换它会重新指向已录制的组合键，因此需要一个组合键才有意义。
                .settingsEnabled(settings.hyperKey != .none)
            } header: {
                SettingsSectionHeader(.generalHyperKey)
            }

            Section {
                Picker(selection: $settings.calcNumberStyle) {
                    ForEach(CalcNumberStyle.allCases) { style in
                        let sample = core.regionNumberFormat.format(for: style).localized("1,234,567.89")
                        Text("\(style.title) (\(sample))").tag(style)
                    }
                } label: {
                    SettingsRowTitle(.generalCalculator, "Number format")
                    Text("With a decimal comma, ; separates arguments.")
                }
            } header: {
                SettingsSectionHeader(.generalCalculator)
            }

            Section {
                Toggle(isOn: $settings.launcherShowsSuggestions) {
                    SettingsRowTitle(.generalSearch, "Show suggestions")
                    Text("What you open most, while the search field is empty.")
                }
                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.generalSearch, "Search sensitivity")
                    Text("Lower finds names from scattered letters.")
                }
                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.generalSearch, "Learned ranking")
                    Text("Learned privately from the results you pick.")
                }
            } header: {
                SettingsSectionHeader(.generalSearch)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.general)
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GearMac will relearn your preferred results as you use the launcher.")
        }
        .onAppear(perform: refreshInputSources)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: InputSourceSwitcher.sourcesDidChange)
        ) { _ in
            refreshInputSources()
        }
    }

    /// 拉取当前可用输入源列表（含已选项）。
    private func refreshInputSources() {
        inputSources = core.inputSourceSwitcher.options(selecting: settings.autoSwitchInputSourceID)
    }
}

/// 「窗口模式」行：用预览图在紧凑与展开两种启动器尺寸之间切换。
private struct WindowModeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let preview = CGSize(width: 135, height: 80)

    var body: some View {
        SettingsRow(
            title: "Window mode", subtitle: "Choose how the launcher opens.",
            subtitleLineLimit: 2, alignment: .top, anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.md) {
                option("Compact", image: "WindowModeCompact", compact: true)
                option("Expanded", image: "WindowModeExpanded", compact: false)
            }
        }
    }

    /// 生成单个窗口模式选项按钮。
    private func option(_ title: String, image: String, compact: Bool) -> some View {
        let selected = settings.compactMode == compact
        return Button {
            settings.compactMode = compact
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.preview.width, height: Self.preview.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    )
                    .saturation(selected ? 1 : 0)
                Text(title)
                    .font(.caption)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowModeButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// 窗口模式按钮样式：按下后略微延迟降低不透明度，避免瞬时的视觉抖动。
private struct WindowModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration)
    }

    private struct PressedLabel: View {
        let configuration: ButtonStyle.Configuration
        @State private var showsPressed = false

        var body: some View {
            configuration.label
                .opacity(showsPressed ? 0.7 : 1)
                .task(id: configuration.isPressed) {
                    if configuration.isPressed {
                        try? await Task.sleep(for: .milliseconds(20))
                        guard !Task.isCancelled else { return }
                        showsPressed = true
                    } else {
                        showsPressed = false
                    }
                }
        }
    }
}

/// 三档字形作为图例更易读；等比例缩放的 "Aa" 在 1.1 倍时看起来几乎相同。
private struct InterfaceSizeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let glyph: [InterfaceSize: CGFloat] = [
        .standard: 11, .large: 14, .larger: 17
    ]

    var body: some View {
        SettingsRow(
            title: "Interface size",
            subtitle: "Scales the launcher and its panels, not Settings.",
            anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(InterfaceSize.allCases) { size in
                    segment(size)
                }
            }
        }
    }

    private func segment(_ size: InterfaceSize) -> some View {
        let selected = settings.interfaceSize == size
        return Button {
            settings.interfaceSize = size
        } label: {
            Text("Aa")
                .font(.system(size: Self.glyph[size] ?? 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .settingsOptionSegment(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(size.title)
    }
}
