// 文件职责：备份与恢复流程的统一入口：导出/打开/应用 GearMac 备份、导入 Raycast 导出，并提供文件选择面板、结果文案与设置文件开关等辅助能力。
// 分层：Service；集中承载副作用与 AppKit 文件面板，相关入口标注为 @MainActor，不负责 Model 层的持久化决策。
import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// 不按渠道区分：UTI 描述的是交换格式，因此 Dev 渠道也必须能读取 stable 渠道导出的文件。
    static let gearmacBackup = UTType(exportedAs: "com.gearmac.backup")
}

/// 备份流程的入口集合，供设置面板与启动器命令共同调用。
@MainActor
enum BackupActions {
    /// Raycast 导入的结果统计，供文案拼装与 UI 反馈使用。
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var snippetsImported: Int
        var snippetsNeedEnabling: Bool
        /// 片段文件写入失败时置位；导入的其余部分仍会照常生效。
        var snippetsError: String?
        var quicklinksImported: Int
        /// 链接库无法打开时置位；导入的其余部分仍会照常生效。
        var quicklinksError: String?
        var missingImages: Int
    }

    // MARK: - GearMac native (own file panels; dialogs come from `AppCore`)

    /// 共享的保存面板：附属型 App 必须先激活，否则面板会出现在其他窗口之后。
    static func chooseSaveLocation(named base: String, type: UTType = .json) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let ext = type.preferredFilenameExtension ?? "json"
        panel.nameFieldStringValue = "\(base)-\(dateStamp()).\(ext)"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// 选择一个 JSON 文件（用于设置等可读数据）。
    static func chooseJSONFile() -> URL? { chooseFile(ofType: .json) }

    /// 选择一个 GearMac 备份文件（`.gearmac`）。
    static func chooseBackupFile() -> URL? { chooseFile(ofType: .gearmacBackup) }

    /// 按指定类型弹出打开面板，返回用户选中的单个文件。
    private static func chooseFile(ofType type: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - GearMac backups

    /// 在主线程之外组装再封装——剪贴板历史可达数 GB。
    static func exportBackup(
        core: AppCore, categories: Set<BackupCategory>
    ) async throws
        -> BackupComposer.Result
    {
        guard let destination = chooseSaveLocation(named: "GearMac", type: .gearmacBackup) else {
            throw CancellationError()
        }
        let plan = BackupComposer.plan(categories, from: core)
        return try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            defer { staging.discard() }
            let result = try BackupComposer.write(plan, into: staging.bundle)
            try BackupArchive.seal(directory: staging.root, into: destination)
            return result
        }.value
    }

    /// 打开归档并读取其中的 manifest，把 staging 留给调用方去应用和清理。
    static func openBackup(at file: URL) async throws -> (BackupStaging, BackupManifest) {
        try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            do {
                try BackupArchive.open(file: file, into: staging.root)
                return (staging, try staging.bundle.readManifest())
            } catch {
                staging.discard()
                throw error
            }
        }.value
    }

    /// 把 staging 中选定类别应用到运行中的 AppCore；涉及可执行命令时先确认，用户取消则返回 nil。
    static func applyBackup(
        _ categories: Set<BackupCategory>, from staging: BackupStaging, to core: AppCore
    ) async -> BackupApplier.Summary? {
        let bundle = staging.bundle
        if categories.contains(.configuration),
            let data = try? Data(contentsOf: bundle.settingsURL),
            let backup = try? SettingsBackup(json: data)
        {
            let commands = backup.customCommands?.count ?? 0
            let shortcuts = backup.hotkeys?.customCommands?.count ?? 0
            guard
                await confirmExecutableImport(
                    core: core, commands: commands, shortcuts: shortcuts)
            else { return nil }
        }
        return await BackupApplier.apply(
            categories, from: bundle, to: core, language: core.settings.language)
    }

    /// 启动器命令没有选择界面，因此导出全部类别；需要挑选类别请到设置面板。
    static func runExportCommand(core: AppCore) async {
        do {
            let result = try await exportBackup(core: core, categories: BackupCategory.all)
            await present(
                core: core,
                title: L10n.string(BackupKey.dialogBackupExported, language: core.settings.language),
                message: exportText(result, language: core.settings.language),
                symbol: exportSymbol, tone: .success)
        } catch is CancellationError {
        } catch {
            await present(
                core: core,
                title: L10n.string(BackupKey.dialogExportFailed, language: core.settings.language),
                message: message(for: error, language: core.settings.language),
                symbol: exportSymbol)
        }
    }

    /// 启动器命令：选择备份文件，应用其中全部类别并弹出结果提示。
    static func runImportCommand(core: AppCore) async {
        guard let file = chooseBackupFile() else { return }
        do {
            let (staging, manifest) = try await openBackup(at: file)
            defer { staging.discard() }
            guard
                let summary = await applyBackup(manifest.categories, from: staging, to: core)
            else { return }
            await present(
                core: core,
                title: L10n.string(BackupKey.dialogBackupImported, language: core.settings.language),
                message: summaryText(summary, language: core.settings.language),
                symbol: importSymbol, tone: .success)
        } catch {
            await present(
                core: core,
                title: L10n.string(BackupKey.dialogImportFailed, language: core.settings.language),
                message: message(for: error, language: core.settings.language),
                symbol: importSymbol)
        }
    }

    // MARK: - Raycast (the pane owns the passphrase field + inline status)

    /// 读取并应用 Raycast 导出：解密后按选项筛选，再分别写入剪贴板、片段、快速链接等 store。
    static func importRaycast(
        core: AppCore, file: URL, passphrase: String, options: RaycastImportOptions = .all
    ) async throws -> RaycastOutcome {
        // 在主线程之外、autoreleasepool 中执行，使庞大的 JSON 树能一次性释放。
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try RaycastImportReader.read(file: file, passphrase: passphrase).selecting(options)
            }
        }.value
        // 只上报而不抛出：它不应中断其余已请求的导入内容。
        var snippetsImported = 0
        var snippetsError: String?
        if !result.snippets.isEmpty {
            do {
                // 先启动 store，使导入的片段能立即被启动器使用。
                if core.settings.snippetsEnabled {
                    await core.snippetsStore.start()
                }
                snippetsImported =
                    try await core.snippetsStore.importSnippets(result.snippets).count
            } catch {
                snippetsError = error.localizedDescription
            }
        }
        var quicklinksImported = 0
        var quicklinksError: String?
        if !result.quicklinks.isEmpty {
            if core.quicklinks.isAvailable {
                quicklinksImported =
                    core.quicklinkCoordinator.addImportedQuicklinks(result.quicklinks).count
                // 打开链接不涉及任何权限类别，因此一旦成功落地链接库就把开关打开。
                if quicklinksImported > 0 { core.settings.quicklinksEnabled = true }
            } else {
                quicklinksError = QuicklinkError.storageUnavailable.errorDescription
            }
        }
        let summary = result.backup.apply(to: core)
        let imported =
            result.clipboard.isEmpty
            ? 0 : core.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary,
            clipboardImported: imported,
            snippetsImported: snippetsImported,
            snippetsNeedEnabling: snippetsImported > 0 && !core.settings.snippetsEnabled,
            snippetsError: snippetsError,
            quicklinksImported: quicklinksImported,
            quicklinksError: quicklinksError,
            missingImages: result.missingImages)
    }

    /// 所有 Raycast 渠道（stable、beta、alpha、internal）共用这个 bundle-id 前缀。
    static let raycastBundleIDPrefix = "com.raycast"

    /// 判断给定 bundle id 是否属于 Raycast（含各发布渠道）。
    static func isRaycastBundleID(_ id: String) -> Bool { id.hasPrefix(raycastBundleIDPrefix) }

    /// 退出正在运行的 Raycast 以避免快捷键冲突；后台辅助进程保持运行。
    static func quitRaycast() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier.map(isRaycastBundleID) == true
            && app.activationPolicy != .prohibited
        {
            app.terminate()
        }
    }

    /// 共享的 `.rayconfig` 文件选择器，供备份面板与引导流程使用。
    static func pickRaycastFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 仅以内存映射方式读取文件头部字节，从而在输入口令之前就能判断文件类型。
    static func isRaycastExport(_ file: URL) -> Bool {
        guard let raw = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
        return RaycastDecoder.isExport(raw)
    }

    // MARK: - Helpers

    /// 汇总导入结果的一句话文案（包含缺失图片的提示）。
    static func summaryText(_ summary: BackupApplier.Summary, language: AppLanguage) -> String {
        let separator = L10n.string(BackupKey.textListSeparator, language: language)
        var parts: [String] = []
        if let settings = summary.settings, let applied = appliedText(settings, language: language) {
            parts.append(applied)
        }
        var imported: [String] = []
        if summary.clipboard > 0 { imported.append(count(summary.clipboard, .countClips, language)) }
        if summary.snippets > 0 { imported.append(count(summary.snippets, .countSnippets, language)) }
        if summary.notes > 0 { imported.append(count(summary.notes, .countNotes, language)) }
        if summary.learning > 0 { imported.append(count(summary.learning, .countRecords, language)) }
        if !imported.isEmpty {
            parts.append(
                String(
                    format: L10n.string(BackupKey.textImported, language: language),
                    imported.joined(separator: separator)))
        }
        if summary.snippetsNeedEnabling {
            parts.append(L10n.string(BackupKey.textSnippetsNeedEnabling, language: language))
        }
        parts.append(contentsOf: summary.problems)
        return parts.isEmpty
            ? L10n.string(BackupKey.textNothingToImport, language: language)
            : parts.joined(separator: " ")
    }

    /// 汇总导出结果的一句话文案（含缺失图片的提示）。
    static func exportText(_ result: BackupComposer.Result, language: AppLanguage) -> String {
        let categories = BackupCategory.ordered(result.manifest.categories)
        let separator = L10n.string(BackupKey.textListSeparator, language: language)
        var text =
            categories.isEmpty
            ? L10n.string(BackupKey.textNothingSelected, language: language)
            : String(
                format: L10n.string(BackupKey.textSaved, language: language),
                categories.map { $0.descriptor.label(language) }.joined(separator: separator))
        if result.missingImages > 0 {
            text +=
                " "
                + String(
                    format: L10n.string(BackupKey.textImagesUnavailable, language: language),
                    result.missingImages)
        }
        return text
    }

    /// 把已知的备份错误类型解析为指定语言的文案；其余退回系统描述。
    static func message(for error: Error, language: AppLanguage) -> String {
        switch error {
        case let failure as BackupArchive.ArchiveError: return failure.message(language)
        case let failure as BackupFormatError: return failure.message(language)
        case let failure as RaycastImportError: return failure.message(language)
        default: return error.localizedDescription
        }
    }

    /// 把数量与本地化的计数单位拼成一句（如「12 clips」）。
    private static func count(_ value: Int, _ noun: BackupKey, _ language: AppLanguage) -> String {
        String(
            format: L10n.string(BackupKey.categoryCount, language: language), value,
            L10n.string(noun, language: language))
    }

    /// 为每个真正发生变更的 Raycast 类别生成一句话，供设置面板与引导流程共用。
    static func raycastText(_ outcome: RaycastOutcome, language: AppLanguage) -> String {
        var parts: [String] = []
        if let applied = appliedText(outcome.summary, language: language) { parts.append(applied) }
        if outcome.clipboardImported > 0 {
            parts.append(
                String(
                    format: L10n.string(BackupKey.textImportedClipboard, language: language),
                    outcome.clipboardImported))
        }
        if outcome.snippetsImported > 0 {
            let key =
                outcome.snippetsImported == 1
                ? BackupKey.textImportedSnippetOne : BackupKey.textImportedSnippetMany
            parts.append(
                String(
                    format: L10n.string(key, language: language), outcome.snippetsImported))
        }
        if outcome.snippetsNeedEnabling {
            parts.append(L10n.string(BackupKey.textSnippetsNeedEnabling, language: language))
        }
        if let snippetsError = outcome.snippetsError {
            parts.append(
                String(
                    format: L10n.string(BackupKey.textCouldntImportSnippets, language: language),
                    snippetsError))
        }
        if outcome.quicklinksImported > 0 {
            let key =
                outcome.quicklinksImported == 1
                ? BackupKey.textImportedQuicklinkOne : BackupKey.textImportedQuicklinkMany
            parts.append(
                String(
                    format: L10n.string(key, language: language), outcome.quicklinksImported))
        }
        if let quicklinksError = outcome.quicklinksError {
            parts.append(
                String(
                    format: L10n.string(BackupKey.textCouldntImportQuicklinks, language: language),
                    quicklinksError))
        }
        var message =
            parts.isEmpty
            ? L10n.string(BackupKey.textNothingToImport, language: language)
            : parts.joined(separator: " ")
        if outcome.missingImages > 0 {
            message +=
                " "
                + String(
                    format: L10n.string(BackupKey.textImagesUnavailable, language: language),
                    outcome.missingImages)
        }
        if !parts.isEmpty {
            message += " " + L10n.string(BackupKey.textRestartAfterImport, language: language)
        }
        return message
    }

    /// 没有任何设置被应用时返回 nil，便于调用方拼合成一句合并文案。
    static func appliedText(_ s: SettingsBackup.ApplySummary, language: AppLanguage) -> String? {
        let separator = L10n.string(BackupKey.textListSeparator, language: language)
        var parts: [String] = []
        func part(_ value: Int, _ noun: BackupKey) {
            parts.append(count(value, noun, language))
        }
        if s.settingsFields > 0 { part(s.settingsFields, .partSettings) }
        if s.hotkeys > 0 { part(s.hotkeys, .partShortcuts) }
        if s.favorites > 0 { part(s.favorites, .partFavorites) }
        if s.hiddenItems > 0 { part(s.hiddenItems, .partHiddenItems) }
        if s.aliases > 0 { part(s.aliases, .partAliases) }
        if s.pinnedEmoji > 0 { part(s.pinnedEmoji, .partPinnedEmoji) }
        if s.customCommands > 0 { part(s.customCommands, .partCustomCommands) }
        if s.quicklinks > 0 { part(s.quicklinks, .partQuicklinks) }
        if s.windowLayouts > 0 { part(s.windowLayouts, .partWindowLayouts) }
        if s.windowRooms > 0 { part(s.windowRooms, .partRooms) }
        if s.customWindowSizes > 0 { part(s.customWindowSizes, .partCustomWindowSizes) }
        guard !parts.isEmpty else { return nil }
        return String(
            format: L10n.string(BackupKey.textApplied, language: language),
            parts.joined(separator: separator))
    }

    // MARK: - Settings file

    /// 当前渠道的 settings.json 路径，格式与设置面板及其对话框展示的一致。
    static var settingsFilePath: String {
        (AppPaths.settingsFile().path as NSString).abbreviatingWithTildeInPath
    }

    /// 在文件已存在时开启镜像会询问以哪一侧为准（导入现有文件或覆盖它）。
    static func setSettingsFileEnabled(_ enabled: Bool, core: AppCore) async {
        guard enabled else { return core.stopSettingsFile() }
        guard FileManager.default.fileExists(atPath: AppPaths.settingsFile().path) else {
            return core.startSettingsFile(importing: false)
        }
        let language = core.settings.language
        let choice = await core.choose(
            title: L10n.string(BackupKey.confirmSettingsFileTitle, language: language),
            message: String(
                format: L10n.string(BackupKey.confirmSettingsFileMessage, language: language),
                settingsFilePath),
            symbol: importSymbol,
            options: [
                DialogAction(title: L10n.string(BackupKey.confirmImport, language: language)),
                DialogAction(
                    title: L10n.string(BackupKey.confirmReplace, language: language), role: .destructive),
                DialogAction(title: L10n.string(BackupKey.confirmCancel, language: language), role: .cancel),
            ],
            defaultIndex: 0)
        switch choice {
        case 0: core.startSettingsFile(importing: true)
        case 1: core.startSettingsFile(importing: false)
        default: break
        }
    }

    /// 在 Finder 中显示当前渠道的 settings.json。
    static func revealSettingsFile() {
        AppLauncher.showInFinder(AppPaths.settingsFile())
    }

    /// 备份包含自定义命令或全局快捷键时，先向用户确认再导入。
    private static func confirmExecutableImport(
        core: AppCore, commands: Int, shortcuts: Int
    ) async
        -> Bool
    {
        guard commands > 0 || shortcuts > 0 else { return true }
        let language = core.settings.language
        let commandText =
            commands == 1
            ? L10n.string(BackupKey.countCustomCommandOne, language: language)
            : String(
                format: L10n.string(BackupKey.countCustomCommandMany, language: language), commands)
        let shortcutText =
            shortcuts == 1
            ? L10n.string(BackupKey.countGlobalShortcutOne, language: language)
            : String(
                format: L10n.string(BackupKey.countGlobalShortcutMany, language: language), shortcuts)
        // 真实警告才用红色图标，按钮保持普通样式：导入不会破坏任何东西。
        return await core.confirm(
            title: L10n.string(BackupKey.confirmImportCommandsTitle, language: language),
            message: String(
                format: L10n.string(BackupKey.confirmImportCommandsMessage, language: language),
                commandText, shortcutText),
            symbol: importSymbol, confirmTitle: L10n.string(BackupKey.confirmImport, language: language),
            confirmRole: .standard)
    }

    /// 生成 `yyyy-MM-dd` 形式的日期戳，用于备份默认文件名。
    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 所有导入对话框使用同一个图标，使整个流程看起来是一件事。
    private static let importSymbol = "square.and.arrow.down"
    private static let exportSymbol = "square.and.arrow.up"

    /// 统一的提示弹窗出口，默认使用 danger 语气。
    private static func present(
        core: AppCore, title: String, message: String, symbol: String, tone: DialogTone = .danger
    ) async {
        await core.showNotice(title: title, message: message, symbol: symbol, tone: tone)
    }
}
