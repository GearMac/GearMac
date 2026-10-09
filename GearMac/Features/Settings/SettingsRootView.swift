// 文件职责：设置窗口的根视图，搭建侧边栏/详情两栏布局与前进后退工具栏。
// 分层：UI（SwiftUI）；使用 NavigationSplitView，而非 NSSplitViewController。
import SwiftUI

/// 使用 SwiftUI 的分栏而非 `NSSplitViewController`：只有它的侧边栏能让 `.searchable` 获得柔和边缘。
struct SettingsRootView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView()
                // 必须写在宽度设置之前：若写在之后，列宽会被压缩到 AppKit 的默认值。
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: Theme.Size.settingsSidebar, ideal: Theme.Size.settingsSidebar,
                    max: Theme.Size.settingsSidebar)
        } detail: {
            SettingsDetailView()
                .frame(minWidth: Theme.Size.settingsDetailMinimum)
        }
        .navigationTitle(navigation.tab.localizedTitle(settings.language))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button("Back", systemImage: "chevron.backward") { navigation.goBack() }
                        .disabled(!navigation.canGoBack)
                    Button("Forward", systemImage: "chevron.forward") { navigation.goForward() }
                        .disabled(!navigation.canGoForward)
                }
                .controlGroupStyle(.navigation)
            }
        }
    }
}
