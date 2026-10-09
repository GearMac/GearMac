// 文件职责：CustomCommands（自定义命令）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 自定义命令功能所有用户可见文案的键。
enum CustomCommandsKey: String, LocalizableKey {
    // 设置页
    case settingsSearchPrompt = "customCommands.settings.searchPrompt"
    case settingsEnableTitle = "customCommands.settings.enable.title"
    case settingsEnableSubtitle = "customCommands.settings.enable.subtitle"
    case settingsEmpty = "customCommands.settings.empty"
    case settingsAdd = "customCommands.settings.add"
    case settingsImport = "customCommands.settings.import"
    case settingsImportFooter = "customCommands.settings.importFooter"
    case deleteTitle = "customCommands.delete.title"
    case deleteMessage = "customCommands.delete.message"
    case deleteAction = "customCommands.delete.action"

    // 设置页：行
    case rowEdit = "customCommands.row.edit"
    case rowEditNamed = "customCommands.row.editNamed"
    case rowDelete = "customCommands.row.delete"
    case rowDeleteNamed = "customCommands.row.deleteNamed"
    case rowEnabled = "customCommands.row.enabled"
    case rowEnableNamed = "customCommands.row.enableNamed"

    // 编辑器面板
    case editorAddTitle = "customCommands.editor.addTitle"
    case editorEditTitle = "customCommands.editor.editTitle"
    case editorName = "customCommands.editor.name"
    case editorNamePlaceholder = "customCommands.editor.namePlaceholder"
    case editorCommand = "customCommands.editor.command"
    case editorCommandExample = "customCommands.editor.commandExample"
    case editorLoadShellEnv = "customCommands.editor.loadShellEnv"
    case editorLoadShellEnvDetail = "customCommands.editor.loadShellEnvDetail"
    case editorNeedsConfirmation = "customCommands.editor.needsConfirmation"
    case editorNeedsConfirmationDetail = "customCommands.editor.needsConfirmationDetail"
    case editorShowConfirmation = "customCommands.editor.showConfirmation"
    case editorShowConfirmationDetail = "customCommands.editor.showConfirmationDetail"
    case editorShowOutput = "customCommands.editor.showOutput"
    case editorShowOutputDetail = "customCommands.editor.showOutputDetail"
    case editorIcon = "customCommands.editor.icon"
    case editorAutomatic = "customCommands.editor.automatic"
    case editorCustom = "customCommands.editor.custom"
    case editorRunIn = "customCommands.editor.runIn"
    case editorRunInPlaceholder = "customCommands.editor.runInPlaceholder"
    case editorChoose = "customCommands.editor.choose"
    case editorRunInHint = "customCommands.editor.runInHint"
    case editorChoosePrompt = "customCommands.editor.choosePrompt"
    case editorChooseMessage = "customCommands.editor.chooseMessage"
    case editorArguments = "customCommands.editor.arguments"
    case editorAddArgument = "customCommands.editor.addArgument"
    case editorArgumentsEmptyHint = "customCommands.editor.argumentsEmptyHint"
    case editorArgumentsHint = "customCommands.editor.argumentsHint"
    case editorArgumentNamePlaceholder = "customCommands.editor.argumentNamePlaceholder"
    case editorOptional = "customCommands.editor.optional"
    case editorRemoveArgument = "customCommands.editor.removeArgument"
    case editorCancel = "customCommands.editor.cancel"
    case editorSave = "customCommands.editor.save"

    // 输出窗口
    case outputTitle = "customCommands.output.title"
    case outputStop = "customCommands.output.stop"
    case outputRunAgain = "customCommands.output.runAgain"
    case outputRunning = "customCommands.output.running"
    case outputOpenSettings = "customCommands.output.openSettings"
    case outputCopy = "customCommands.output.copy"
    case durationSeconds = "customCommands.duration.seconds"
    case durationWholeSeconds = "customCommands.duration.wholeSeconds"
    case durationMinutesSeconds = "customCommands.duration.minutesSeconds"

