// 文件职责：设置 › 扩展面板：总开关、安装入口（商店/GitHub/文件夹/Raycast 导入）、已安装列表与残留文件清理。
// 分层：UI（SwiftUI 视图）；安装、更新、卸载等副作用经 AppCore 的 extensions 与 extensionCoordinator 执行。
import SwiftUI

/// 设置 › 扩展：先是总开关，然后每个扩展一行，可在原处展开。
struct ExtensionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var expanded: String?
    @State private var filter = ""
    @State private var importCandidates: ImportCandidates?
    @State private var browsingStore = false
    @State private var installingFromGitHub = false
    @State private var error: String?
    @State private var updateError: String?
    /// Raycast 已构建但本机尚未安装的扩展，面板每次出现时重新扫描。
    @State private var pending: [RaycastImportCandidate] = []
    /// 批量导入的进度，让三十项的批次有反馈而不是悄无声息。
    @State private var importProgress: (done: Int, total: Int)?
    @State private var importSummary: String?
    /// 清理可回收的空间，已安装集合变化时重新扫描。
    @State private var reclaimable = ExtensionCleanup.Report()

    var body: some View {
        @Bindable var settings = core.settings
        return Form {
            FeatureSwitchSection(
                anchor: .extensionsExtensions,
                enableTitle: "Enable extensions",
                enableSubtitle: "Run Raycast extensions natively.",
                // 启用即意味着同意运行第三方代码，因此 setter 会做确认。
                isEnabled: Binding(
                    get: { settings.extensionsEnabled },
                    set: { core.extensionCoordinator.setExtensionsEnabled($0) }),
                showsInLauncher: $settings.extensionsShowInLauncher,
                showsIcon: true)

            Group {
                install
                library
                compatibility
            }
            .settingsEnabled(settings.extensionsEnabled)

            // 放在启用开关作用域之外：无论扩展是否启用，残留文件都在磁盘上。
            storage
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.extensions)
        .releasesFocusOnOutsideClick()
        // Escape 和 Return 都是离开当前输入框的键盘方式。
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
        // 按 item 驱动：`isPresented` 会用写入前的快照构建面板。
        .settingsEditorPanel(item: $importCandidates) { candidates in
            ExtensionImportPanel(
                candidates: candidates.entries,
                onImport: { chosen in
                    importCandidates = nil
                    Task { await importAll(chosen) }
                },
                onCancel: { importCandidates = nil })
        }
        .settingsEditorPanel(isPresented: $browsingStore) {
            ExtensionStorePanel(onClose: { browsingStore = false })
        }
        .settingsEditorPanel(isPresented: $installingFromGitHub) {
            ExtensionGitHubPanel(onClose: { installingFromGitHub = false })
        }
        .onChange(of: navigation.scrollRequest, initial: true) {
            if case .row(.extensionsInstalled, let name)? = navigation.scrollRequest?.target {
                (expanded, filter) = (name, "")
            }
        }
        .onChange(of: core.extensions.installed.count) { Task { await measureReclaimable() } }
        .task {
            await core.extensions.refresh()
            await measureReclaimable()
            await findPending()
            await core.extensions.checkForUpdates()
        }
    }

    // MARK: - Compatibility

    /// 兼容性说明区块：列出当前支持与尚不支持的 Raycast 能力。
    private var compatibility: some View {
        Section {
            SettingsRow(
                title: "What works",
                subtitle:
                    "List, detail, form, grid, no-view and menu-bar commands, plus preferences, storage and OAuth.",
                subtitleLineLimit: 2
            ) {
                ExtensionSettingsIcon(systemName: "checkmark.circle")
            } trailing: {
                EmptyView()
            }
            SettingsRow(
                title: "What doesn't, yet",
                subtitle: "Raycast's OAuth proxy, and its AI, browser and window services.",
                subtitleLineLimit: 2
            ) {
                ExtensionSettingsIcon(systemName: "xmark.circle")
            } trailing: {
                EmptyView()
            }
        } header: {
            SettingsSectionHeader(.extensionsCompatibility)
        }
    }

    // MARK: - The library

    /// 已安装扩展列表区块：包含更新行、过滤框与逐项展开配置。
    private var library: some View {
        Section {
            if !core.extensions.updates.isEmpty {
                updatesRow
            }
            if core.extensions.installed.isEmpty {
                Text("Nothing installed yet.")
                    .foregroundStyle(.secondary)
            } else {
                if core.extensions.installed.count > 3 {
                    SettingsFilterField(prompt: "Filter extensions…", query: $filter)
                }
                if matching.isEmpty {
                    Text("No extension matches \u{201C}\(filter)\u{201D}.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(matching) { installed in
                        let name = installed.manifest.name
                        ExtensionDisclosure(
                            installed: installed,
                            isExpanded: expanded == name,
                            isUpdating: core.extensions.updating.contains(name),
                            onToggle: { expanded = expanded == name ? nil : name },
                            onUpdate: core.extensions.updates[name] == nil ? nil : { update([name]) },
                            onUninstall: {
                                core.extensionCoordinator.confirmUninstall(installed)
                            })
                    }
                }
            }
        } header: {
            SettingsSectionHeader(anchor: .extensionsInstalled) {
                Text(
                    core.extensions.installed.isEmpty
                        ? "Installed" : "Installed (\(core.extensions.installed.count))")
            }
        } footer: {
            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 与逐行更新并列出现在列表上方，让整批更新只需按一次。
    private var updatesRow: some View {
        SettingsRow(
            title: "Updates available",
            subtitle: listed(core.extensions.updates.values.map(\.title)) + "."
        ) {
            ExtensionSettingsIcon(systemName: "arrow.down.circle")
        } trailing: {
            if core.extensions.updating.isEmpty {
                Button("Update All") { update(core.extensions.updates.keys.sorted()) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// 更新指定扩展，失败时把失败名单写入错误提示。
    private func update(_ names: [String]) {
        updateError = nil
        Task {
            let failed = await core.extensions.update(names)
            if !failed.isEmpty { updateError = "Couldn't update \(failed.joined(separator: ", "))." }
        }
    }

    /// 按过滤词筛选已安装扩展（匹配扩展标题或命令标题）。
    private var matching: [InstalledExtension] {
        guard !filter.isEmpty else { return core.extensions.installed }
        return core.extensions.installed.filter { entry in
            entry.title.localizedCaseInsensitiveContains(filter)
                || entry.manifest.commands.contains {
                    $0.title.localizedCaseInsensitiveContains(filter)
                }
        }
    }

    /// 用行而不是菜单：每种安装路径的方式都不一样。
    private var install: some View {
        Section {
            SettingsRow(
                title: "Search extensions", subtitle: "Ready-built from the Raycast Store.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "magnifyingglass")
            } trailing: {
                Button("Search…") { browsingStore = true }
            }
            SettingsRow(
                title: "Install from GitHub",
                subtitle: "Builds from source with your package manager.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "hammer")
            } trailing: {
                Button("Install…") { installingFromGitHub = true }
            }
            // 这是该行的一种状态，而不是一张卡片：它与旁边的按钮做同一件事。
            SettingsRow(
                title: "Import from Raycast", subtitle: importSubtitle,
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "arrow.down.doc")
            } trailing: {
                if importProgress != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Import…", action: openImport)
                        .disabled(!raycastAvailable)
                    if !pending.isEmpty {
                        Button("Import All") { Task { await importAll(pending.map(\.installed)) } }
                    }
                }
            }
            SettingsRow(
                title: "Add from folder",
                subtitle: "A folder with package.json and built commands.",
                anchor: .extensionsInstall
            ) {
                ExtensionSettingsIcon(systemName: "folder")
            } trailing: {
                Button("Choose…", action: addFolder)
            }
        } header: {
            SettingsSectionHeader(.extensionsInstall)
        } footer: {
            if let error {
                // 显示在触发它的按钮下方。
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 安装会自行清理，因此正常使用时这一行没有可操作的内容。
    private var storage: some View {
        Section {
            SettingsRow(
                title: "Leftover files", subtitle: reclaimableSubtitle,
                anchor: .extensionsStorage
            ) {
                ExtensionSettingsIcon(systemName: "internaldrive")
            } trailing: {
                Button("Clean Up…") {
                    Task {
                        await core.extensionCoordinator.confirmCleanup(reclaimable)
                        await measureReclaimable()
                    }
                }
                .disabled(reclaimable.isEmpty)
            }
        } header: {
            SettingsSectionHeader(.extensionsStorage)
        }
    }

    /// 清理行的副标题：无可清理项时说明，否则给出可回收空间与条目数。
    private var reclaimableSubtitle: String {
        guard !reclaimable.isEmpty else { return "Nothing to clean up." }
        let items = reclaimable.items == 1 ? "1 item" : "\(reclaimable.items) items"
        return "Reclaims \(ExtensionCleanup.formatted(bytes: reclaimable.bytes)) from \(items)."
    }

    /// 在主线程之外执行：统计需要遍历 `node_modules`，那是数万个文件。
    private func measureReclaimable() async {
        let installed = Set(core.extensions.installed.map(\.manifest.name))
        let roots = ExtensionCleanup.defaultRoots()
        reclaimable = await Task.detached(priority: .utility) {
            ExtensionCleanup.reclaimable(installed: installed, in: roots)
        }.value
    }

    /// 导入行的副标题：反映导入进度、结果摘要、Raycast 可用性或待导入数量。
    private var importSubtitle: String {
        if let importProgress {
            return "Importing \(importProgress.done) of \(importProgress.total)…"
        }
        if let importSummary { return importSummary }
        guard raycastAvailable else {
            return "No Raycast install found in ~/.config."
        }
        guard !pending.isEmpty else {
            return "Copies what Raycast has already built."
        }
        return "\(pending.count) not here yet — \(listed(pending.map(\.installed.title)))."
    }

    /// 按顺序取前三项再加上数量，让长列表也能塞进一行副标题。
    private func listed(_ titles: [String]) -> String {
        let sorted = titles.sorted {
            $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
        }
        let names = sorted.prefix(3).joined(separator: ", ")
        return sorted.count > 3 ? "\(names) and \(sorted.count - 3) more" : names
    }

    /// 本机是否存在 Raycast 的扩展构建目录。
    private var raycastAvailable: Bool {
        ExtensionCatalog.raycastExtensionsDirectory() != nil
    }

    // MARK: - Adding

    /// 扫描本地 Raycast 安装并打开导入面板。
    private func openImport() {
        Task {
            importCandidates = ImportCandidates(
                entries: await core.extensions.raycastImportCandidates())
        }
    }

    /// 通过打开面板选择一个或多个本地扩展文件夹并逐个安装。
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        Task {
            error = nil
            for url in panel.urls {
                do {
                    try await core.extensions.install(from: url)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    /// 批量导入选中项，实时更新进度并在结束后汇总成功与失败。
    private func importAll(_ chosen: [InstalledExtension]) async {
        error = nil
        importSummary = nil
        importProgress = (0, chosen.count)
        let failed = await core.extensions.importAllFromRaycast(chosen) { done in
            importProgress = (done, chosen.count)
        }
        importProgress = nil
        await findPending()
        let imported = chosen.count - failed.count
        if failed.isEmpty {
            importSummary = "Imported \(imported) extension\(imported == 1 ? "" : "s")."
        } else {
            importSummary = "Imported \(imported); \(failed.count) failed."
            error = "Couldn't import \(failed.joined(separator: ", "))."
        }
    }

    /// 重新扫描 Raycast 已构建但本机尚未安装的扩展。
    private func findPending() async {
        guard core.settings.extensionsEnabled, raycastAvailable else {
            pending = []
            return
        }
        pending = await core.extensions.raycastImportCandidates().filter { !$0.isInstalled }
    }
}

/// 扩展设置行左侧的统一图标。
private struct ExtensionSettingsIcon: View {
    let systemName: String
    private let iconSize = Theme.Size.settingsRowIcon + Theme.Spacing.xs

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs))
            .foregroundStyle(.primary)
            .frame(width: iconSize, height: iconSize)
    }
}

/// 摘要行；展开时它的设置显示在内嵌卡片上——用分隔线和填充，不用玻璃效果。
private struct ExtensionDisclosure: View {
    let installed: InstalledExtension
    let isExpanded: Bool
    let isUpdating: Bool
    let onToggle: () -> Void
    /// 仅当商店有更新版本时才非 nil。
    let onUpdate: (() -> Void)?
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded {
                settings
                    .padding(.top, Theme.Spacing.lg)
            }
        }
    }

    /// 折叠状态下的摘要行：图标、标题、命令数与作者，以及更新和卸载控件。
    private var summary: some View {
        SettingsRow(title: installed.title, subtitle: subtitle) {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        } trailing: {
            if isUpdating {
                ProgressView().controlSize(.small)
            } else if let onUpdate {
                Button("Update", action: onUpdate)
            }
            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Uninstall")
            .accessibilityLabel("Uninstall \(installed.title)")
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        // 整行都可点击切换：`DisclosureGroup` 只会响应它的展开箭头。
        .contentShape(.rect)
        .onTapGesture(perform: onToggle)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isExpanded ? "Hide \(installed.title) settings" : "Configure \(installed.title)"
        )
        .id(SettingsTarget.row(.extensionsInstalled, installed.manifest.name))
    }

    /// 每组内容共用一个 `Grid`：分成多个 Grid 会让各列宽度不一致，控件被孤立排布。
    private var settings: some View {
        Grid(
            alignment: .leading, horizontalSpacing: Theme.Spacing.lg,
            verticalSpacing: Theme.Spacing.md
        ) {
            // 不设小标题：这两项属于同一个概念，且放在最前，免得被 19 条命令淹没。
            ExtensionLauncherRow(installed: installed)
            ExtensionIconRow(installed: installed)

            if !installed.manifest.preferences.isEmpty {
                rule
                heading("Preferences")
                ForEach(
                    Array(installed.manifest.preferences.enumerated()), id: \.element.name
                ) { index, schema in
                    if index > 0 { rule }
                    ExtensionPreferenceRow(
                        extensionName: installed.manifest.name, schema: schema)
                }
            }

            rule
            heading(installed.manifest.commands.count == 1 ? "Command" : "Commands")
            ForEach(Array(installed.manifest.commands.enumerated()), id: \.element.id) {
                index, command in
                if index > 0 { rule }
                CommandRows(installed: installed, command: command)
            }
        }
        // 缩进到该行图标之后，使这些设置读起来属于上方那一行。
        .padding(.leading, Theme.Size.rowIcon + Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 比面板的区块标题低一级；这里没有任何地方把标题设成全大写。
    private func heading(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .gridCellColumns(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    /// 与应用中其他多行分组一致的行间细线。
    private var rule: some View {
        GridRow {
            Divider()
                .gridCellColumns(2)
        }
    }

    /// 摘要行的副标题：命令数，若有作者则附加作者。
    private var subtitle: String {
        let count = installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        let author = installed.manifest.author
        return author.isEmpty ? commands : "\(commands) · \(author)"
    }
}

/// 卡片式的一行：标签在左、控件在右，列由外层 `Grid` 对齐。
private struct SettingsCardRow<Control: View>: View {
    /// 宽度足以容纳路径输入框，也是该列所有控件共享的右边界。
    static var controlWidth: CGFloat { 200 }

    let title: String
    var detail: String?
    /// 属于上方那一行（而非当前分组）的行所使用的左缩进。
    var indent: CGFloat = 0
    /// 关于该行的简短事实，紧贴名称显示而不是放在控件列。
    var badge: String?
    /// 传 `nil` 时让两个 120pt 的输入框自行定宽；其余行沿用共享的 200pt 槽位。
    var controlWidth: CGFloat? = Self.controlWidth
    @ViewBuilder var control: Control

    var body: some View {
        GridRow(alignment: .center) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.controlSurface, in: .capsule)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridColumnAlignment(.leading)
            // 所有控件统一宽度：否则开关、下拉和输入框的右边缘会参差不齐。
            control
                .frame(width: controlWidth, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

/// 一条命令：标题行上是别名、快捷键与启动器勾选框，下面跟着它自己的偏好设置。
private struct CommandRows: View {
    let installed: InstalledExtension
    let command: ExtensionCommand
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(VisibilityStore.self) private var visibility

    /// 关于该命令的一条事实，因此以徽标形式贴在名称旁，而不是用警告色。
    private var badge: String? { command.mode == .menuBar ? "Menu Bar" : nil }

    /// 该命令在扩展内的引用标识，用于菜单栏等按命令定位的能力。
    private var reference: ExtensionCommandRef {
        ExtensionCommandRef(extensionName: installed.manifest.name, commandName: command.name)
    }

    var body: some View {
        let entry = installed.launcherEntry(for: command)
        let isVisible = visibility.isItemVisible(entry)
        SettingsCardRow(
            title: command.title, detail: command.description, badge: badge, controlWidth: nil
        ) {
            HStack(spacing: Theme.Spacing.lg) {
                // 被隐藏或未发布的命令不会进入排序，因此在这里输入别名不会匹配到任何内容。
                AliasField(entry: entry)
                    .settingsEnabled(settings.extensionsShowInLauncher && isVisible)
                // 按命令而不是按扩展设置：快捷键必须落到一个具体目标上才能运行。
                ShortcutRecorder(action: .extensionCommand(entryID: entry.id))
                Toggle(
                    "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Show in launcher")
                .accessibilityLabel("Show \(command.title) in launcher")
            }
        }
        if command.mode == .menuBar {
            SettingsCardRow(title: "Show in menu bar", indent: Theme.Spacing.lg) {
                Toggle(
                    "Show in menu bar",
                    isOn: Binding(
                        get: { core.extensionCoordinator.menuBarIsEnabled(reference) },
                        set: { core.extensionCoordinator.setMenuBarEnabled($0, reference: reference) })
                )
                .labelsHidden()
            }
        }
        // 缩进到它所属命令之下：同一缩进下，从属关系就是阅读顺序。
        ForEach(command.preferences, id: \.name) { schema in
            ExtensionPreferenceRow(
                extensionName: installed.manifest.name, schema: schema, indent: Theme.Spacing.lg)
        }
        // 与调度器使用同一判断：无法解析的间隔不会出现开关。
        if ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval),
            let schedule = command.intervalRaw
        {
            ExtensionRefreshRow(
                extensionName: installed.manifest.name, command: command, schedule: schedule,
                indent: Theme.Spacing.lg)
        }
    }
}

/// 某个 `no-view` 命令的后台刷新：对应 Raycast 的 interval 偏好，存储在本地。
private struct ExtensionRefreshRow: View {
    let extensionName: String
    let command: ExtensionCommand
    let schedule: String
    var indent: CGFloat = 0
    @Environment(AppCore.self) private var core

    /// 共享的相对时间格式化器（如「2 分钟前」）。
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        let info = core.extensions.backgroundInfo(extension: extensionName, command: command.name)
        SettingsCardRow(title: "Background refresh", detail: detail(for: info), indent: indent) {
            Toggle(
                "",
                isOn: Binding(
                    get: { info.backgroundEnabled }, set: { setEnabled($0) })
            )
            .labelsHidden()
        }
    }

    /// 后台刷新行的副标题：刷新周期、上次刷新时间与最近错误。
    private func detail(for info: ExtensionCommandMetadata) -> String {
        var detail = "Every \(schedule)."
        if let lastRun = info.lastRun {
            detail += " Last refresh \(Self.relative.localizedString(for: lastRun, relativeTo: Date()))."
        } else {
            detail += " Hasn't refreshed yet."
        }
        if let error = info.lastError {
            detail += " Last error: \(ExtensionRefreshPolicy.headline(error))."
        }
        return detail
    }

    /// 写入该命令的后台刷新开关。
    private func setEnabled(_ enabled: Bool) {
        core.extensions.setBackgroundEnabled(enabled, extension: extensionName, command: command.name)
    }
}

/// 隐藏某个扩展的全部命令：一次导入可能加入上百个，全局开关又过于粗暴。
private struct ExtensionLauncherRow: View {
    let installed: InstalledExtension
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entries = installed.manifest.commands.map(installed.launcherEntry)
        let visibleCount = entries.count(where: visibility.isItemVisible)
        SettingsCardRow(title: "Show in launcher", detail: detail(visible: visibleCount, of: entries.count)) {
            // 用闭包而不是 `set: setVisible`：把 actor 隔离的方法直接当 setter 会导致 IRGen 崩溃。
            Toggle(
                "",
                isOn: Binding(
                    get: { visibleCount > 0 },
                    set: { visible in entries.forEach { visibility.setItemVisible(visible, for: $0) } })
            )
            .labelsHidden()
        }
    }

    /// 启动器可见性的说明：全部隐藏或部分可见时给出提示，全部可见时为 nil。
    private func detail(visible: Int, of total: Int) -> String? {
        switch visible {
        case 0: "Hidden. Shortcuts still work."
        case total: nil
        default: "\(visible) of \(total) commands."
        }
    }
}

/// 启动器图标，以及替换它的选择器。
private struct ExtensionIconRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// 从 store 读取而非 manager：选择结果发布到 store，两者都观察它。
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        SettingsCardRow(
            title: "Launcher icon",
            detail: appearance == nil ? nil : "Custom icon."
        ) {
            HStack(spacing: Theme.Spacing.md) {
                preview
                Button("Change…") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        ExtensionAppearancePicker(
                            current: appearance ?? .fallback,
                            isCustom: appearance != nil,
                            onPick: { core.extensions.setAppearance($0, for: installed.manifest.name) },
                            onReset: {
                                core.extensions.setAppearance(nil, for: installed.manifest.name)
                            })
                    }
            }
        }
    }

    /// 图标预览：有自定义外观时画 `SymbolTile`，否则显示扩展自带图标。
    @ViewBuilder
    private var preview: some View {
        if let appearance {
            SymbolTile(symbol: appearance.symbol, tint: appearance.tint, side: Theme.Size.rowIcon)
        } else {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        }
    }
}

/// 一个偏好设置控件，值被持久化，便于命令通过 `getPreferenceValues()` 读取。
private struct ExtensionPreferenceRow: View {
    let extensionName: String
    let schema: ExtensionPreferenceSchema
    var indent: CGFloat = 0
    @Environment(AppCore.self) private var core
    @State private var text: String = ""
    @State private var flag: Bool = false

    /// 读写扩展偏好设置所用的存储。
    private var storage: ExtensionStorage { core.extensions.storage }

    var body: some View {
        SettingsCardRow(title: schema.displayTitle, detail: detail, indent: indent) {
            control
        }
        .onAppear(perform: load)
    }

    /// 偏好项说明，必填时附加「Required.」提示。
    private var detail: String? {
        let description = schema.description ?? ""
        guard schema.required else { return description }
        return description.isEmpty ? "Required." : description + " Required."
    }

    /// 按偏好类型渲染对应控件（复选框、下拉、密码、文件/目录/应用选择、文本框）。
    @ViewBuilder
    private var control: some View {
        switch schema.kind {
        case .checkbox:
            Toggle(schema.label ?? "", isOn: $flag)
                .labelsHidden()
                .onChange(of: flag) { _, value in
                    storage.setPreference(
                        extension: extensionName, key: schema.name, value: .bool(value))
                }
        case .dropdown:
            Picker("", selection: $text) {
                ForEach(schema.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .onChange(of: text) { _, value in save(value) }
        case .password:
            SecureField("", text: $text, prompt: schema.placeholder.map(Text.init))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .pointerStyle(.horizontalText)
                .onChange(of: text) { _, value in save(value) }
        case .file, .directory, .appPicker:
            HStack(spacing: Theme.Spacing.sm) {
                Text(text.isEmpty ? "Not set" : (text as NSString).lastPathComponent)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…", action: choosePath)
            }
        case .textfield:
            TextField("", text: $text, prompt: schema.placeholder.map(Text.init))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .pointerStyle(.horizontalText)
                .onChange(of: text) { _, value in save(value) }
        }
    }

    /// 从存储读取当前值（无值时用 schema 的默认值）填充控件状态。
    private func load() {
        let value =
            storage.preference(extension: extensionName, key: schema.name)
            ?? schema.effectiveDefault
        text = value.stringValue
        flag = value.boolValue
    }

    /// 把字符串值写回存储。
    private func save(_ value: String) {
        storage.setPreference(extension: extensionName, key: schema.name, value: .string(value))
    }

    /// 弹出打开面板选择文件、目录或应用，并把路径写入存储。
    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = schema.kind != .directory
        panel.canChooseDirectories = schema.kind == .directory
        if schema.kind == .appPicker {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = url.path
        save(url.path)
    }
}

/// 来自本地 Raycast 安装的一个导入候选，以及本机是否已安装。
struct RaycastImportCandidate: Identifiable {
    let installed: InstalledExtension
    let isInstalled: Bool

    var id: String { installed.id }
}

/// 一次对本地 Raycast 安装的扫描结果，作为导入面板的展示 item 传递。
private struct ImportCandidates: Identifiable {
    let id = UUID()
    let entries: [RaycastImportCandidate]
}

/// 尚未安装的默认勾选，使常见情况只需按一次。
private struct ExtensionImportPanel: View {
    let candidates: [RaycastImportCandidate]
    let onImport: ([InstalledExtension]) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String> = []
    @State private var seeded = false
    @State private var filter = ""

    /// 尚未安装的候选，默认被勾选。
    private var fresh: [RaycastImportCandidate] { candidates.filter { !$0.isInstalled } }

    /// 三十来行已超过「逐行扫视」优于「过滤」的临界点。
    private var matching: [RaycastImportCandidate] {
        guard !filter.isEmpty else { return candidates }
        return candidates.filter {
            $0.installed.title.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ExtensionSettingsEditorHeader(title: "Import from Raycast", subtitle: subtitle)

            if candidates.count > 6 {
                SettingsFilterField(prompt: "Filter…", query: $filter)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matching) { candidate in
                        // AppKit 会把复选框对齐到标签首行的基线上。
                        HStack(spacing: Theme.Spacing.md) {
                            Toggle("", isOn: binding(for: candidate))
                                .labelsHidden()
                            ExtensionIconView(
                                resolved: candidate.installed.iconPath.map {
                                    ExtensionImage.Resolved(source: .file($0))
                                }, size: Theme.Size.rowIcon)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(candidate.installed.title)
                                Text(detail(for: candidate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onTapGesture { binding(for: candidate).wrappedValue.toggle() }
                    }
                }
                .hideNativeScrollers()
            }
            .overflowFade()
            .thinScrollbar()
            .frame(minHeight: 220, maxHeight: 360)

            HStack {
                // 文案随当前选择变化，因此不会出现点了没反应的按钮。
                Button(allChosen ? "Deselect All" : "Select All") {
                    chosen = allChosen ? [] : Set(candidates.map(\.installed.manifest.name))
                }
                .buttonStyle(
                    ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false)
                )
                .disabled(candidates.isEmpty)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Import \(chosen.isEmpty ? "" : "(\(chosen.count))")") {
                    onImport(
                        candidates.map(\.installed).filter { chosen.contains($0.manifest.name) })
                }
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .extensionSettingsEditorPanelSurface()
        .onAppear {
            // 只执行一次：每次渲染都重新填充会与用户自己的取消勾选相冲突。
            guard !seeded else { return }
            seeded = true
            chosen = Set(fresh.map(\.installed.manifest.name))
        }
    }

    /// 是否所有候选都被勾选。
    private var allChosen: Bool { chosen.count == candidates.count }

    /// 面板副标题：无候选、全部已安装或统计尚未安装数量时的不同说明。
    private var subtitle: String {
        guard !candidates.isEmpty else {
            return "No built extensions found in ~/.config/raycast/extensions."
        }
        guard !fresh.isEmpty else {
            return "Everything Raycast has built is already here. Import one again to update it."
        }
        let count = fresh.count == 1 ? "one" : "\(fresh.count)"
        return "The \(count) you don't have yet \(fresh.count == 1 ? "is" : "are") already ticked. "
            + "Ticking one you have updates it."
    }

    /// 候选项的说明：命令数；已安装时提示勾选可更新。
    private func detail(for candidate: RaycastImportCandidate) -> String {
        let count = candidate.installed.manifest.commands.count
        let commands = "\(count) command\(count == 1 ? "" : "s")"
        return candidate.isInstalled ? "\(commands) · installed — tick to update" : commands
    }

    /// 为某个候选构造读写 `chosen` 集合的 Bool 绑定。
    private func binding(for candidate: RaycastImportCandidate) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(candidate.installed.manifest.name) },
            set: { isOn in
                if isOn {
                    chosen.insert(candidate.installed.manifest.name)
                } else {
                    chosen.remove(candidate.installed.manifest.name)
                }
            })
    }
}

extension InstalledExtension {
    /// `VisibilityStore` 与 `AliasStore` 作为键使用的条目：只会读它的 id，不读它的行。
    fileprivate func launcherEntry(for command: ExtensionCommand) -> AppEntry {
        AppEntry(
            id: ExtensionCommandRef(extensionName: manifest.name, commandName: command.name).entryID,
            name: command.title, url: directory, bundleID: nil, kind: .extensionCommand)
    }
}

extension String {
    /// 按首个字母排序：否则 "(Basic) Bookmarks" 会因开头的括号排到最前。
    fileprivate var sortKey: String {
        String(drop { !$0.isLetter && !$0.isNumber })
    }
}
