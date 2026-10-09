// 文件职责：语音输入（听写）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 听写设置、模型描述、枚举展示名与运行提示的文案键。
enum DictationKey: String, LocalizableKey {
    // 设置页
    case enableTitle = "dictation.enable.title"
    case enableSubtitle = "dictation.enable.subtitle"
    case micRequiredTitle = "dictation.micRequired.title"
    case micRequiredSubtitle = "dictation.micRequired.subtitle"
    case micGrantAccess = "dictation.mic.grantAccess"
    case micOpenSettings = "dictation.mic.openSettings"
    case shortcutBehavior = "dictation.shortcut.behavior"
    case shortcut = "dictation.shortcut.label"
    case shortcutHoldHint = "dictation.shortcut.holdHint"
    case engine = "dictation.model.engine"
    case model = "dictation.model.label"
    case modelLanguage = "dictation.model.language"
    case modelAuto = "dictation.model.auto"
    case buttonCancel = "dictation.model.cancel"
    case buttonRemove = "dictation.model.remove"
    case buttonDownload = "dictation.model.download"
    case stateDownloading = "dictation.model.downloading"
    case stateInstalled = "dictation.model.installed"
    case stateNotInstalled = "dictation.model.notInstalled"
    case downloadProgress = "dictation.model.downloadProgress"
    case downloadProgressDetail = "dictation.model.downloadProgressDetail"
    case sizeOnDisk = "dictation.model.sizeOnDisk"
    case sizeAboutInstalled = "dictation.model.sizeAboutInstalled"
    case memoryTitle = "dictation.memory.title"
    case memoryFooter = "dictation.memory.footer"
    case outputMicrophone = "dictation.output.microphone"
    case outputNoMicrophone = "dictation.output.noMicrophone"
    case outputSystemDefault = "dictation.output.systemDefault"
    case outputWhenFinished = "dictation.output.whenFinished"
    case outputAdaptCapitalization = "dictation.output.adaptCapitalization"
    case outputAdaptCapitalizationSubtitle = "dictation.output.adaptCapitalizationSubtitle"
    case outputFooter = "dictation.output.footer"

    // 枚举展示名
    case modePushToTalk = "dictation.mode.pushToTalk"
    case modeToggle = "dictation.mode.toggle"
    case destinationPaste = "dictation.destination.paste"
    case destinationCopy = "dictation.destination.copy"
    case destinationBoth = "dictation.destination.both"
    case idleNever = "dictation.idle.never"
    case idleOneMinute = "dictation.idle.oneMinute"
    case idleOneHour = "dictation.idle.oneHour"
    case idleMinutes = "dictation.idle.minutes"

    // 模型描述
    case familyParakeetSummary = "dictation.family.parakeet.summary"
    case familyQwenSummary = "dictation.family.qwen.summary"
    case coverageParakeet = "dictation.model.coverage.parakeet"
    case coverageQwen = "dictation.model.coverage.qwen"
    case summaryRedux = "dictation.model.summary.redux"
    case summaryUltra = "dictation.model.summary.ultra"
    case summaryQwenSmall = "dictation.model.summary.qwenSmall"
    case summaryQwenLarge = "dictation.model.summary.qwenLarge"

    // 运行提示与无障碍
    case micPermissionMessage = "dictation.message.micPermission"
    case holdIssueModifier = "dictation.message.holdIssueModifier"
    case holdIssueConflict = "dictation.message.holdIssueConflict"
    case holdNeedsShortcut = "dictation.message.holdNeedsShortcut"
    case downloadModelFirst = "dictation.message.downloadModelFirst"
    case noSpeechRecorded = "dictation.message.noSpeechRecorded"
    case pasteFailed = "dictation.message.pasteFailed"
    case accessibilityListening = "dictation.accessibility.listening"
    case accessibilityTranscribing = "dictation.accessibility.transcribing"
    case failNoMicrophone = "dictation.fail.noMicrophone"
    case failMicrophoneDenied = "dictation.fail.microphoneDenied"
    case failCaptureUnavailable = "dictation.fail.captureUnavailable"

