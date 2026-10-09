// 文件职责：设置中的搜索范围列表，可编辑启动器索引的文件夹与单个 .app，并标记失效路径。
// 分层：UI（SwiftUI）；直接读写 AppSettings.searchScopes，缺失路径仅在变更时重算。
import SwiftUI
import UniformTypeIdentifiers

/// 启动器索引的文件夹（以及单个 `.app` bundle）可编辑列表。
struct SearchScopesSection: View {
    @Environment(AppSettings.self) private var settings
    /// 仅在变化时重算：每次 body 渲染对每行做一次 `fileExists` 开销过大。
    @State private var missing: Set<String> = []

    /// 当前搜索范围是否等于默认值。
    private var isDefault: Bool { settings.searchScopes == SearchScopes.defaults }

    var body: some View {
        Section {
            ForEach(settings.searchScopes, id: \.self) { scope in
                SettingsScopeRow(
                    scope: scope, path: SearchScopes.expand(scope),
                    isMissing: missing.contains(scope)
                ) {
                    settings.searchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button(settings.text(LauncherKey.addEllipsis), action: addScopes)
                    .help(settings.text(LauncherKey.addScopeHelp))
                if !isDefault {
                    Button(settings.text(LauncherKey.restoreDefaults)) {
                        settings.searchScopes = SearchScopes.defaults
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.applicationsSearchScopes)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.searchScopes) { _, _ in refreshMissing() }
    }

    /// 重新计算磁盘上已不存在的搜索范围。
    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.searchScopes.filter { !fm.fileExists(atPath: SearchScopes.expand($0)) })
    }

    /// 弹出选择面板，把选中的文件夹或应用追加并规范化到搜索范围。
    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        // 否则 .app 会被进入查看而不是被选中。
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = settings.text(LauncherKey.addScopePrompt)
        panel.message = settings.text(LauncherKey.chooseScopesMessage)
        // GearMac 是辅助型应用，没有这一步时面板会打开在最前应用之后。
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.searchScopes = SearchScopes.normalize(
            settings.searchScopes + panel.urls.map(\.path))
    }
}
