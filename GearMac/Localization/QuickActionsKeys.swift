// 文件职责：QuickActions（快速操作）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 快速操作功能所有用户可见文案的键。
enum QuickActionsKey: String, LocalizableKey {
    // 内置动作标题
    case builtInFixGrammar = "quickActions.builtIn.fixGrammar"
    case builtInRewrite = "quickActions.builtIn.rewrite"
    case builtInTranslate = "quickActions.builtIn.translate"
    case builtInSummarize = "quickActions.builtIn.summarize"
    case builtInDecide = "quickActions.builtIn.decide"

    // 内置动作进行中文案
    case progressFixGrammar = "quickActions.progress.fixGrammar"
    case progressRewrite = "quickActions.progress.rewrite"
    case progressTranslate = "quickActions.progress.translate"
    case progressSummarize = "quickActions.progress.summarize"
    case progressDecide = "quickActions.progress.decide"

    // 设置页
    case settingsEnableTitle = "quickActions.settings.enable.title"
    case settingsEnableSubtitle = "quickActions.settings.enable.subtitle"
    case settingsAccessTitle = "quickActions.settings.access.title"
    case settingsAccessSubtitle = "quickActions.settings.access.subtitle"
    case settingsOpenSystemSettings = "quickActions.settings.openSystemSettings"
    case settingsAddAction = "quickActions.settings.addAction"
    case settingsFooter = "quickActions.settings.footer"
    case settingsEditNamed = "quickActions.settings.editNamed"
    case settingsReplace = "quickActions.settings.replace"
    case settingsPreview = "quickActions.settings.preview"
    case settingsResultAccessibility = "quickActions.settings.resultAccessibility"
    case settingsShowInLauncher = "quickActions.settings.showInLauncher"
    case settingsModel = "quickActions.settings.model"
    case settingsModelDetail = "quickActions.settings.modelDetail"
    case settingsEffort = "quickActions.settings.effort"
    case settingsModelFooter = "quickActions.settings.modelFooter"
    case settingsTranslateTo = "quickActions.settings.translateTo"
    case settingsSameAsMac = "quickActions.settings.sameAsMac"
    case settingsTranslateFooter = "quickActions.settings.translateFooter"
    case settingsAlwaysShown = "quickActions.settings.alwaysShown"
    case settingsCustomizeTitle = "quickActions.settings.customizeTitle"
    case settingsCustomizeSubtitle = "quickActions.settings.customizeSubtitle"
    case settingsUseDefault = "quickActions.settings.useDefault"
    case settingsCancel = "quickActions.settings.cancel"
    case settingsSave = "quickActions.settings.save"

    // 自建动作编辑器
    case customNewTitle = "quickActions.custom.newTitle"
    case customEditTitle = "quickActions.custom.editTitle"
    case customSubtitle = "quickActions.custom.subtitle"
    case customName = "quickActions.custom.name"
    case customNamePlaceholder = "quickActions.custom.namePlaceholder"
    case customIcon = "quickActions.custom.icon"
    case customAutomatic = "quickActions.custom.automatic"
    case customCustom = "quickActions.custom.custom"
    case customInstructions = "quickActions.custom.instructions"
    case customInstructionsPlaceholder = "quickActions.custom.instructionsPlaceholder"
    case customInstructionsFooter = "quickActions.custom.instructionsFooter"
    case customDelete = "quickActions.custom.delete"

    // 模型选择
    case modelLabel = "quickActions.model.label"
    case modelInherited = "quickActions.model.inherited"
    case modelEffort = "quickActions.model.effort"

    // 结果面板
    case panelWorking = "quickActions.panel.working"
    case panelNotDownloaded = "quickActions.panel.notDownloaded"
    case panelDownloadHint = "quickActions.panel.downloadHint"
    case panelOpenLanguageRegion = "quickActions.panel.openLanguageRegion"
    case panelDismiss = "quickActions.panel.dismiss"
    case panelCopy = "quickActions.panel.copy"
    case panelReplace = "quickActions.panel.replace"

    // 协调器
    case enableTitle = "quickActions.enable.title"
    case enableMessage = "quickActions.enable.message"
    case enableContinue = "quickActions.enable.continue"
    case deleteTitle = "quickActions.delete.title"
    case deleteMessage = "quickActions.delete.message"
    case deleteAction = "quickActions.delete.action"
    case errorSaveChange = "quickActions.error.saveChange"
    case refusalTitle = "quickActions.refusal.title"
    case refusalMessage = "quickActions.refusal.message"
    case refusalOpenSystemSettings = "quickActions.refusal.openSystemSettings"
    case messageApplied = "quickActions.message.applied"
    case messageCopiedInstead = "quickActions.message.copiedInstead"