    // 协调器：导入
    case importNothing = "customCommands.import.nothing"
    case importNoneFound = "customCommands.import.noneFound"
    case importAllPresent = "customCommands.import.allPresent"
    case importDone = "customCommands.import.done"
    case importPanelPrompt = "customCommands.import.panelPrompt"
    case importPanelMessage = "customCommands.import.panelMessage"
    case importConfirmOne = "customCommands.import.confirmOne"
    case importConfirmMany = "customCommands.import.confirmMany"
    case importConfirmMessage = "customCommands.import.confirmMessage"
    case importConfirmAction = "customCommands.import.confirmAction"
    case importSummaryOne = "customCommands.import.summaryOne"
    case importSummaryMany = "customCommands.import.summaryMany"
    case importSummarySkipped = "customCommands.import.summarySkipped"

    // 协调器：运行与结果
    case runConfirmMessage = "customCommands.run.confirmMessage"
    case runConfirmAction = "customCommands.run.confirmAction"
    case reportRan = "customCommands.report.ran"
    case reportFailedTitle = "customCommands.report.failedTitle"
    case reportOpenSettings = "customCommands.report.openSettings"
    case summaryShellFailed = "customCommands.summary.shellFailed"
    case summaryStopped = "customCommands.summary.stopped"
    case summaryFinished = "customCommands.summary.finished"
    case summaryExited = "customCommands.summary.exited"
    case shellEnvHint = "customCommands.hint.shellEnv"

    // 校验错误
    case errorEmptyName = "customCommands.error.emptyName"
    case errorEmptyCommand = "customCommands.error.emptyCommand"
    case errorDuplicateName = "customCommands.error.duplicateName"
    case errorInvalidCharacter = "customCommands.error.invalidCharacter"

    static let table: [String: L10nEntry] = [
        CustomCommandsKey.settingsSearchPrompt.rawValue: L10nEntry("Search commands…", "搜索命令…"),
        CustomCommandsKey.settingsEnableTitle.rawValue: L10nEntry(
            "Enable custom commands", "启用自定义命令"),
        CustomCommandsKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Run as you in /bin/zsh, or the interpreter a #! line names. Use full executable paths.",
            "以你的身份在 /bin/zsh 中运行，或使用 #! 行指定的解释器。请使用完整的可执行文件路径。"),
        CustomCommandsKey.settingsEmpty.rawValue: L10nEntry(
            "No custom commands yet.", "暂无自定义命令。"),
        CustomCommandsKey.settingsAdd.rawValue: L10nEntry("Add Custom Command", "添加自定义命令"),
        CustomCommandsKey.settingsImport.rawValue: L10nEntry(
            "Import Raycast Scripts", "导入 Raycast 脚本"),
        CustomCommandsKey.settingsImportFooter.rawValue: L10nEntry(
            "Import reads a folder of Raycast script commands.", "导入会读取一个包含 Raycast 脚本命令的文件夹。"),
        CustomCommandsKey.deleteTitle.rawValue: L10nEntry("Delete “%@”?", "删除“%@”？"),
        CustomCommandsKey.deleteMessage.rawValue: L10nEntry(
            "Its global shortcut and launcher references will also be removed.",
            "它的全局快捷键和启动器引用也会一并移除。"),
        CustomCommandsKey.deleteAction.rawValue: L10nEntry("Delete", "删除"),

        CustomCommandsKey.rowEdit.rawValue: L10nEntry("Edit Command", "编辑命令"),
        CustomCommandsKey.rowEditNamed.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        CustomCommandsKey.rowDelete.rawValue: L10nEntry("Delete Command", "删除命令"),
        CustomCommandsKey.rowDeleteNamed.rawValue: L10nEntry("Delete %@", "删除 %@"),
        CustomCommandsKey.rowEnabled.rawValue: L10nEntry("Enabled", "启用"),
        CustomCommandsKey.rowEnableNamed.rawValue: L10nEntry("Enable %@", "启用 %@"),