    static let table: [String: L10nEntry] = [
        DictationKey.enableTitle.rawValue: L10nEntry("Enable Dictation", "启用语音输入"),
        DictationKey.enableSubtitle.rawValue: L10nEntry(
            "Transcribe speech on your Mac with a local model.",
            "使用本地模型在你的 Mac 上转写语音。"),
        DictationKey.micRequiredTitle.rawValue: L10nEntry(
            "Microphone access required", "需要麦克风访问权限"),
        DictationKey.micRequiredSubtitle.rawValue: L10nEntry(
            "Needed to record your dictation.", "录制语音输入所必需。"),
        DictationKey.micGrantAccess.rawValue: L10nEntry("Grant Access…", "授予访问权限…"),
        DictationKey.micOpenSettings.rawValue: L10nEntry(
            "Open System Settings", "打开系统设置"),
        DictationKey.shortcutBehavior.rawValue: L10nEntry("Shortcut behavior", "快捷键行为"),
        DictationKey.shortcut.rawValue: L10nEntry("Shortcut", "快捷键"),
        DictationKey.shortcutHoldHint.rawValue: L10nEntry(
            "Hold a key combination or a single modifier; release it to transcribe. "
                + "Double taps work in toggle mode.",
            "长按一个组合键或单个修饰键，松手即开始转写。切换模式下支持双击。"),
        DictationKey.engine.rawValue: L10nEntry("Engine", "引擎"),
        DictationKey.model.rawValue: L10nEntry("Model", "模型"),
        DictationKey.modelLanguage.rawValue: L10nEntry("Language", "语言"),
        DictationKey.modelAuto.rawValue: L10nEntry("Auto", "自动"),
        DictationKey.buttonCancel.rawValue: L10nEntry("Cancel", "取消"),
        DictationKey.buttonRemove.rawValue: L10nEntry("Remove", "移除"),
        DictationKey.buttonDownload.rawValue: L10nEntry("Download", "下载"),
        DictationKey.stateDownloading.rawValue: L10nEntry("Downloading…", "正在下载…"),
        DictationKey.stateInstalled.rawValue: L10nEntry("Installed", "已安装"),
        DictationKey.stateNotInstalled.rawValue: L10nEntry("Not installed", "未安装"),
        DictationKey.downloadProgress.rawValue: L10nEntry("Download progress", "下载进度"),
        DictationKey.downloadProgressDetail.rawValue: L10nEntry(
            "%@ of %@ MB", "%@ / %@ MB"),
        DictationKey.sizeOnDisk.rawValue: L10nEntry("%@ on disk", "磁盘上占用 %@"),
        DictationKey.sizeAboutInstalled.rawValue: L10nEntry(
            "about %d MB installed", "约 %d MB 已安装"),
        DictationKey.memoryTitle.rawValue: L10nEntry(
            "Release model from memory", "从内存释放模型"),
        DictationKey.memoryFooter.rawValue: L10nEntry(
            "Releasing it when idle frees memory. The next dictation takes a moment longer.",
            "空闲时释放可节省内存。下一次语音输入会稍慢。"),
        DictationKey.outputMicrophone.rawValue: L10nEntry("Microphone", "麦克风"),
        DictationKey.outputNoMicrophone.rawValue: L10nEntry(
            "No microphone available", "没有可用的麦克风"),
        DictationKey.outputSystemDefault.rawValue: L10nEntry("System default", "系统默认"),
        DictationKey.outputWhenFinished.rawValue: L10nEntry("When finished", "完成后"),
        DictationKey.outputAdaptCapitalization.rawValue: L10nEntry(
            "Adapt capitalization", "适配大小写"),
        DictationKey.outputAdaptCapitalizationSubtitle.rawValue: L10nEntry(
            "Match the first letter to the text before the cursor.",
            "根据光标前的文本匹配首字母大小写。"),
        DictationKey.outputFooter.rawValue: L10nEntry(
            "Press Return to finish dictating or Escape to cancel. Protected fields may refuse insertion.",
            "按回车结束语音输入，按 Escape 取消。受保护字段可能拒绝插入。"),

        DictationKey.modePushToTalk.rawValue: L10nEntry("Hold to talk", "按住说话"),
        DictationKey.modeToggle.rawValue: L10nEntry(
            "Press to start or stop", "按一下开始或停止"),
        DictationKey.destinationPaste.rawValue: L10nEntry(
            "Paste in active app", "粘贴到当前应用"),
        DictationKey.destinationCopy.rawValue: L10nEntry(
            "Copy to clipboard", "复制到剪贴板"),
        DictationKey.destinationBoth.rawValue: L10nEntry("Paste and copy", "粘贴并复制"),
        DictationKey.idleNever.rawValue: L10nEntry("Never", "从不"),
        DictationKey.idleOneMinute.rawValue: L10nEntry("1 minute", "1 分钟"),
        DictationKey.idleOneHour.rawValue: L10nEntry("1 hour", "1 小时"),
        DictationKey.idleMinutes.rawValue: L10nEntry("%d minutes", "%d 分钟"),

        DictationKey.familyParakeetSummary.rawValue: L10nEntry(
            "Fast and memory-efficient", "快速且省内存"),
        DictationKey.familyQwenSummary.rawValue: L10nEntry(
            "More languages, but slower", "支持更多语言，但更慢"),
        DictationKey.coverageParakeet.rawValue: L10nEntry("25 languages", "25 种语言"),
        DictationKey.coverageQwen.rawValue: L10nEntry(
            "30 languages and 22 Chinese dialects", "30 种语言和 22 种中文方言"),
        DictationKey.summaryRedux.rawValue: L10nEntry(
            "Lightweight and efficient.", "轻量高效。"),
        DictationKey.summaryUltra.rawValue: L10nEntry(
            "Higher accuracy, larger download.", "准确率更高，下载更大。"),
        DictationKey.summaryQwenSmall.rawValue: L10nEntry("Smaller and faster.", "更小更快。"),
        DictationKey.summaryQwenLarge.rawValue: L10nEntry(
            "Higher accuracy, more memory.", "准确率更高，占用更多内存。"),

        DictationKey.micPermissionMessage.rawValue: L10nEntry(
            "Allow GearMac to use the microphone in System Settings",
            "请在系统设置中允许 GearMac 使用麦克风"),
        DictationKey.holdIssueModifier.rawValue: L10nEntry(
            "Record a single modifier or a key combination for hold to talk.",
            "为按住说话录制单个修饰键或一个组合键。"),
        DictationKey.holdIssueConflict.rawValue: L10nEntry(
            "This shortcut is also used by %@. Record another shortcut.",
            "此快捷键也被 %@ 使用。请录制其他快捷键。"),
        DictationKey.holdNeedsShortcut.rawValue: L10nEntry(
            "Hold to talk needs a key combination or a single modifier",
            "按住说话需要一个组合键或单个修饰键"),
        DictationKey.downloadModelFirst.rawValue: L10nEntry(
            "Download the dictation model in Settings first",
            "请先在设置中下载语音输入模型"),
        DictationKey.noSpeechRecorded.rawValue: L10nEntry("No speech was recorded", "未录制到语音"),
        DictationKey.pasteFailed.rawValue: L10nEntry(
            "Couldn't paste dictation into this app", "无法把语音输入粘贴到此应用"),
        DictationKey.accessibilityListening.rawValue: L10nEntry(
            "Dictation listening", "语音输入监听中"),
        DictationKey.accessibilityTranscribing.rawValue: L10nEntry(
            "Transcribing dictation", "正在转写语音输入"),
        DictationKey.failNoMicrophone.rawValue: L10nEntry(
            "No microphone is available.", "没有可用的麦克风。"),
        DictationKey.failMicrophoneDenied.rawValue: L10nEntry(
            "Allow GearMac to use the microphone in System Settings.",
            "请在系统设置中允许 GearMac 使用麦克风。"),
        DictationKey.failCaptureUnavailable.rawValue: L10nEntry(
            "Couldn't start recording from this microphone.", "无法从此麦克风开始录音。"),
    ]
}