    // 选区失败
    case failureNeedsAccessibility = "quickActions.failure.needsAccessibility"
    case failureNoTarget = "quickActions.failure.noTarget"
    case failureUnreadableApp = "quickActions.failure.unreadableApp"
    case failureNoSelection = "quickActions.failure.noSelection"
    case failureTooLong = "quickActions.failure.tooLong"

    // 自建动作错误
    case errorEmptyName = "quickActions.error.emptyName"
    case errorEmptyInstructions = "quickActions.error.emptyInstructions"
    case errorInvalidCharacter = "quickActions.error.invalidCharacter"
    case errorStorageUnavailable = "quickActions.error.storageUnavailable"

    // 翻译失败
    case translateUndetectable = "quickActions.translate.undetectable"
    case translateUnsupported = "quickActions.translate.unsupported"
    case translateNotInstalled = "quickActions.translate.notInstalled"
    case translateFailed = "quickActions.translate.failed"

    static let table: [String: L10nEntry] = [
        QuickActionsKey.builtInFixGrammar.rawValue: L10nEntry("Fix Grammar", "修正语法"),
        QuickActionsKey.builtInRewrite.rawValue: L10nEntry("Rewrite", "改写"),
        QuickActionsKey.builtInTranslate.rawValue: L10nEntry("Translate", "翻译"),
        QuickActionsKey.builtInSummarize.rawValue: L10nEntry("Summarize", "总结"),
        QuickActionsKey.builtInDecide.rawValue: L10nEntry("Decide", "判定"),

        QuickActionsKey.progressFixGrammar.rawValue: L10nEntry("Fixing Grammar…", "正在修正语法…"),
        QuickActionsKey.progressRewrite.rawValue: L10nEntry("Rewriting…", "正在改写…"),
        QuickActionsKey.progressTranslate.rawValue: L10nEntry("Translating…", "正在翻译…"),
        QuickActionsKey.progressSummarize.rawValue: L10nEntry("Summarizing…", "正在总结…"),
        QuickActionsKey.progressDecide.rawValue: L10nEntry("Deciding…", "正在判定…"),

        QuickActionsKey.settingsEnableTitle.rawValue: L10nEntry(
            "Enable Quick Actions", "启用快速操作"),
        QuickActionsKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Act on selected text. Nothing is read until you press a shortcut.",
            "对选中文本执行操作。在你按下快捷键前不会读取任何内容。"),
        QuickActionsKey.settingsAccessTitle.rawValue: L10nEntry(
            "Accessibility permission required", "需要辅助功能权限"),
        QuickActionsKey.settingsAccessSubtitle.rawValue: L10nEntry(
            "Needed to read your selection.", "读取选中文本需要它。"),
        QuickActionsKey.settingsOpenSystemSettings.rawValue: L10nEntry(
            "Open System Settings", "打开系统设置"),
        QuickActionsKey.settingsAddAction.rawValue: L10nEntry("Add Quick Action", "添加快速操作"),
        QuickActionsKey.settingsFooter.rawValue: L10nEntry(
            "Replace writes into your document, and undo restores it. Preview shows a panel first.",
            "“替换”会写回你的文档，撤销可恢复；“预览”会先显示一个面板。"),
        QuickActionsKey.settingsEditNamed.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        QuickActionsKey.settingsReplace.rawValue: L10nEntry("Replace", "替换"),
        QuickActionsKey.settingsPreview.rawValue: L10nEntry("Preview", "预览"),
        QuickActionsKey.settingsResultAccessibility.rawValue: L10nEntry(
            "What %@ does with its result", "%@ 如何处理其结果"),
        QuickActionsKey.settingsShowInLauncher.rawValue: L10nEntry(
            "Show %@ in launcher", "在启动器中显示 %@"),
        QuickActionsKey.settingsModel.rawValue: L10nEntry("Model", "模型"),
        QuickActionsKey.settingsModelDetail.rawValue: L10nEntry(
            "Unless an action sets its own.", "除非某个动作设置了自己的模型。"),
        QuickActionsKey.settingsEffort.rawValue: L10nEntry("Reasoning effort", "推理强度"),
        QuickActionsKey.settingsModelFooter.rawValue: L10nEntry(
            "Separate from AI Chat's, so frequent use needn't bill an API.",
            "与 AI 聊天分开设置，频繁使用也无需为 API 付费。"),
        QuickActionsKey.settingsTranslateTo.rawValue: L10nEntry("Translate to", "翻译为"),
        QuickActionsKey.settingsSameAsMac.rawValue: L10nEntry(
            "Same as this Mac", "与此 Mac 相同"),
        QuickActionsKey.settingsTranslateFooter.rawValue: L10nEntry(
            "Apple's translator, on this Mac. A language downloads on first use.",
            "使用此 Mac 上的 Apple 翻译器。首次使用时下载语言。"),
        QuickActionsKey.settingsAlwaysShown.rawValue: L10nEntry(
            "Always shown in a panel", "始终在面板中显示"),
        QuickActionsKey.settingsCustomizeTitle.rawValue: L10nEntry("Customize %@", "自定义 %@"),
        QuickActionsKey.settingsCustomizeSubtitle.rawValue: L10nEntry(
            "Tell GearMac how you want %@ to handle your selected text.",
            "告诉 GearMac 你希望 %@ 如何处理选中的文本。"),
        QuickActionsKey.settingsUseDefault.rawValue: L10nEntry("Use Default", "使用默认值"),
        QuickActionsKey.settingsCancel.rawValue: L10nEntry("Cancel", "取消"),
        QuickActionsKey.settingsSave.rawValue: L10nEntry("Save", "保存"),

