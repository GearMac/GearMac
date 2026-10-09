// 文件职责：设置窗口的右侧页面列，按导航历史当前指向的 tab 渲染对应的设置页。
// 分层：UI（SwiftUI）；所有设置页共用同一个宿主，不使用多标签容器。
import SwiftUI

/// 页面列：渲染导航历史当前指向的那个设置页。
struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        // 不使用 `TabView`：`NSTabView` 在切换时会重新挂载宿主，从而破坏快捷键录制器。
        Group {
            switch navigation.tab {
            case .general: GeneralSettingsView()
            case .applications: ApplicationsSettingsView()
            case .systemSettings: SystemSettingsSettingsView()
            case .systemActions: SystemActionsSettingsView()
            case .commands: CommandsSettingsView()
            case .quicklinks: QuicklinksSettingsView()
            case .appleShortcuts: AppleShortcutsSettingsView()
            case .fallbacks: FallbacksSettingsView()
            case .ai: AISettingsView()
            case .quickActions: QuickActionsSettingsView()
            case .dictation: DictationSettingsView()
            case .fileSearch: FileSearchSettingsView()
            case .notes: NotesSettingsView()
            case .snippets: SnippetsSettingsView()
            case .navigation: NavigationSettingsView()
            case .windowManagement: WindowManagementSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .emoji: EmojiSettingsView()
            case .calendar: CalendarSettingsView()
            case .extensions: ExtensionsSettingsView()
            case .permissions: PermissionsSettingsView()
            case .backup: BackupSettingsView()
            case .about: AboutView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 所有页面共用同一个宿主，且位于各自滚动视图之上，因此弹出提示不会被裁剪。
        .shortcutRecorderPopoverHost()
    }
}