/// 听写可选语言的展示名（rawValue 仍用于模型提示，因此单独提供本地化名）。
enum DictationLanguageKey: String, LocalizableKey {
    case arabic = "dictation.language.arabic"
    case cantonese = "dictation.language.cantonese"
    case chinese = "dictation.language.chinese"
    case czech = "dictation.language.czech"
    case danish = "dictation.language.danish"
    case dutch = "dictation.language.dutch"
    case english = "dictation.language.english"
    case filipino = "dictation.language.filipino"
    case finnish = "dictation.language.finnish"
    case french = "dictation.language.french"
    case german = "dictation.language.german"
    case greek = "dictation.language.greek"
    case hindi = "dictation.language.hindi"
    case hungarian = "dictation.language.hungarian"
    case indonesian = "dictation.language.indonesian"
    case italian = "dictation.language.italian"
    case japanese = "dictation.language.japanese"
    case korean = "dictation.language.korean"
    case macedonian = "dictation.language.macedonian"
    case malay = "dictation.language.malay"
    case persian = "dictation.language.persian"
    case polish = "dictation.language.polish"
    case portuguese = "dictation.language.portuguese"
    case romanian = "dictation.language.romanian"
    case russian = "dictation.language.russian"
    case spanish = "dictation.language.spanish"
    case swedish = "dictation.language.swedish"
    case thai = "dictation.language.thai"
    case turkish = "dictation.language.turkish"
    case vietnamese = "dictation.language.vietnamese"

