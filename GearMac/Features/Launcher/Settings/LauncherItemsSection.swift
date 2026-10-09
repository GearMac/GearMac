// 文件职责：定义启动器条目设置列表的通用组件：类别总开关、条目分组、过滤列表与单行控件。
// 分层：UI（SwiftUI）；列表不做可见性过滤，被隐藏的条目仍会列出以便恢复。
import SwiftUI

/// 某类别的总开关：即使该类的列表被禁用，开关仍保持可用。
struct LauncherCategorySwitchSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor

    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { visibility.isKindEnabled(kind) },
                    set: { visibility.setKindEnabled($0, for: kind) }
                )
            ) {
                SettingsFeatureToggleLabel(
                    anchor: anchor,
                    title: String(format: settings.text(LauncherKey.enableFormat), anchor.title),
                    subtitle: settings.text(LauncherKey.offHidesAll))
            }
        }
    }
}

/// 某个类别的设置列表；不按可见性过滤，因此被隐藏的行仍会列出。
struct LauncherItemsSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor
    let searchPrompt: String

    @Environment(AppIndex.self) private var appIndex
    @Environment(VisibilityStore.self) private var visibility
    @State private var query = ""

    /// 按类别取条目，并按查询做纯成员过滤（不改变原有顺序）。
    private var entries: [AppEntry] {
        let scoped = appIndex.apps.filter { $0.kind == kind && $0.settingsOwner == nil }
        guard !query.isEmpty else { return scoped }
        // 只判断是否命中：若按得分排序，正在编辑的行会在光标下发生位移。
        let matched = Set(appIndex.matches(query).map(\.id))
        return scoped.filter { matched.contains($0.id) }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: searchPrompt, query: $query)
            LauncherItemsList(
                entries: entries, query: query, isEnabled: visibility.isKindEnabled(kind))
        } header: {
            SettingsSectionHeader(anchor)
        }
        .settingsEnabled(visibility.isKindEnabled(kind))
    }
}

/// 过滤框下方的行列表，或为空时的提示文案；由各条目面板共用。
struct LauncherItemsList: View {
    let entries: [AppEntry]
    let query: String
    let isEnabled: Bool

    @Environment(VisibilityStore.self) private var visibility
    @Environment(AliasStore.self) private var aliases
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AppSettings.self) private var settings
    @State private var recorderFrame: CGRect?

    var body: some View {
        if entries.isEmpty {
            Text(
                query.isEmpty
                    ? settings.text(LauncherKey.nothingHereYet)
                    : String(format: settings.text(LauncherKey.noMatchesFormat), query)
            )
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        } else if entries.first?.kind != .application && entries.first?.kind != .appleShortcut {
            ForEach(entries) { entry in LauncherItemRow(entry: entry) }
        } else {
            // 用一行承载整张表：`Form` 会实体化它收到的每一行。
            LauncherItemsTable(
                entries: entries, isEnabled: isEnabled,
                visibility: visibility, aliases: aliases, hotKeys: hotKeys, settings: settings,
                recorderFrame: $recorderFrame
            )
            .overlay(alignment: .topLeading) { recorderStandIn }
        }
    }

    /// 已打开的录制器的锚点无法离开其宿主行，因此在此重新发布其边界。
    @ViewBuilder
    private var recorderStandIn: some View {
        if let recorderFrame {
            Color.clear
                .frame(width: recorderFrame.width, height: recorderFrame.height)
                .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) { $0 }
                .position(x: recorderFrame.midX, y: recorderFrame.midY)
                .allowsHitTesting(false)
        }
    }
}

/// 单个启动器条目的行；由表格单元格承载，并在列表滚动时接收新的条目。
struct LauncherItemRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(
            title: entry.name,
            labelOpacity: visibility.isItemVisible(entry) ? 1 : 0.45
        ) {
            // 加上键值，使复用的单元格能在首帧就加载新条目的图标。
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
                .id(entry.iconKey)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(format: settings.text(LauncherKey.showInLauncherFormat), entry.name))
        }
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
