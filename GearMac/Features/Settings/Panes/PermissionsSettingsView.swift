// 文件职责：设置面板「权限」页，展示辅助功能、日历、麦克风授权状态并提供申请或打开设置的入口。
// 分层：UI；通过 Permissions 与 AppCore 查询和申请权限，不直接管理 TCC。
import AVFoundation
import Combine
import SwiftUI

/// 「权限」设置页：显示各项系统权限状态并引导用户授权。
struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    @State private var microphoneAccess = Permissions.microphoneAccess()
    /// 每秒轮询一次的定时器，用于在用户于系统设置中修改权限后同步状态。
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: accessibilityStatus.symbol)
                                .accessibilityHidden(true)
                            Text(accessibilityStatus.title)
                        }
                        .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Pastes into the app you were using.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: calendarStatus.symbol)
                                .accessibilityHidden(true)
                            Text(calendarStatus.title)
                        }
                        .foregroundStyle(calendarStatus.tint)
                        Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                            // 设置里不会列出从未被 TCC 询问过的 App，因此主动询问才是进入授权设置的途径。
                            if calendarNeedsPrompt {
                                core.calendarCoordinator.setCalendarEnabled(true)
                            } else {
                                Permissions.openCalendarSettings()
                            }
                        }
                        .help(
                            calendarNeedsPrompt
                                ? "Turns the calendar on, then asks macOS for access."
                                : "Opens Privacy & Security › Calendars.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path: "/System/Applications/Calendar.app")
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsCalendars, "Calendars")
                            Text("Finds the join link for your next meeting.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: microphoneStatus.symbol)
                                .accessibilityHidden(true)
                            Text(microphoneStatus.title)
                        }
                        .foregroundStyle(microphoneStatus.tint)
                        Button(microphoneAccess == .notDetermined ? "Grant Access…" : "Open…") {
                            if microphoneAccess == .notDetermined {
                                Task {
                                    _ = await Permissions.requestMicrophoneAccess()
                                    refresh()
                                }
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                        .help(
                            microphoneAccess == .notDetermined
                                ? "Asks macOS for microphone access."
                                : "Opens Privacy & Security › Microphone.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: SettingsListMetrics.iconSize - Theme.Spacing.xs))
                            .frame(width: SettingsListMetrics.iconSize)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsMicrophone, "Microphone")
                            Text("Records audio only while dictating.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsMicrophone)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    /// 日历权限尚未被询问过（可以走「先启用再申请」的路径）。
    private var calendarNeedsPrompt: Bool { calendarAccess == .notDetermined }

    /// 辅助功能权限状态对应的标题、图标与颜色。
    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    /// 日历权限状态对应的标题、图标与颜色。
    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        switch calendarAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    /// 麦克风权限状态对应的标题、图标与颜色。
    private var microphoneStatus: (title: String, symbol: String, tint: Color) {
        switch microphoneAccess {
        case .authorized: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        default: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    /// 重新查询各项权限状态，仅在变化时更新 @State 以避免多余刷新。
    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
        let microphone = Permissions.microphoneAccess()
        if microphone != microphoneAccess { microphoneAccess = microphone }
    }
}

/// 权限行左侧的系统图标：根据文件路径读取真实 App 图标。
private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