    static let table: [String: L10nEntry] = [
        DictationLanguageKey.arabic.rawValue: L10nEntry("Arabic", "阿拉伯语"),
        DictationLanguageKey.cantonese.rawValue: L10nEntry("Cantonese", "粤语"),
        DictationLanguageKey.chinese.rawValue: L10nEntry("Chinese", "中文"),
        DictationLanguageKey.czech.rawValue: L10nEntry("Czech", "捷克语"),
        DictationLanguageKey.danish.rawValue: L10nEntry("Danish", "丹麦语"),
        DictationLanguageKey.dutch.rawValue: L10nEntry("Dutch", "荷兰语"),
        DictationLanguageKey.english.rawValue: L10nEntry("English", "英语"),
        DictationLanguageKey.filipino.rawValue: L10nEntry("Filipino", "菲律宾语"),
        DictationLanguageKey.finnish.rawValue: L10nEntry("Finnish", "芬兰语"),
        DictationLanguageKey.french.rawValue: L10nEntry("French", "法语"),
        DictationLanguageKey.german.rawValue: L10nEntry("German", "德语"),
        DictationLanguageKey.greek.rawValue: L10nEntry("Greek", "希腊语"),
        DictationLanguageKey.hindi.rawValue: L10nEntry("Hindi", "印地语"),
        DictationLanguageKey.hungarian.rawValue: L10nEntry("Hungarian", "匈牙利语"),
        DictationLanguageKey.indonesian.rawValue: L10nEntry("Indonesian", "印度尼西亚语"),
        DictationLanguageKey.italian.rawValue: L10nEntry("Italian", "意大利语"),
        DictationLanguageKey.japanese.rawValue: L10nEntry("Japanese", "日语"),
        DictationLanguageKey.korean.rawValue: L10nEntry("Korean", "韩语"),
        DictationLanguageKey.macedonian.rawValue: L10nEntry("Macedonian", "马其顿语"),
        DictationLanguageKey.malay.rawValue: L10nEntry("Malay", "马来语"),
        DictationLanguageKey.persian.rawValue: L10nEntry("Persian", "波斯语"),
        DictationLanguageKey.polish.rawValue: L10nEntry("Polish", "波兰语"),
        DictationLanguageKey.portuguese.rawValue: L10nEntry("Portuguese", "葡萄牙语"),
        DictationLanguageKey.romanian.rawValue: L10nEntry("Romanian", "罗马尼亚语"),
        DictationLanguageKey.russian.rawValue: L10nEntry("Russian", "俄语"),
        DictationLanguageKey.spanish.rawValue: L10nEntry("Spanish", "西班牙语"),
        DictationLanguageKey.swedish.rawValue: L10nEntry("Swedish", "瑞典语"),
        DictationLanguageKey.thai.rawValue: L10nEntry("Thai", "泰语"),
        DictationLanguageKey.turkish.rawValue: L10nEntry("Turkish", "土耳其语"),
        DictationLanguageKey.vietnamese.rawValue: L10nEntry("Vietnamese", "越南语"),
    ]
}