        QuickActionsKey.customNewTitle.rawValue: L10nEntry("New Quick Action", "新建快速操作"),
        QuickActionsKey.customEditTitle.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        QuickActionsKey.customSubtitle.rawValue: L10nEntry(
            "GearMac sends your selected text to the model with these instructions.",
            "GearMac 会按这些指令把选中的文本发送给模型。"),
        QuickActionsKey.customName.rawValue: L10nEntry("Name", "名称"),
        QuickActionsKey.customNamePlaceholder.rawValue: L10nEntry("Make Concise", "精简"),
        QuickActionsKey.customIcon.rawValue: L10nEntry("Icon", "图标"),
        QuickActionsKey.customAutomatic.rawValue: L10nEntry("Automatic", "自动"),
        QuickActionsKey.customCustom.rawValue: L10nEntry("Custom", "自定义"),
        QuickActionsKey.customInstructions.rawValue: L10nEntry("Instructions", "指令"),
        QuickActionsKey.customInstructionsPlaceholder.rawValue: L10nEntry(
            "Make the text more concise, keeping the writer's voice and meaning.",
            "让文本更简洁，同时保留作者的语气和含义。"),
        QuickActionsKey.customInstructionsFooter.rawValue: L10nEntry(
            "GearMac always tells the model to return only the transformed text, and to treat "
                + "your selection as material rather than as instructions.",
            "GearMac 始终要求模型只返回转换后的文本，并把你的选中内容视为素材而非指令。"),
        QuickActionsKey.customDelete.rawValue: L10nEntry("Delete", "删除"),

        QuickActionsKey.modelLabel.rawValue: L10nEntry("Model", "模型"),
        QuickActionsKey.modelInherited.rawValue: L10nEntry(
            "Same as Quick Actions", "与快速操作相同"),
        QuickActionsKey.modelEffort.rawValue: L10nEntry("Reasoning effort", "推理强度"),

        QuickActionsKey.panelWorking.rawValue: L10nEntry("Working…", "处理中…"),
        QuickActionsKey.panelNotDownloaded.rawValue: L10nEntry(
            "%@ hasn't been downloaded yet.", "%@ 尚未下载。"),
        QuickActionsKey.panelDownloadHint.rawValue: L10nEntry(
            "Click **Translation Languages…** in Language & Region, then download it.",
            "在“语言与地区”中点按 **翻译语言…**，然后下载它。"),
        QuickActionsKey.panelOpenLanguageRegion.rawValue: L10nEntry(
            "Open Language & Region", "打开语言与地区"),
        QuickActionsKey.panelDismiss.rawValue: L10nEntry("Dismiss", "关闭"),
        QuickActionsKey.panelCopy.rawValue: L10nEntry("Copy", "复制"),
        QuickActionsKey.panelReplace.rawValue: L10nEntry("Replace", "替换"),

