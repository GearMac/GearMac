// 文件职责：设置窗口的侧边栏，提供分区浏览列表与搜索结果列表，并处理 ⌘F 搜索。
// 分层：UI（SwiftUI）；浏览与搜索使用两个独立 List，避免选中 id 命名空间冲突。
import SwiftUI

/// 设置窗口的侧边栏：分区浏览与搜索结果两种形态。
struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppSettings.self) private var settings
    @Environment(\.appearsActive) private var appearsActive
    @State private var query = ""
    @State private var highlighted: SettingsSearchEntry.ID?
    @State private var searching = false

    /// 当前查询对应的搜索结果。
    private var results: [SettingsSearchEntry] { SettingsSearchCatalog.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        .searchable(
            text: $query, isPresented: $searching, placement: .sidebar,
            prompt: Text(settings.text(SettingsKey.sidebarSearchPrompt)))
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    /// 分区浏览列表（未输入查询时）。
    private var browse: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.localizedTitle(settings.language)) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.localizedTitle(settings.language))
                        } icon: {
                            SettingsTabIcon(
                                systemImage: tab.systemImage,
                                tint: appearsActive
                                    ? (navigation.tab == tab ? Color.primary : Color.accentColor)
                                    : Color.secondary)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // 在挂载前固定样式；隐式的侧边栏样式会让图标晚一帧才绘制。
        .labelStyle(.titleAndIcon)
    }

    /// 搜索结果列表（已输入查询时）；无结果时展示空状态。
    @ViewBuilder private var found: some View {
        if results.isEmpty {
            // 需要贪婪布局：这里若给出有限的最大高度，它会变成约束并把整个窗口压小。
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // 第二个 `List`，因此搜索结果 id 与 `SettingsTab` 不会共用同一个选择命名空间。
            List(selection: $highlighted) {
                Section("Results") {
                    ForEach(results) { entry in
                        SettingsSearchResultRow(entry: entry).tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            // 用方向键浏览结果时，右侧页面会跟随选中项切换，与系统「设置」一致。
            .onChange(of: highlighted) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                navigation.select(entry.tab, revealing: entry.target)
            }
        }
    }

    /// 用于承载 ⌘F——它没有对应的菜单项；尺寸为零，因此只贡献快捷键本身。
    private var focusShortcut: some View {
        Button("Search Settings") { searching = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// `List` 返回的是可选选中项；经由 `select` 转发才能记录导航历史。
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}

/// 搜索结果的单行：标题加面包屑路径。
private struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.title).lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            SettingsTabIcon(systemImage: entry.tab.systemImage, tint: .accentColor)
        }
        // 居中对齐而非首行基线：图标块旁的标题与面包屑共两行。
        .labelStyle(CenteredLabelStyle())
    }
}

/// 图标与标题垂直居中对齐的 Label 样式。
private struct CenteredLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}
