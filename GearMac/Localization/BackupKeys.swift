// 文件职责：备份与恢复功能的本地化键与中英词表（设置页、类别、结果文案、确认与错误）。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 备份面板、类别选择、结果文案、确认弹窗与错误提示的键。
enum BackupKey: String, LocalizableKey {
    // 导出区
    case exportSection = "backup.export.section"
    case exportSubtitle = "backup.export.subtitle"
    case buttonExport = "backup.button.export"
    // 导入区
    case importSection = "backup.import.section"
    case buttonChoose = "backup.button.choose"
    case buttonImport = "backup.button.import"
    case backupFileHint = "backup.backupFile.hint"
    case backupFileUnreadable = "backup.backupFile.unreadable"
    // Raycast 导入区
    case raycastSection = "backup.raycast.section"
    case raycastFileHint = "backup.raycast.fileHint"
    case raycastFileIsExport = "backup.raycast.fileIsExport"
    case raycastFileNotExport = "backup.raycast.fileNotExport"
    case passphrase = "backup.passphrase"
    case passphrasePrompt = "backup.passphrase.prompt"
    case raycastRunning = "backup.raycast.running"
    case raycastQuit = "backup.raycast.quit"
    case raycastUnsetShortcuts = "backup.raycast.unsetShortcuts"
    // 设置文件区
    case settingsFileSection = "backup.settingsFile.section"
    case settingsFileShowInFinder = "backup.settingsFile.showInFinder"
    case settingsFileDescription = "backup.settingsFile.description"

    // 全选/取消全选
    case selectAll = "backup.selectAll"
    case deselectAll = "backup.deselectAll"
    case categoryCount = "backup.category.count"

    // 备份类别
    case categoryConfiguration = "backup.category.configuration"
    case categoryClipboard = "backup.category.clipboard"
    case categorySnippets = "backup.category.snippets"
    case categoryNotes = "backup.category.notes"
    case categoryLearning = "backup.category.learning"
    case countClips = "backup.count.clips"
    case countSnippets = "backup.count.snippets"
    case countNotes = "backup.count.notes"
    case countRecords = "backup.count.records"

    // Raycast 导入选项
    case optionShortcuts = "backup.raycast.option.shortcuts"
    case optionFavorites = "backup.raycast.option.favorites"
    case optionAliases = "backup.raycast.option.aliases"
    case optionEmojiSkinTone = "backup.raycast.option.emojiSkinTone"
    case optionLaunchAtLogin = "backup.raycast.option.launchAtLogin"
    case optionMenuBarIcon = "backup.raycast.option.menuBarIcon"
    case optionClipboardHistory = "backup.raycast.option.clipboardHistory"
    case optionSnippets = "backup.raycast.option.snippets"
    case optionQuicklinks = "backup.raycast.option.quicklinks"
    case optionPopToRoot = "backup.raycast.option.popToRoot"
    case optionCompactMode = "backup.raycast.option.compactMode"

    // 结果文案
    case textNothingSelected = "backup.text.nothingSelected"
    case textSaved = "backup.text.saved"
    case textImagesUnavailable = "backup.text.imagesUnavailable"
    case textNothingToImport = "backup.text.nothingToImport"
    case textSnippetsNeedEnabling = "backup.text.snippetsNeedEnabling"
    case textRestartAfterImport = "backup.text.restartAfterImport"
    case textImportedClipboard = "backup.text.importedClipboard"
    case textImportedSnippetOne = "backup.text.importedSnippetOne"
    case textImportedSnippetMany = "backup.text.importedSnippetMany"
    case textImportedQuicklinkOne = "backup.text.importedQuicklinkOne"
    case textImportedQuicklinkMany = "backup.text.importedQuicklinkMany"
    case textCouldntImportSnippets = "backup.text.couldntImportSnippets"
    case textCouldntImportQuicklinks = "backup.text.couldntImportQuicklinks"
    case textImported = "backup.text.imported"
    case textApplied = "backup.text.applied"
    case textPartCount = "backup.text.partCount"
    case textListSeparator = "backup.text.listSeparator"
    case problemSnippets = "backup.problem.snippets"

    // 应用类别名词
    case partSettings = "backup.part.settings"
    case partShortcuts = "backup.part.shortcuts"
    case partFavorites = "backup.part.favorites"
    case partHiddenItems = "backup.part.hiddenItems"
    case partAliases = "backup.part.aliases"
    case partPinnedEmoji = "backup.part.pinnedEmoji"
    case partCustomCommands = "backup.part.customCommands"
    case partQuicklinks = "backup.part.quicklinks"
    case partWindowLayouts = "backup.part.windowLayouts"
    case partRooms = "backup.part.rooms"
    case partCustomWindowSizes = "backup.part.customWindowSizes"

