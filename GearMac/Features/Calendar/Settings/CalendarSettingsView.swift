// 文件职责：日历功能的设置界面：启停开关、加入窗口与自动加入选项、菜单栏显示方式、命令与逐日历启用列表。
// 分层：Settings（SwiftUI）；各项开关经 coordinator 路由，仅在功能启用时可用。
import SwiftUI

/// 日历功能的设置面板，由多个 Section 组成。
struct CalendarSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        Form {
            FeatureSwitchSection(
                anchor: .calendarCalendar,
                enableTitle: settings.text(CalendarKey.settingsEnable),
                enableSubtitle: String(
                    format: settings.text(CalendarKey.settingsEnableSubtitle),
                    settings.calendarSpan.localizedPossessivePhrase(settings.language)),
                isEnabled: enabledBinding,
                showsInLauncher: $settings.calendarShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Section {
                Picker(selection: $settings.calendarLauncherLimit) {
                    ForEach(CalendarLauncherLimit.allCases) { limit in
                        Text(launcherLimitTitle(limit)).tag(limit)
                    }
                } label: {
                    SettingsRowTitle(
                        .calendarCalendar, settings.text(CalendarKey.settingsLauncherLimit))
                }
            }
            .settingsEnabled(settings.calendarEnabled && settings.calendarShowInLauncher)

            if settings.calendarEnabled, store.access == .notDetermined {
                Section {
                    SettingsRow(
                        title: settings.text(CalendarKey.settingsAccessNeededTitle),
                        subtitle: settings.text(CalendarKey.settingsAccessNeededSubtitle)
                    ) {
                        Button(settings.text(CalendarKey.settingsAllowAccess)) {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        }
                    }
                }
            } else if store.access == .denied {
                Section {
                    SettingsRow(
                        title: settings.text(CalendarKey.settingsAccessOffTitle),
                        subtitle: settings.text(CalendarKey.settingsAccessOffSubtitle)
                    ) {
                        Button(settings.text(CalendarKey.settingsOpenSystemSettings)) {
                            Permissions.openCalendarSettings()
                        }
                    }
                }
            }

            Section {
                Picker(selection: $settings.joinWindowMinutes) {
                    ForEach(JoinWindow.allCases) { window in
                        Text(joinWindowTitle(window)).tag(window)
                    }
                } label: {
                    SettingsRowTitle(
                        .calendarJoining, settings.text(CalendarKey.settingsShowJoinCard))
                    Text(settings.text(CalendarKey.settingsShowJoinCardSubtitle))
                }
                Toggle(isOn: $settings.autoJoinMeetings) {
                    SettingsRowTitle(.calendarJoining, settings.text(CalendarKey.settingsAutoJoin))
                    Text(settings.text(CalendarKey.settingsAutoJoinSubtitle))
                }
                Toggle(isOn: $settings.autoJoinNamedProvidersOnly) {
                    SettingsRowTitle(
                        .calendarJoining, settings.text(CalendarKey.settingsKnownProvidersOnly))
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.autoJoinConfirms) {
                    SettingsRowTitle(
                        .calendarJoining, settings.text(CalendarKey.settingsConfirmBeforeJoining))
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.cameraPreview) {
                    SettingsRowTitle(
                        .calendarJoining, settings.text(CalendarKey.settingsCameraPreview))
                    Text(settings.text(CalendarKey.settingsCameraPreviewSubtitle))
                }
                MeetingBrowserPicker(selection: $settings.meetingBrowserBundleID)
            } header: {
                SettingsSectionHeader(.calendarJoining)
            }
            .settingsEnabled(settings.calendarEnabled)

            Section {
                Picker(selection: $settings.calendarMenuBarDisplay) {
                    ForEach(CalendarMenuBarDisplay.allCases) { display in
                        Text(menuBarDisplayTitle(display)).tag(display)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, settings.text(CalendarKey.settingsMenuBar))
                    Text(settings.text(CalendarKey.settingsMenuBarSubtitle))
                }
                Picker(selection: $settings.calendarSpan) {
                    ForEach(MeetingSpan.allCases) { span in
                        Text(span.localizedTitle(settings.language)).tag(span)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, settings.text(CalendarKey.settingsDaysToShow))
                    Text(settings.text(CalendarKey.settingsDaysToShowSubtitle))
                }
                Picker(selection: $settings.menuBarEvents) {
                    ForEach(MenuBarEvents.allCases) { lead in
                        Text(menuBarEventsTitle(lead)).tag(lead)
                    }
                } label: {
                    SettingsRowTitle(
                        .calendarMenuBar, settings.text(CalendarKey.settingsUpcomingEvents))
                    Text(settings.text(CalendarKey.settingsUpcomingEventsSubtitle))
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.menuBarLinkedEventsOnly) {
                    SettingsRowTitle(
                        .calendarMenuBar, settings.text(CalendarKey.settingsLinkedOnly))
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.calendarMenuBarHidesWhenEmpty) {
                    SettingsRowTitle(
                        .calendarMenuBar, settings.text(CalendarKey.settingsHideWhenEmpty))
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Picker(selection: $settings.hideCurrentEvent) {
                    ForEach(HideCurrentEvent.allCases) { hide in
                        Text(hideCurrentEventTitle(hide)).tag(hide)
                    }
                } label: {
                    SettingsRowTitle(
                        .calendarMenuBar, settings.text(CalendarKey.settingsHideCurrentEvent))
                    Text(settings.text(CalendarKey.settingsHideCurrentEventSubtitle))
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
            } header: {
                SettingsSectionHeader(.calendarMenuBar)
            }
            .settingsEnabled(settings.calendarEnabled)

            FeatureCommandsSection(owner: .calendar, anchor: .calendarCommands)
                .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.calendar)
        .releasesFocusOnOutsideClick()
        // 快照仅在功能运行时才会重载，因此在设置中授予的权限需要在这里被抓取。
        .onAppear { store.refreshAccess() }
    }

    /// 启动器中展示几场会议的选项标题：枚举定义在 AppSettings 中，标题在此映射。
    private func launcherLimitTitle(_ limit: CalendarLauncherLimit) -> String {
        let key: CalendarKey =
            switch limit {
            case .one: .optionLauncherLimitOne
            case .three: .optionLauncherLimitThree
            case .five: .optionLauncherLimitFive
            case .all: .optionLauncherLimitAll
            }
        return settings.text(key)
    }

    /// 加入卡片提前出现的分钟数选项标题。
    private func joinWindowTitle(_ window: JoinWindow) -> String {
        guard window != .one else { return settings.text(CalendarKey.optionJoinWindowOne) }
        return String(format: settings.text(CalendarKey.optionJoinWindowMany), window.rawValue)
    }

    /// 菜单栏显示方式选项标题。
    private func menuBarDisplayTitle(_ display: CalendarMenuBarDisplay) -> String {
        let key: CalendarKey =
            switch display {
            case .disabled: .optionMenuBarDisabled
            case .meetingIcon: .optionMenuBarIcon
            case .meetingTitle: .optionMenuBarTitle
            }
        return settings.text(key)
    }

    /// 菜单栏提前接管下一场会议的选项标题。
    private func menuBarEventsTitle(_ events: MenuBarEvents) -> String {
        guard events != .today else { return settings.text(CalendarKey.optionMenuBarEventsToday) }
        return String(
            format: settings.text(CalendarKey.optionMenuBarEventsBefore), events.rawValue)
    }

    /// 已开始会议的隐藏方式选项标题。
    private func hideCurrentEventTitle(_ hide: HideCurrentEvent) -> String {
        switch hide {
        case .dontHide: return settings.text(CalendarKey.optionHideCurrentKeepVisible)
        case .automatically: return settings.text(CalendarKey.optionHideCurrentAutomatically)
        default:
            return String(
                format: settings.text(CalendarKey.optionHideCurrentAfter), hide.rawValue)
        }
    }

    /// 经 coordinator 路由，使「启用」（同时也是授权）先经过确认。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

/// 会议链接浏览器选择器：枚举能打开 https 的 App，默认使用默认浏览器。
private struct MeetingBrowserPicker: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: String?
    @State private var browsers: [MeetingLauncher.Browser] = []

    /// 选择项：默认浏览器 + 已安装浏览器列表。
    var body: some View {
        Picker(selection: installedSelection) {
            Text(settings.text(CalendarKey.settingsDefaultBrowser)).tag(String?.none)
            Divider()
            ForEach(browsers) { browser in
                Text(browser.name).tag(Optional(browser.id))
            }
        } label: {
            SettingsRowTitle(.calendarJoining, settings.text(CalendarKey.settingsOpenLinksIn))
            Text(settings.text(CalendarKey.settingsOpenLinksInSubtitle))
        }
        .onAppear { browsers = MeetingLauncher.installedBrowsers() }
    }

    /// 已被卸载的浏览器会回退为默认项，也就是加入时的兜底行为。
    private var installedSelection: Binding<String?> {
        Binding(
            get: { browsers.contains { $0.id == selection } ? selection : nil },
            set: { selection = $0 }
        )
    }
}

/// 属于本机特有的数据，因此保存在 store 上，永不随备份迁移。
private struct CalendarPickerSection: View {
    @Environment(CalendarStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    /// 按查询串过滤后的日历列表（匹配名称或账号）。
    private var calendars: [MeetingCalendar] {
        guard !query.isEmpty else { return store.calendars }
        return store.calendars.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Section {
            SettingsFilterField(
                prompt: settings.text(CalendarKey.settingsSearchCalendars), query: $query)

            if calendars.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(calendars) { calendar in
                    CalendarRow(calendar: calendar)
                }
            }
        } header: {
            SettingsSectionHeader(.calendarCalendars)
        }
    }

    /// 列表为空时的提示文案，区分搜索无结果、无日历与未授权三种情况。
    private var emptyMessage: String {
        if !query.isEmpty {
            return String(format: settings.text(CalendarKey.settingsNoMatchesFormat), query)
        }
        return settings.text(
            store.access == .granted
                ? CalendarKey.settingsNoCalendars : CalendarKey.settingsNothingToShow)
    }
}

/// 单个日历的开关行，以复选框控制是否纳入会议读取范围。
private struct CalendarRow: View {
    @Environment(AppSettings.self) private var settings
    let calendar: MeetingCalendar
    @Environment(CalendarStore.self) private var store

    var body: some View {
        SettingsRow(title: calendar.title, subtitle: calendar.accountName) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel(
                    String(
                        format: settings.text(CalendarKey.settingsIncludeCalendarFormat),
                        calendar.title))
        }
    }

    /// 绑定到 store 中该日历的启用状态。
    private var binding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(calendar) },
            set: { store.setEnabled($0, for: calendar) }
        )
    }
}