        CustomCommandsKey.editorAddTitle.rawValue: L10nEntry("Add Custom Command", "添加自定义命令"),
        CustomCommandsKey.editorEditTitle.rawValue: L10nEntry("Edit Custom Command", "编辑自定义命令"),
        CustomCommandsKey.editorName.rawValue: L10nEntry("Name", "名称"),
        CustomCommandsKey.editorNamePlaceholder.rawValue: L10nEntry("Sleep Displays", "让显示器休眠"),
        CustomCommandsKey.editorCommand.rawValue: L10nEntry("Command", "命令"),
        CustomCommandsKey.editorCommandExample.rawValue: L10nEntry(
            "Example: /usr/bin/pmset displaysleepnow", "示例：/usr/bin/pmset displaysleepnow"),
        CustomCommandsKey.editorLoadShellEnv.rawValue: L10nEntry(
            "Load shell environment", "加载 shell 环境"),
        CustomCommandsKey.editorLoadShellEnvDetail.rawValue: L10nEntry(
            "Sources ~/.zshrc for aliases, functions and PATH. Slower to start.",
            "加载 ~/.zshrc 以获取别名、函数和 PATH。启动较慢。"),
        CustomCommandsKey.editorNeedsConfirmation.rawValue: L10nEntry(
            "Needs confirmation", "需要确认"),
        CustomCommandsKey.editorNeedsConfirmationDetail.rawValue: L10nEntry(
            "Ask before running this command.", "运行此命令前先询问。"),
        CustomCommandsKey.editorShowConfirmation.rawValue: L10nEntry(
            "Show confirmation", "显示确认"),
        CustomCommandsKey.editorShowConfirmationDetail.rawValue: L10nEntry(
            "Confirm on screen after the command succeeds.", "命令成功后显示屏幕确认。"),
        CustomCommandsKey.editorShowOutput.rawValue: L10nEntry("Show output", "显示输出"),
        CustomCommandsKey.editorShowOutputDetail.rawValue: L10nEntry(
            "Open a window with everything the command printed when it finishes.",
            "命令结束后打开一个窗口，显示其打印的全部内容。"),
        CustomCommandsKey.editorIcon.rawValue: L10nEntry("Icon", "图标"),
        CustomCommandsKey.editorAutomatic.rawValue: L10nEntry("Automatic", "自动"),
        CustomCommandsKey.editorCustom.rawValue: L10nEntry("Custom", "自定义"),
        CustomCommandsKey.editorRunIn.rawValue: L10nEntry("Run In", "运行目录"),
        CustomCommandsKey.editorRunInPlaceholder.rawValue: L10nEntry("Home folder", "主文件夹"),
        CustomCommandsKey.editorChoose.rawValue: L10nEntry("Choose…", "选取…"),
        CustomCommandsKey.editorRunInHint.rawValue: L10nEntry(
            "The folder the command starts in. Leave empty for your home folder.",
            "命令启动时所在的文件夹。留空则使用你的主文件夹。"),
        CustomCommandsKey.editorChoosePrompt.rawValue: L10nEntry("Choose", "选取"),
        CustomCommandsKey.editorChooseMessage.rawValue: L10nEntry(
            "Choose the folder this command runs in.", "选择此命令运行的文件夹。"),
        CustomCommandsKey.editorArguments.rawValue: L10nEntry("Arguments", "参数"),
        CustomCommandsKey.editorAddArgument.rawValue: L10nEntry("Add", "添加"),
        CustomCommandsKey.editorArgumentsEmptyHint.rawValue: L10nEntry(
            "Add up to three, filled in beside the search field before the command runs.",
            "最多添加三个，在命令运行前于搜索框旁填写。"),
        CustomCommandsKey.editorArgumentsHint.rawValue: L10nEntry(
            "Passed to the command in order as $1, $2 …", "按 $1、$2 …… 的顺序传给命令。"),
        CustomCommandsKey.editorArgumentNamePlaceholder.rawValue: L10nEntry(
            "Argument name", "参数名称"),
        CustomCommandsKey.editorOptional.rawValue: L10nEntry("Optional", "可选"),
        CustomCommandsKey.editorRemoveArgument.rawValue: L10nEntry(
            "Remove this argument", "移除此参数"),
        CustomCommandsKey.editorCancel.rawValue: L10nEntry("Cancel", "取消"),
        CustomCommandsKey.editorSave.rawValue: L10nEntry("Save", "保存"),

        CustomCommandsKey.outputTitle.rawValue: L10nEntry("Command Output", "命令输出"),
        CustomCommandsKey.outputStop.rawValue: L10nEntry("Stop", "停止"),
        CustomCommandsKey.outputRunAgain.rawValue: L10nEntry("Run Again", "再次运行"),
        CustomCommandsKey.outputRunning.rawValue: L10nEntry("Running", "运行中"),
        CustomCommandsKey.outputOpenSettings.rawValue: L10nEntry("Open Settings", "打开设置"),
        CustomCommandsKey.outputCopy.rawValue: L10nEntry("Copy Output", "复制输出"),
        CustomCommandsKey.durationSeconds.rawValue: L10nEntry("%.1fs", "%.1f 秒"),
        CustomCommandsKey.durationWholeSeconds.rawValue: L10nEntry("%ds", "%d 秒"),
        CustomCommandsKey.durationMinutesSeconds.rawValue: L10nEntry("%dm %ds", "%d 分 %d 秒"),