        QuickActionsKey.enableTitle.rawValue: L10nEntry("Enable Quick Actions?", "启用快速操作？"),
        QuickActionsKey.enableMessage.rawValue: L10nEntry(
            "GearMac needs the Accessibility permission to read the text you have selected in "
                + "other apps and replace it. Nothing is read until you press a shortcut.",
            "GearMac 需要辅助功能权限，才能读取你在其他应用中选中的文本并替换它。"
                + "在你按下快捷键前不会读取任何内容。"),
        QuickActionsKey.enableContinue.rawValue: L10nEntry("Continue", "继续"),
        QuickActionsKey.deleteTitle.rawValue: L10nEntry("Delete “%@”?", "删除“%@”？"),
        QuickActionsKey.deleteMessage.rawValue: L10nEntry(
            "Its instructions, shortcut and learned ranking go with it.",
            "它的指令、快捷键和学习排序也会一并移除。"),
        QuickActionsKey.deleteAction.rawValue: L10nEntry("Delete", "删除"),
        QuickActionsKey.errorSaveChange.rawValue: L10nEntry(
            "Couldn’t Save the Change", "无法保存更改"),
        QuickActionsKey.refusalTitle.rawValue: L10nEntry(
            "Quick Actions can't read your selection", "快速操作无法读取你的选中内容"),
        QuickActionsKey.refusalMessage.rawValue: L10nEntry(
            "GearMac needs the Accessibility permission to read the text you have selected and "
                + "replace it. If GearMac is already listed, switch it off and on again — a "
                + "rebuilt app keeps a stale entry.",
            "GearMac 需要辅助功能权限，才能读取你选中的文本并替换它。如果 GearMac 已在列表中，"
                + "请将其关闭再重新打开——重新构建的应用会保留过期条目。"),
        QuickActionsKey.refusalOpenSystemSettings.rawValue: L10nEntry(
            "Open System Settings", "打开系统设置"),
        QuickActionsKey.messageApplied.rawValue: L10nEntry("%@ applied", "已应用 %@"),
        QuickActionsKey.messageCopiedInstead.rawValue: L10nEntry(
            "%@ couldn't replace the selection — copied instead", "%@ 无法替换选中内容——已改为复制"),

        QuickActionsKey.failureNeedsAccessibility.rawValue: L10nEntry(
            "GearMac needs the Accessibility permission to read the selected text.",
            "GearMac 需要辅助功能权限才能读取选中的文本。"),
        QuickActionsKey.failureNoTarget.rawValue: L10nEntry(
            "Select text in another app first.", "请先在其他应用中选中文本。"),
        QuickActionsKey.failureUnreadableApp.rawValue: L10nEntry(
            "%@ doesn't share its text with GearMac.", "%@ 不会向 GearMac 提供其文本。"),
        QuickActionsKey.failureNoSelection.rawValue: L10nEntry(
            "Select some text first.", "请先选中一些文本。"),
        QuickActionsKey.failureTooLong.rawValue: L10nEntry(
            "That selection is too long to work on.", "选中的内容太长，无法处理。"),

        QuickActionsKey.errorEmptyName.rawValue: L10nEntry(
            "Give the action a name.", "请为该操作命名。"),
        QuickActionsKey.errorEmptyInstructions.rawValue: L10nEntry(
            "Tell the model what the action should do.", "请告诉模型该操作要做什么。"),
        QuickActionsKey.errorInvalidCharacter.rawValue: L10nEntry(
            "The name contains a character GearMac can't store.", "名称包含 GearMac 无法保存的字符。"),
        QuickActionsKey.errorStorageUnavailable.rawValue: L10nEntry(
            "GearMac couldn't save to its actions file.", "GearMac 无法保存到其操作文件。"),

        QuickActionsKey.translateUndetectable.rawValue: L10nEntry(
            "The language of the selected text could not be identified.", "无法识别所选文本的语言。"),
        QuickActionsKey.translateUnsupported.rawValue: L10nEntry(
            "Apple's translator does not support this language pair.",
            "Apple 翻译器不支持该语言对。"),
        QuickActionsKey.translateNotInstalled.rawValue: L10nEntry(
            "%@ needs to be downloaded before it can be used.", "%@ 需要先下载才能使用。"),
        QuickActionsKey.translateFailed.rawValue: L10nEntry(
            "The text could not be translated.", "无法翻译该文本。")
    ]
}