    // 对话框
    case dialogBackupExported = "backup.dialog.backupExported"
    case dialogExportFailed = "backup.dialog.exportFailed"
    case dialogBackupImported = "backup.dialog.backupImported"
    case dialogImportFailed = "backup.dialog.importFailed"
    case confirmImportCommandsTitle = "backup.confirm.importCommandsTitle"
    case confirmImportCommandsMessage = "backup.confirm.importCommandsMessage"
    case confirmSettingsFileTitle = "backup.confirm.settingsFileTitle"
    case confirmSettingsFileMessage = "backup.confirm.settingsFileMessage"
    case confirmImport = "backup.confirm.import"
    case confirmReplace = "backup.confirm.replace"
    case confirmCancel = "backup.confirm.cancel"
    case countCustomCommandOne = "backup.count.customCommandOne"
    case countCustomCommandMany = "backup.count.customCommandMany"
    case countGlobalShortcutOne = "backup.count.globalShortcutOne"
    case countGlobalShortcutMany = "backup.count.globalShortcutMany"

    // 错误
    case errorCannotWrite = "backup.error.cannotWrite"
    case errorCannotRead = "backup.error.cannotRead"
    case errorUnsupportedFormat = "backup.error.unsupportedFormat"
    case errorNotRaycastFile = "backup.error.notRaycastFile"
    case errorIncorrectPassphrase = "backup.error.incorrectPassphrase"
    case errorCorrupt = "backup.error.corrupt"
    case errorTooLarge = "backup.error.tooLarge"