        CustomCommandsKey.importNothing.rawValue: L10nEntry("Nothing to Import", "无可导入内容"),
        CustomCommandsKey.importNoneFound.rawValue: L10nEntry(
            "No Raycast script commands were found in this folder.",
            "此文件夹中未找到 Raycast 脚本命令。"),
        CustomCommandsKey.importAllPresent.rawValue: L10nEntry(
            "Every script in this folder is already in your library.",
            "此文件夹中的每个脚本都已在你的库中。"),
        CustomCommandsKey.importDone.rawValue: L10nEntry("Scripts Imported", "脚本已导入"),
        CustomCommandsKey.importPanelPrompt.rawValue: L10nEntry("Import", "导入"),
        CustomCommandsKey.importPanelMessage.rawValue: L10nEntry(
            "Choose a folder of Raycast script commands.", "选择一个包含 Raycast 脚本命令的文件夹。"),
        CustomCommandsKey.importConfirmOne.rawValue: L10nEntry(
            "Import 1 script?", "导入 1 个脚本？"),
        CustomCommandsKey.importConfirmMany.rawValue: L10nEntry(
            "Import %d scripts?", "导入 %d 个脚本？"),
        CustomCommandsKey.importConfirmMessage.rawValue: L10nEntry(
            "Imported commands run these files with your user account. Only import scripts you trust.",
            "导入的命令会以你的用户身份运行这些文件。请只导入你信任的脚本。"),
        CustomCommandsKey.importConfirmAction.rawValue: L10nEntry("Import", "导入"),
        CustomCommandsKey.importSummaryOne.rawValue: L10nEntry(
            "Imported 1 command.", "已导入 1 个命令。"),
        CustomCommandsKey.importSummaryMany.rawValue: L10nEntry(
            "Imported %d commands.", "已导入 %d 个命令。"),
        CustomCommandsKey.importSummarySkipped.rawValue: L10nEntry(
            " Skipped %d already in your library.", "，跳过 %d 个已在库中的。"),

        CustomCommandsKey.runConfirmMessage.rawValue: L10nEntry(
            "Are you sure you want to run this command?\n\n%@", "确定要运行此命令吗？\n\n%@"),
        CustomCommandsKey.runConfirmAction.rawValue: L10nEntry("Run", "运行"),
        CustomCommandsKey.reportRan.rawValue: L10nEntry("Ran %@", "已运行 %@"),
        CustomCommandsKey.reportFailedTitle.rawValue: L10nEntry("“%@” Failed", "“%@”失败"),
        CustomCommandsKey.reportOpenSettings.rawValue: L10nEntry("Open Settings…", "打开设置…"),
        CustomCommandsKey.summaryShellFailed.rawValue: L10nEntry(
            "The shell could not be started.", "无法启动 shell。"),
        CustomCommandsKey.summaryStopped.rawValue: L10nEntry("Stopped", "已停止"),
        CustomCommandsKey.summaryFinished.rawValue: L10nEntry(
            "Finished successfully.", "已成功完成。"),
        CustomCommandsKey.summaryExited.rawValue: L10nEntry(
            "The command exited with status %d.", "命令以状态 %d 退出。"),
        CustomCommandsKey.shellEnvHint.rawValue: L10nEntry(
            "If this is a shell alias or function, turn on Load Shell Environment for this command.",
            "如果这是 shell 别名或函数，请为此命令开启“加载 shell 环境”。"),

        CustomCommandsKey.errorEmptyName.rawValue: L10nEntry(
            "Enter a name for the command.", "请输入命令的名称。"),
        CustomCommandsKey.errorEmptyCommand.rawValue: L10nEntry(
            "Enter a command to run.", "请输入要运行的命令。"),
        CustomCommandsKey.errorDuplicateName.rawValue: L10nEntry(
            "A custom command with this name already exists.", "已存在同名的自定义命令。"),
        CustomCommandsKey.errorInvalidCharacter.rawValue: L10nEntry(
            "Names and commands cannot contain null characters.", "名称和命令不能包含空字符。")
    ]
}