    static let table: [String: L10nEntry] = [
        BackupKey.exportSection.rawValue: L10nEntry("Export Backup", "导出备份"),
        BackupKey.exportSubtitle.rawValue: L10nEntry(
            "The ticked items, as one .gearmac file.", "所选项目打包为一个 .gearmac 文件。"),
        BackupKey.buttonExport.rawValue: L10nEntry("Export…", "导出…"),
        BackupKey.importSection.rawValue: L10nEntry("Backup File", "备份文件"),
        BackupKey.buttonChoose.rawValue: L10nEntry("Choose…", "选择…"),
        BackupKey.buttonImport.rawValue: L10nEntry("Import", "导入"),
        BackupKey.backupFileHint.rawValue: L10nEntry(
            "A .gearmac file exported from GearMac.", "从 GearMac 导出的 .gearmac 文件。"),
        BackupKey.backupFileUnreadable.rawValue: L10nEntry(
            "%@ — couldn't be read", "%@ — 无法读取"),
        BackupKey.raycastSection.rawValue: L10nEntry("Raycast Export", "Raycast 导出文件"),
        BackupKey.raycastFileHint.rawValue: L10nEntry(
            "A .rayconfig file from Raycast 2.0 or later.",
            "Raycast 2.0 或更高版本导出的 .rayconfig 文件。"),
        BackupKey.raycastFileIsExport.rawValue: L10nEntry(
            "%@ — Raycast export", "%@ — Raycast 导出文件"),
        BackupKey.raycastFileNotExport.rawValue: L10nEntry(
            "%@ — not a Raycast export", "%@ — 不是 Raycast 导出文件"),
        BackupKey.passphrase.rawValue: L10nEntry("Passphrase", "口令"),
        BackupKey.passphrasePrompt.rawValue: L10nEntry("Export password", "导出密码"),
        BackupKey.raycastRunning.rawValue: L10nEntry(
            "Raycast is running — quit it to avoid hotkey conflicts.",
            "Raycast 正在运行 — 退出它以避免快捷键冲突。"),
        BackupKey.raycastQuit.rawValue: L10nEntry("Quit Raycast", "退出 Raycast"),
        BackupKey.raycastUnsetShortcuts.rawValue: L10nEntry(
            "Unset matching Raycast shortcuts to avoid conflicts.",
            "取消匹配的 Raycast 快捷键以避免冲突。"),
        BackupKey.settingsFileSection.rawValue: L10nEntry(
            "Sync settings file", "同步 settings 文件"),
        BackupKey.settingsFileShowInFinder.rawValue: L10nEntry(
            "Show in Finder", "在访达中显示"),
        BackupKey.settingsFileDescription.rawValue: L10nEntry(
            "Settings changed here are written to the file, and edits to it apply here.",
            "在此处更改的设置会写入文件，对文件的编辑也会应用到这里。"),

        BackupKey.selectAll.rawValue: L10nEntry("Select All", "全选"),
        BackupKey.deselectAll.rawValue: L10nEntry("Deselect All", "取消全选"),
        BackupKey.categoryCount.rawValue: L10nEntry("%d %@", "%d %@"),

        BackupKey.categoryConfiguration.rawValue: L10nEntry(
            "Settings & Shortcuts", "设置与快捷键"),
        BackupKey.categoryClipboard.rawValue: L10nEntry("Clipboard History", "剪贴板历史"),
        BackupKey.categorySnippets.rawValue: L10nEntry("Snippets", "片段"),
        BackupKey.categoryNotes.rawValue: L10nEntry("Notes", "笔记"),
        BackupKey.categoryLearning.rawValue: L10nEntry("Launcher Learning", "启动器学习数据"),
        BackupKey.countClips.rawValue: L10nEntry("clips", "条记录"),
        BackupKey.countSnippets.rawValue: L10nEntry("snippets", "个片段"),
        BackupKey.countNotes.rawValue: L10nEntry("notes", "条笔记"),
        BackupKey.countRecords.rawValue: L10nEntry("records", "条记录"),

        BackupKey.optionShortcuts.rawValue: L10nEntry("Shortcuts", "快捷键"),
        BackupKey.optionFavorites.rawValue: L10nEntry("Favorites", "收藏"),
        BackupKey.optionAliases.rawValue: L10nEntry("Aliases", "别名"),
        BackupKey.optionEmojiSkinTone.rawValue: L10nEntry("Emoji skin tone", "Emoji 肤色"),
        BackupKey.optionLaunchAtLogin.rawValue: L10nEntry("Launch at login", "登录时启动"),
        BackupKey.optionMenuBarIcon.rawValue: L10nEntry("Menu-bar icon", "菜单栏图标"),
        BackupKey.optionClipboardHistory.rawValue: L10nEntry(
            "Clipboard history", "剪贴板历史"),
        BackupKey.optionSnippets.rawValue: L10nEntry("Snippets", "片段"),
        BackupKey.optionQuicklinks.rawValue: L10nEntry("Quicklinks", "快速链接"),
        BackupKey.optionPopToRoot.rawValue: L10nEntry("Pop to root", "返回根界面"),
        BackupKey.optionCompactMode.rawValue: L10nEntry("Compact mode", "紧凑模式"),

        BackupKey.textNothingSelected.rawValue: L10nEntry(
            "Nothing was selected.", "未选择任何内容。"),
        BackupKey.textSaved.rawValue: L10nEntry("Saved %@.", "已保存 %@。"),
        BackupKey.textImagesUnavailable.rawValue: L10nEntry(
            "%d images were unavailable and skipped.", "有 %d 张图片不可用，已跳过。"),
        BackupKey.textNothingToImport.rawValue: L10nEntry(
            "Nothing to import from this file.", "此文件中没有可导入的内容。"),
        BackupKey.textSnippetsNeedEnabling.rawValue: L10nEntry(
            "Turn on Snippets in Settings to use their keywords.",
            "请在设置中开启「片段」以使用其关键字。"),
        BackupKey.textRestartAfterImport.rawValue: L10nEntry(
            "Quit and reopen GearMac to finish.", "退出并重新打开 GearMac 以完成。"),
        BackupKey.textImportedClipboard.rawValue: L10nEntry(
            "Imported %d clipboard entries.", "已导入 %d 条剪贴板记录。"),
        BackupKey.textImportedSnippetOne.rawValue: L10nEntry(
            "Imported 1 snippet.", "已导入 1 个片段。"),
        BackupKey.textImportedSnippetMany.rawValue: L10nEntry(
            "Imported %d snippets.", "已导入 %d 个片段。"),
        BackupKey.textImportedQuicklinkOne.rawValue: L10nEntry(
            "Imported 1 quicklink.", "已导入 1 个快速链接。"),
        BackupKey.textImportedQuicklinkMany.rawValue: L10nEntry(
            "Imported %d quicklinks.", "已导入 %d 个快速链接。"),
        BackupKey.textCouldntImportSnippets.rawValue: L10nEntry(
            "Couldn’t import snippets: %@", "无法导入片段：%@"),
        BackupKey.textCouldntImportQuicklinks.rawValue: L10nEntry(
            "Couldn’t import quicklinks: %@", "无法导入快速链接：%@"),
        BackupKey.textImported.rawValue: L10nEntry("Imported %@.", "已导入 %@。"),
        BackupKey.textApplied.rawValue: L10nEntry("Applied %@.", "已应用 %@。"),
        BackupKey.textPartCount.rawValue: L10nEntry("%d %@", "%d %@"),
        BackupKey.textListSeparator.rawValue: L10nEntry(", ", "、"),
        BackupKey.problemSnippets.rawValue: L10nEntry(
            "Couldn't import snippets: %@", "无法导入片段：%@"),

        BackupKey.partSettings.rawValue: L10nEntry("settings", "项设置"),
        BackupKey.partShortcuts.rawValue: L10nEntry("shortcuts", "个快捷键"),
        BackupKey.partFavorites.rawValue: L10nEntry("favorites", "个收藏"),
        BackupKey.partHiddenItems.rawValue: L10nEntry("hidden items", "个隐藏项"),
        BackupKey.partAliases.rawValue: L10nEntry("aliases", "个别名"),
        BackupKey.partPinnedEmoji.rawValue: L10nEntry(
            "pinned emoji and symbols", "个固定的表情与符号"),
        BackupKey.partCustomCommands.rawValue: L10nEntry("custom commands", "个自定义命令"),
        BackupKey.partQuicklinks.rawValue: L10nEntry("quicklinks", "个快速链接"),
        BackupKey.partWindowLayouts.rawValue: L10nEntry("window layouts", "个窗口布局"),
        BackupKey.partRooms.rawValue: L10nEntry("rooms", "个空间"),
        BackupKey.partCustomWindowSizes.rawValue: L10nEntry(
            "custom window sizes", "个自定义窗口尺寸"),

        BackupKey.dialogBackupExported.rawValue: L10nEntry("Backup Exported", "备份已导出"),
        BackupKey.dialogExportFailed.rawValue: L10nEntry("Export Failed", "导出失败"),
        BackupKey.dialogBackupImported.rawValue: L10nEntry("Backup Imported", "备份已导入"),
        BackupKey.dialogImportFailed.rawValue: L10nEntry("Import Failed", "导入失败"),
        BackupKey.confirmImportCommandsTitle.rawValue: L10nEntry(
            "Import executable commands?", "导入可执行命令？"),
        BackupKey.confirmImportCommandsMessage.rawValue: L10nEntry(
            "This backup contains %@ and %@. Custom commands can run arbitrary shell code. Only import files you trust.",
            "此备份包含 %@ 和 %@。自定义命令可以运行任意 shell 代码。请只导入你信任的文件。"),
        BackupKey.confirmSettingsFileTitle.rawValue: L10nEntry(
            "Import the existing settings file?", "导入现有的 settings 文件？"),
        BackupKey.confirmSettingsFileMessage.rawValue: L10nEntry(
            "%@ already exists. Import applies its settings here; Replace overwrites it with the current ones.",
            "%@ 已存在。「导入」会把其中的设置应用到这里；「替换」会用当前设置覆盖它。"),
        BackupKey.confirmImport.rawValue: L10nEntry("Import", "导入"),
        BackupKey.confirmReplace.rawValue: L10nEntry("Replace", "替换"),
        BackupKey.confirmCancel.rawValue: L10nEntry("Cancel", "取消"),
        BackupKey.countCustomCommandOne.rawValue: L10nEntry(
            "1 custom command", "1 个自定义命令"),
        BackupKey.countCustomCommandMany.rawValue: L10nEntry(
            "%d custom commands", "%d 个自定义命令"),
        BackupKey.countGlobalShortcutOne.rawValue: L10nEntry(
            "1 global shortcut", "1 个全局快捷键"),
        BackupKey.countGlobalShortcutMany.rawValue: L10nEntry(
            "%d global shortcuts", "%d 个全局快捷键"),

        BackupKey.errorCannotWrite.rawValue: L10nEntry(
            "Couldn't write the backup file.", "无法写入备份文件。"),
        BackupKey.errorCannotRead.rawValue: L10nEntry(
            "This file isn't a GearMac backup, or it's damaged.",
            "这不是 GearMac 备份文件，或者已损坏。"),
        BackupKey.errorUnsupportedFormat.rawValue: L10nEntry(
            "This backup was made by a different version of GearMac (format %d, expected %d). Export again from the Mac that has your setup.",
            "此备份由其他版本的 GearMac 创建（格式 %d，预期 %d）。请从保存有你配置的 Mac 上重新导出。"),
        BackupKey.errorNotRaycastFile.rawValue: L10nEntry(
            "This doesn't look like a Raycast export (.rayconfig).",
            "这不像 Raycast 导出文件（.rayconfig）。"),
        BackupKey.errorIncorrectPassphrase.rawValue: L10nEntry(
            "Incorrect passphrase, or the file is corrupted.", "口令不正确，或文件已损坏。"),
        BackupKey.errorCorrupt.rawValue: L10nEntry(
            "The Raycast export could not be read.", "无法读取 Raycast 导出文件。"),
        BackupKey.errorTooLarge.rawValue: L10nEntry(
            "This export is too large to import. Clear some Raycast clipboard history and export again.",
            "此导出文件过大，无法导入。请清理一些 Raycast 剪贴板历史后重新导出。"),
    ]
}
