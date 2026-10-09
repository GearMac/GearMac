// 文件职责：AI 功能的本地化键与中英词表（设置面板、提供方、模型选择、聊天界面与状态文案）。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// AI 设置面板、提供方面板与聊天界面共用的文案键。
enum AIKey: String, LocalizableKey {
    // 设置面板：总开关与提供方
    case enableTitle = "ai.enable.title"
    case enableSubtitle = "ai.enable.subtitle"
    case providersTitle = "ai.providers.title"
    case providersManage = "ai.providers.manage"
    case apiConnectionOne = "ai.providers.apiConnectionOne"
    case apiConnectionMany = "ai.providers.apiConnectionMany"
    case noExternalProviders = "ai.providers.noneReady"

    // 设置面板：默认模型
    case defaultModel = "ai.default.model"
    case reasoningEffort = "ai.default.effort"
    case defaultFooterOnDevice = "ai.default.footerOnDevice"
    case defaultFooterNone = "ai.default.footerNone"
    case defaultFooterSelected = "ai.default.footerSelected"

    // 设置面板：聊天
    case webSearch = "ai.chat.webSearch"
    case webSearchSubtitle = "ai.chat.webSearchSubtitle"
    case toolRounds = "ai.chat.toolRounds"
    case toolRoundsSubtitle = "ai.chat.toolRoundsSubtitle"

    // 设置面板：会话
    case opensTo = "ai.conversations.opensTo"
    case newChatAfter = "ai.conversations.newChatAfter"
    case retention = "ai.conversations.retention"
    case retentionSubtitle = "ai.conversations.retentionSubtitle"
    case conversationsFooter = "ai.conversations.footer"

    // 设置面板：系统提示
    case systemPromptEnable = "ai.systemPrompt.enable"
    case systemPromptEnableSubtitle = "ai.systemPrompt.enableSubtitle"
    case systemPromptFooter = "ai.systemPrompt.footer"

    // 模型选择行
    case noProviderConfigured = "ai.model.noProviderConfigured"

    // 系统提示编辑器
    case promptNothingAdded = "ai.prompt.nothingAdded"
    case promptAddedToEveryMessage = "ai.prompt.addedToEveryMessage"
    case promptShow = "ai.prompt.show"
    case promptHide = "ai.prompt.hide"
    case promptShowAccessibility = "ai.prompt.showAccessibility"
    case promptHideAccessibility = "ai.prompt.hideAccessibility"

    // 模型枚举
    case providerOpenAI = "ai.provider.openAI"
    case providerAnthropic = "ai.provider.anthropic"
    case providerGemini = "ai.provider.gemini"
    case providerOpenRouter = "ai.provider.openRouter"
    case providerOpenAICompatible = "ai.provider.openAICompatible"
    case retentionWeek = "ai.retention.week"
    case retentionMonth = "ai.retention.month"
    case retentionThreeMonths = "ai.retention.threeMonths"
    case retentionForever = "ai.retention.forever"
    case opensToRecent = "ai.opensTo.recent"
    case opensToNew = "ai.opensTo.new"
    case newAfterNever = "ai.newAfter.never"
    case newAfterMinutes = "ai.newAfter.minutes"
    case toolRoundsUnlimited = "ai.toolRounds.unlimited"
    case planFree = "ai.plan.free"
    case planGo = "ai.plan.go"
    case planPlus = "ai.plan.plus"
    case planPro20 = "ai.plan.pro20"
    case planPro5 = "ai.plan.pro5"
    case planTeam = "ai.plan.team"
    case planBusiness = "ai.plan.business"
    case planEnterprise = "ai.plan.enterprise"
    case planEdu = "ai.plan.edu"
    case planAPIKey = "ai.plan.apiKey"
    case planAccount = "ai.plan.account"
    case onDevice = "ai.model.onDevice"
    case newChat = "ai.chat.newChat"

    // 聊天窗口与侧边栏
    case windowTitle = "ai.window.title"
    case sidebarSearch = "ai.sidebar.search"
    case sidebarSearchPlaceholder = "ai.sidebar.searchPlaceholder"
    case sidebarClearSearch = "ai.sidebar.clearSearch"
    case sidebarPinned = "ai.sidebar.pinned"
    case sidebarHistoryUnavailable = "ai.sidebar.historyUnavailable"
    case sidebarHistoryUnavailableDetail = "ai.sidebar.historyUnavailableDetail"
    case sidebarNoChats = "ai.sidebar.noChats"
    case sidebarNoChatsDetail = "ai.sidebar.noChatsDetail"
    case sidebarChatName = "ai.sidebar.chatName"
    case sidebarPin = "ai.sidebar.pin"
    case sidebarUnpin = "ai.sidebar.unpin"
    case sidebarCopy = "ai.sidebar.copy"
    case sidebarExport = "ai.sidebar.export"
    case sidebarDelete = "ai.sidebar.delete"
    case sidebarRename = "ai.sidebar.rename"
    case sidebarDeleteAll = "ai.sidebar.deleteAll"
    case sidebarAnswering = "ai.sidebar.answering"

    case chatCopied = "ai.coordinator.chatCopied"
    case chatOpenFailed = "ai.coordinator.openFailed"
    case chatExportFailed = "ai.coordinator.exportFailed"
    case thisChat = "ai.coordinator.thisChat"
    case deleteChatTitle = "ai.coordinator.deleteTitle"
    case deleteChatMessage = "ai.coordinator.deleteMessage"
    case deleteAllTitle = "ai.coordinator.deleteAllTitle"
    case deleteAllMessage = "ai.coordinator.deleteAllMessage"
    case deleteAll = "ai.coordinator.deleteAll"
    case deleteConfirm = "ai.coordinator.delete"
    case attachPrompt = "ai.coordinator.attach"
    case attachHint = "ai.coordinator.attachHint"
    case fileStillLoading = "ai.coordinator.fileStillLoading"
    case chooseModelHint = "ai.coordinator.chooseModelHint"
    case chooseModel = "ai.coordinator.chooseModel"
    case contextSummary = "ai.coordinator.contextSummary"

    case chromeSidebarToggle = "ai.chrome.sidebarToggle"
    case chromeFindInChat = "ai.chrome.findInChat"
    case chromeActions = "ai.chrome.actions"
    case chromeStop = "ai.chrome.stop"
    case chromeRegenerate = "ai.chrome.regenerate"
    case chromeCopyLast = "ai.chrome.copyLast"
    case chromeCopyChat = "ai.chrome.copyChat"
    case chromeRemoveAttachments = "ai.chrome.removeAttachments"
    case chromePin = "ai.chrome.pin"
    case chromeUnpin = "ai.chrome.unpin"
    case chromeDeleteChat = "ai.chrome.deleteChat"
    case chromeAISettings = "ai.chrome.aiSettings"

    case historyOpenChat = "ai.history.openChat"
    case historyContinue = "ai.history.continueInChat"
    case historyEmpty = "ai.history.empty"
    case historyNoMatches = "ai.history.noMatches"
    case historyUnavailable = "ai.history.unavailable"
    case historyDeleteChat = "ai.history.deleteChat"
    case historyDeleteAll = "ai.history.deleteAll"

    // Decisions 判定：校验文案
    case decisionsValidationEmpty = "ai.decisions.validation.empty"
    case decisionsValidationTooMany = "ai.decisions.validation.tooMany"
    case decisionsValidationNameMissing = "ai.decisions.validation.nameMissing"
    case decisionsValidationNameDuplicate = "ai.decisions.validation.nameDuplicate"
    case decisionsValidationInstructionsMissing = "ai.decisions.validation.instructionsMissing"
    case decisionsValidationChoiceCount = "ai.decisions.validation.choiceCount"
    case decisionsValidationChoiceValueEmpty = "ai.decisions.validation.choiceValueEmpty"
    case decisionsValidationLevelCount = "ai.decisions.validation.levelCount"
    case decisionsValidationLevelLabelEmpty = "ai.decisions.validation.levelLabelEmpty"

    // Decisions 判定：结果序列化
    case decisionsVerdictYes = "ai.decisions.verdict.yes"
    case decisionsVerdictNo = "ai.decisions.verdict.no"
    case decisionsCopyPredicate = "ai.decisions.copy.predicate"
    case decisionsCopyChoice = "ai.decisions.copy.choice"
    case decisionsCopyScore = "ai.decisions.copy.score"
    case decisionsCopyRefused = "ai.decisions.copy.refused"
    case decisionsCopyTokens = "ai.decisions.copy.tokens"

    // Decisions 判定：客户端错误
    case decisionsErrorUnauthorized = "ai.decisions.error.unauthorized"
    case decisionsErrorModelUnavailable = "ai.decisions.error.modelUnavailable"
    case decisionsErrorInvalidRequest = "ai.decisions.error.invalidRequest"
    case decisionsErrorRateLimited = "ai.decisions.error.rateLimited"
    case decisionsErrorServer = "ai.decisions.error.server"
    case decisionsErrorNetwork = "ai.decisions.error.network"
    case decisionsErrorEmptyResponse = "ai.decisions.error.emptyResponse"
    case decisionsErrorDecoding = "ai.decisions.error.decoding"
    case decisionsErrorMissingKey = "ai.decisions.error.missingKey"
    case decisionsErrorNoRoute = "ai.decisions.error.noRoute"
    case decisionsErrorKeychain = "ai.decisions.error.keychain"
    case decisionsErrorBadEndpoint = "ai.decisions.error.badEndpoint"

    // Decisions 判定：设置面板
    case decisionsNoQuestions = "ai.decisions.noQuestions"
    case decisionsAddQuestion = "ai.decisions.addQuestion"
    case decisionsRestoreDefaults = "ai.decisions.restoreDefaults"
    case decisionsFooter = "ai.decisions.footer"

    // Decisions 判定：问题编辑器
    case decisionsQuestionsTitle = "ai.decisions.editor.title"
    case decisionsQuestionsSubtitle = "ai.decisions.editor.subtitle"
    case decisionsEditTitle = "ai.decisions.editor.editTitle"
    case decisionsKindTitle = "ai.decisions.editor.kind"
    case decisionsKindPredicate = "ai.decisions.editor.kindPredicate"
    case decisionsKindChoice = "ai.decisions.editor.kindChoice"
    case decisionsKindScore = "ai.decisions.editor.kindScore"
    case decisionsNameTitle = "ai.decisions.editor.name"
    case decisionsNamePrompt = "ai.decisions.editor.namePrompt"
    case decisionsInstructionsTitle = "ai.decisions.editor.instructions"
    case decisionsInstructionsPrompt = "ai.decisions.editor.instructionsPrompt"
    case decisionsChoicesTitle = "ai.decisions.editor.choices"
    case decisionsChoiceValuePrompt = "ai.decisions.editor.choiceValuePrompt"
    case decisionsChoiceDescriptionPrompt = "ai.decisions.editor.choiceDescriptionPrompt"
    case decisionsAddChoice = "ai.decisions.editor.addChoice"
    case decisionsLevelsTitle = "ai.decisions.editor.levels"
    case decisionsLevelLabelPrompt = "ai.decisions.editor.levelLabelPrompt"
    case decisionsLevelDescriptionPrompt = "ai.decisions.editor.levelDescriptionPrompt"
    case decisionsAddLevel = "ai.decisions.editor.addLevel"
    case decisionsNameTaken = "ai.decisions.editor.nameTaken"
    case decisionsDelete = "ai.decisions.editor.delete"
    case decisionsCancel = "ai.decisions.editor.cancel"
    case decisionsSave = "ai.decisions.editor.save"
    case decisionsKindFooter = "ai.decisions.editor.kindFooter"

    // Decisions 判定：结果面板
    case decisionsRefusedChip = "ai.decisions.panel.refused"
    case decisionsConfidence = "ai.decisions.panel.confidence"

    static let table: [String: L10nEntry] = [
        AIKey.enableTitle.rawValue: L10nEntry("Enable AI", "启用 AI"),
        AIKey.enableSubtitle.rawValue: L10nEntry(
            "Nothing is loaded or sent while it is off.", "关闭时不会加载或发送任何内容。"),
        AIKey.providersTitle.rawValue: L10nEntry("Providers", "提供方"),
        AIKey.providersManage.rawValue: L10nEntry("Manage…", "管理…"),
        AIKey.apiConnectionOne.rawValue: L10nEntry("1 API connection", "1 个 API 连接"),
        AIKey.apiConnectionMany.rawValue: L10nEntry("%d API connections", "%d 个 API 连接"),
        AIKey.noExternalProviders.rawValue: L10nEntry(
            "No external providers ready", "尚无就绪的外部提供方"),

        AIKey.defaultModel.rawValue: L10nEntry("Default model", "默认模型"),
        AIKey.reasoningEffort.rawValue: L10nEntry("Reasoning effort", "推理强度"),
        AIKey.defaultFooterOnDevice.rawValue: L10nEntry(
            "Apple Intelligence runs on this Mac. Nothing leaves it.",
            "Apple Intelligence 在本机运行，不会离开这台 Mac。"),
        AIKey.defaultFooterNone.rawValue: L10nEntry(
            "Turn on Apple Intelligence, or add a provider above.",
            "开启 Apple Intelligence，或在上方添加提供方。"),
        AIKey.defaultFooterSelected.rawValue: L10nEntry(
            "Only the selected provider is contacted.", "只会联系所选的提供方。"),

        AIKey.webSearch.rawValue: L10nEntry("Web search", "联网搜索"),
        AIKey.webSearchSubtitle.rawValue: L10nEntry(
            "Codex and OpenRouter only. Prompts go to a search engine.",
            "仅限 Codex 和 OpenRouter。提示词会发送到搜索引擎。"),
        AIKey.toolRounds.rawValue: L10nEntry("Tool call rounds", "工具调用轮数"),
        AIKey.toolRoundsSubtitle.rawValue: L10nEntry(
            "A reply stops after this many; Unlimited runs until Stop. API connections, Codex and Claude.",
            "回复会在此轮数后停止；「不限」会一直运行到点击停止。适用于 API 连接、Codex 和 Claude。"),

        AIKey.opensTo.rawValue: L10nEntry("Quick AI opens to", "快速 AI 打开到"),
        AIKey.newChatAfter.rawValue: L10nEntry(
            "Start a new conversation after", "在此时间后开始新对话"),
        AIKey.retention.rawValue: L10nEntry("Keep conversations", "保留对话"),
        AIKey.retentionSubtitle.rawValue: L10nEntry(
            "Older ones are deleted, except pinned chats.", "较旧的会被删除，固定对话除外。"),
        AIKey.conversationsFooter.rawValue: L10nEntry(
            "Conversations stay on this Mac, outside settings backups.",
            "对话保存在这台 Mac 上，不包含在设置备份中。"),

        AIKey.systemPromptEnable.rawValue: L10nEntry("Send a system prompt", "发送系统提示词"),
        AIKey.systemPromptEnableSubtitle.rawValue: L10nEntry(
            "Off also skips GearMac's own prompt.", "关闭后也会跳过 GearMac 自带的提示词。"),
        AIKey.systemPromptFooter.rawValue: L10nEntry(
            "Sent before every message, after GearMac's own. Both are billed each turn.",
            "在每条消息前发送，位于 GearMac 自带提示词之后。两者每轮都会计费。"),

        AIKey.noProviderConfigured.rawValue: L10nEntry(
            "No AI provider configured", "尚未配置 AI 提供方"),

        AIKey.promptNothingAdded.rawValue: L10nEntry("Nothing added", "未添加任何内容"),
        AIKey.promptAddedToEveryMessage.rawValue: L10nEntry(
            "Added to every message", "会添加到每条消息"),
        AIKey.promptShow.rawValue: L10nEntry("Show the prompt", "显示提示词"),
        AIKey.promptHide.rawValue: L10nEntry("Hide the prompt", "隐藏提示词"),
        AIKey.promptShowAccessibility.rawValue: L10nEntry(
            "Show the system prompt", "显示系统提示词"),
        AIKey.promptHideAccessibility.rawValue: L10nEntry(
            "Hide the system prompt", "隐藏系统提示词"),

        AIKey.providerOpenAI.rawValue: L10nEntry("OpenAI API", "OpenAI API"),
        AIKey.providerAnthropic.rawValue: L10nEntry("Anthropic Claude", "Anthropic Claude"),
        AIKey.providerGemini.rawValue: L10nEntry("Google Gemini", "Google Gemini"),
        AIKey.providerOpenRouter.rawValue: L10nEntry("OpenRouter", "OpenRouter"),
        AIKey.providerOpenAICompatible.rawValue: L10nEntry(
            "OpenAI Compatible", "OpenAI 兼容"),
        AIKey.retentionWeek.rawValue: L10nEntry("7 Days", "7 天"),
        AIKey.retentionMonth.rawValue: L10nEntry("30 Days", "30 天"),
        AIKey.retentionThreeMonths.rawValue: L10nEntry("3 Months", "3 个月"),
        AIKey.retentionForever.rawValue: L10nEntry("Forever", "永久"),
        AIKey.opensToRecent.rawValue: L10nEntry("Recent Conversation", "最近的对话"),
        AIKey.opensToNew.rawValue: L10nEntry("A New Conversation", "新建对话"),
        AIKey.newAfterNever.rawValue: L10nEntry("Never", "从不"),
        AIKey.newAfterMinutes.rawValue: L10nEntry("%d Minutes", "%d 分钟"),
        AIKey.toolRoundsUnlimited.rawValue: L10nEntry("Unlimited", "不限"),
        AIKey.planFree.rawValue: L10nEntry("Free", "免费"),
        AIKey.planGo.rawValue: L10nEntry("Go", "Go"),
        AIKey.planPlus.rawValue: L10nEntry("Plus", "Plus"),
        AIKey.planPro20.rawValue: L10nEntry("Pro 20x", "Pro 20x"),
        AIKey.planPro5.rawValue: L10nEntry("Pro 5x", "Pro 5x"),
        AIKey.planTeam.rawValue: L10nEntry("Team", "团队"),
        AIKey.planBusiness.rawValue: L10nEntry("Business", "商业版"),
        AIKey.planEnterprise.rawValue: L10nEntry("Enterprise", "企业版"),
        AIKey.planEdu.rawValue: L10nEntry("Edu", "教育版"),
        AIKey.planAPIKey.rawValue: L10nEntry("API key", "API 密钥"),
        AIKey.planAccount.rawValue: L10nEntry("Account", "账户"),
        AIKey.onDevice.rawValue: L10nEntry("On device", "本机"),
        AIKey.newChat.rawValue: L10nEntry("New Chat", "新对话"),

        AIKey.windowTitle.rawValue: L10nEntry("AI Chat", "AI 对话"),
        AIKey.sidebarSearch.rawValue: L10nEntry("Search chats", "搜索对话"),
        AIKey.sidebarSearchPlaceholder.rawValue: L10nEntry("Search", "搜索"),
        AIKey.sidebarClearSearch.rawValue: L10nEntry("Clear search", "清除搜索"),
        AIKey.sidebarPinned.rawValue: L10nEntry("Pinned", "已固定"),
        AIKey.sidebarHistoryUnavailable.rawValue: L10nEntry(
            "History Unavailable", "历史记录不可用"),
        AIKey.sidebarHistoryUnavailableDetail.rawValue: L10nEntry(
            "Chats can't be saved on this Mac right now.", "目前无法在这台 Mac 上保存对话。"),
        AIKey.sidebarNoChats.rawValue: L10nEntry("No Chats Yet", "暂无对话"),
        AIKey.sidebarNoChatsDetail.rawValue: L10nEntry(
            "Conversations stay on this Mac.", "对话保存在这台 Mac 上。"),
        AIKey.sidebarChatName.rawValue: L10nEntry("Chat name", "对话名称"),
        AIKey.sidebarPin.rawValue: L10nEntry("Pin Chat", "固定对话"),
        AIKey.sidebarUnpin.rawValue: L10nEntry("Unpin Chat", "取消固定"),
        AIKey.sidebarCopy.rawValue: L10nEntry("Copy Chat", "复制对话"),
        AIKey.sidebarExport.rawValue: L10nEntry("Export as Markdown…", "导出为 Markdown…"),
        AIKey.sidebarDelete.rawValue: L10nEntry("Delete Chat…", "删除对话…"),
        AIKey.sidebarRename.rawValue: L10nEntry("Rename…", "重命名…"),
        AIKey.sidebarDeleteAll.rawValue: L10nEntry("Delete All Chats…", "删除所有对话…"),
        AIKey.sidebarAnswering.rawValue: L10nEntry("Answering", "正在回答"),

        AIKey.chatCopied.rawValue: L10nEntry("Chat copied", "对话已复制"),
        AIKey.chatOpenFailed.rawValue: L10nEntry(
            "That chat could not be opened.", "无法打开该对话。"),
        AIKey.chatExportFailed.rawValue: L10nEntry(
            "The chat could not be exported.", "无法导出该对话。"),
        AIKey.thisChat.rawValue: L10nEntry("This chat", "此对话"),
        AIKey.deleteChatTitle.rawValue: L10nEntry("Delete chat?", "删除对话？"),
        AIKey.deleteChatMessage.rawValue: L10nEntry(
            "“%@” will be removed. This can't be undone.", "“%@”将被移除。此操作无法撤销。"),
        AIKey.deleteAllTitle.rawValue: L10nEntry("Delete all chats?", "删除所有对话？"),
        AIKey.deleteAllMessage.rawValue: L10nEntry(
            "Every saved conversation except pinned ones will be removed. This can't be undone.",
            "除固定对话外，所有已保存的对话都会被移除。此操作无法撤销。"),
        AIKey.deleteAll.rawValue: L10nEntry("Delete All", "全部删除"),
        AIKey.deleteConfirm.rawValue: L10nEntry("Delete", "删除"),
        AIKey.attachPrompt.rawValue: L10nEntry("Attach", "附加"),
        AIKey.attachHint.rawValue: L10nEntry(
            "Choose images, PDFs or text files to send with your next message.",
            "选择要随下一条消息发送的图片、PDF 或文本文件。"),
        AIKey.fileStillLoading.rawValue: L10nEntry(
            "That file was still loading and did not make it into the chat.",
            "该文件仍在加载，未能加入对话。"),
        AIKey.chooseModelHint.rawValue: L10nEntry(
            "Choose a default AI model in Settings.", "请在设置中选择默认 AI 模型。"),
        AIKey.chooseModel.rawValue: L10nEntry("Choose Model", "选择模型"),
        AIKey.contextSummary.rawValue: L10nEntry(
            "Context %@, %d of %d messages sent", "上下文 %@，已发送 %d/%d 条消息"),

        AIKey.chromeSidebarToggle.rawValue: L10nEntry(
            "Show or Hide Sidebar", "显示或隐藏边栏"),
        AIKey.chromeFindInChat.rawValue: L10nEntry("Find in Chat", "在对话中查找"),
        AIKey.chromeActions.rawValue: L10nEntry("Actions", "操作"),
        AIKey.chromeStop.rawValue: L10nEntry("Stop Response", "停止回复"),
        AIKey.chromeRegenerate.rawValue: L10nEntry("Regenerate Response", "重新生成回复"),
        AIKey.chromeCopyLast.rawValue: L10nEntry("Copy Last Response", "复制上一条回复"),
        AIKey.chromeCopyChat.rawValue: L10nEntry("Copy Chat", "复制对话"),
        AIKey.chromeRemoveAttachments.rawValue: L10nEntry(
            "Remove Attachments", "移除附件"),
        AIKey.chromePin.rawValue: L10nEntry("Pin Chat", "固定对话"),
        AIKey.chromeUnpin.rawValue: L10nEntry("Unpin Chat", "取消固定"),
        AIKey.chromeDeleteChat.rawValue: L10nEntry("Delete Chat…", "删除对话…"),
        AIKey.chromeAISettings.rawValue: L10nEntry("AI Settings", "AI 设置"),

        AIKey.historyOpenChat.rawValue: L10nEntry("Open Chat", "打开对话"),
        AIKey.historyContinue.rawValue: L10nEntry(
            "Continue in AI Chat", "在 AI 对话中继续"),
        AIKey.historyEmpty.rawValue: L10nEntry("No chats yet", "暂无对话"),
        AIKey.historyNoMatches.rawValue: L10nEntry("No matching chats", "没有匹配的对话"),
        AIKey.historyUnavailable.rawValue: L10nEntry(
            "Chat history is unavailable", "对话历史不可用"),
        AIKey.historyDeleteChat.rawValue: L10nEntry("Delete Chat", "删除对话"),
        AIKey.historyDeleteAll.rawValue: L10nEntry("Delete All Chats", "删除所有对话"),

        AIKey.decisionsValidationEmpty.rawValue: L10nEntry(
            "Add at least one question.", "至少添加一个问题。"),
        AIKey.decisionsValidationTooMany.rawValue: L10nEntry(
            "At most %d questions are allowed.", "最多允许 %d 个问题。"),
        AIKey.decisionsValidationNameMissing.rawValue: L10nEntry(
            "Every question needs a name.", "每个问题都需要名称。"),
        AIKey.decisionsValidationNameDuplicate.rawValue: L10nEntry(
            "Question names must be unique: “%@”.", "问题名称必须唯一：“%@”。"),
        AIKey.decisionsValidationInstructionsMissing.rawValue: L10nEntry(
            "Every question needs instructions.", "每个问题都需要判定说明。"),
        AIKey.decisionsValidationChoiceCount.rawValue: L10nEntry(
            "A choice question needs 2–255 choices; it has %d.",
            "选择题需要 2–255 个选项；当前 %d 个。"),
        AIKey.decisionsValidationChoiceValueEmpty.rawValue: L10nEntry(
            "Every choice needs a value.", "每个选项都需要取值。"),
        AIKey.decisionsValidationLevelCount.rawValue: L10nEntry(
            "A score question needs 2–10 levels; it has %d.", "评分题需要 2–10 个档位；当前 %d 个。"),
        AIKey.decisionsValidationLevelLabelEmpty.rawValue: L10nEntry(
            "Every level needs a label.", "每个档位都需要名称。"),

        AIKey.decisionsVerdictYes.rawValue: L10nEntry("Yes", "是"),
        AIKey.decisionsVerdictNo.rawValue: L10nEntry("No", "否"),
        AIKey.decisionsCopyPredicate.rawValue: L10nEntry(
            "%1$@: %2$@ (%3$d%%)", "%1$@：%2$@（%3$d%%）"),
        AIKey.decisionsCopyChoice.rawValue: L10nEntry(
            "%1$@: %2$@ (confidence %3$d%%)", "%1$@：%2$@（置信度 %3$d%%）"),
        AIKey.decisionsCopyScore.rawValue: L10nEntry(
            "%1$@: %2$@ (score %3$@)", "%1$@：%2$@（评分 %3$@）"),
        AIKey.decisionsCopyRefused.rawValue: L10nEntry(
            "%1$@: refused", "%1$@：拒答"),
        AIKey.decisionsCopyTokens.rawValue: L10nEntry(
            "Tokens: %1$d in · %2$d out", "Token：输入 %1$d · 输出 %2$d"),

        AIKey.decisionsErrorUnauthorized.rawValue: L10nEntry(
            "The gateway rejected the API key — check it in Settings.",
            "网关拒绝了 API 密钥——请在设置中检查。"),
        AIKey.decisionsErrorModelUnavailable.rawValue: L10nEntry(
            "The gateway does not offer this model.", "网关未开放该模型。"),
        AIKey.decisionsErrorInvalidRequest.rawValue: L10nEntry(
            "The gateway rejected the request: %@", "网关拒绝了该请求：%@"),
        AIKey.decisionsErrorRateLimited.rawValue: L10nEntry(
            "The gateway is rate-limiting requests; try again shortly.",
            "网关正在限流，请稍后再试。"),
        AIKey.decisionsErrorServer.rawValue: L10nEntry(
            "The gateway had a problem; try again shortly.", "网关暂时不可用，请稍后再试。"),
        AIKey.decisionsErrorNetwork.rawValue: L10nEntry(
            "Could not reach the gateway — check the network or VPN.",
            "无法连接网关——请检查网络或 VPN。"),
        AIKey.decisionsErrorEmptyResponse.rawValue: L10nEntry(
            "The gateway returned no answers.", "网关没有返回任何答案。"),
        AIKey.decisionsErrorDecoding.rawValue: L10nEntry(
            "The gateway returned an unreadable answer.", "网关返回了无法解析的答案。"),
        AIKey.decisionsErrorMissingKey.rawValue: L10nEntry(
            "Add the Decisions API key in Settings → AI.", "请在设置 → AI 中填写 Decisions API 密钥。"),
        AIKey.decisionsErrorNoRoute.rawValue: L10nEntry(
            "Add an API connection with a Decisions model (openai/gpt-6-luna-decisions) in Settings → AI.",
            "请在设置 → AI 的 API 连接中添加 Decisions 模型（openai/gpt-6-luna-decisions）。"),
        AIKey.decisionsErrorKeychain.rawValue: L10nEntry(
            "The API key could not be read from Keychain.", "无法从钥匙串读取 API 密钥。"),
        AIKey.decisionsErrorBadEndpoint.rawValue: L10nEntry(
            "The Decisions endpoint is invalid: %@", "Decisions 端点无效：%@"),

        AIKey.decisionsNoQuestions.rawValue: L10nEntry(
            "No questions yet", "还没有问题"),
        AIKey.decisionsAddQuestion.rawValue: L10nEntry("Add Question", "添加问题"),
        AIKey.decisionsRestoreDefaults.rawValue: L10nEntry(
            "Restore Defaults", "恢复默认"),
        AIKey.decisionsFooter.rawValue: L10nEntry(
            "The Decide action, and any chat on a Decisions model "
                + "(openai/gpt-6-luna-decisions), asks these questions about the text at hand. "
                + "Add the gateway as an API connection under Providers, then pick that model in "
                + "the chat's model menu.",
            "「判定」动作与任何使用 Decisions 模型（openai/gpt-6-luna-decisions）的聊天，都会对面前的文本提问这些问题。"
                + "请先在 Providers 中把网关添加为 API 连接，再在聊天的模型菜单中选择该模型。"),

        AIKey.decisionsQuestionsTitle.rawValue: L10nEntry("Decision Questions", "判定问题"),
        AIKey.decisionsQuestionsSubtitle.rawValue: L10nEntry(
            "Asked together about the selected text; each answers independently.",
            "随选中文本一起提问，各问题独立作答。"),
        AIKey.decisionsEditTitle.rawValue: L10nEntry("Edit Question", "编辑问题"),
        AIKey.decisionsKindTitle.rawValue: L10nEntry("Type", "类型"),
        AIKey.decisionsKindPredicate.rawValue: L10nEntry(
            "Predicate (yes/no)", "命题（是/否）"),
        AIKey.decisionsKindChoice.rawValue: L10nEntry("Choice", "选择题"),
        AIKey.decisionsKindScore.rawValue: L10nEntry("Score", "评分"),
        AIKey.decisionsNameTitle.rawValue: L10nEntry("Name", "名称"),
        AIKey.decisionsNamePrompt.rawValue: L10nEntry(
            "unique, e.g. is_negative", "唯一，如 is_negative"),
        AIKey.decisionsInstructionsTitle.rawValue: L10nEntry("Instructions", "判定说明"),
        AIKey.decisionsInstructionsPrompt.rawValue: L10nEntry(
            "e.g. 这段文本是否表达负面评价？", "如：这段文本是否表达负面评价？"),
        AIKey.decisionsChoicesTitle.rawValue: L10nEntry("Choices", "选项"),
        AIKey.decisionsChoiceValuePrompt.rawValue: L10nEntry(
            "value, e.g. quality", "取值，如 quality"),
        AIKey.decisionsChoiceDescriptionPrompt.rawValue: L10nEntry(
            "what belongs here (optional)", "该选项的边界（可选）"),
        AIKey.decisionsAddChoice.rawValue: L10nEntry("Add Choice", "添加选项"),
        AIKey.decisionsLevelsTitle.rawValue: L10nEntry("Levels", "档位"),
        AIKey.decisionsLevelLabelPrompt.rawValue: L10nEntry(
            "label, e.g. 中等", "名称，如：中等"),
        AIKey.decisionsLevelDescriptionPrompt.rawValue: L10nEntry(
            "what belongs here (optional)", "该档位的边界（可选）"),
        AIKey.decisionsAddLevel.rawValue: L10nEntry("Add Level", "添加档位"),
        AIKey.decisionsNameTaken.rawValue: L10nEntry(
            "That name is already used.", "该名称已被使用。"),
        AIKey.decisionsDelete.rawValue: L10nEntry("Delete", "删除"),
        AIKey.decisionsCancel.rawValue: L10nEntry("Cancel", "取消"),
        AIKey.decisionsSave.rawValue: L10nEntry("Save", "保存"),
        AIKey.decisionsKindFooter.rawValue: L10nEntry(
            "Predicate answers a probability; Choice picks one of 2–255 options; Score lands on one of 2–10 ordered levels.",
            "命题返回成立概率；选择题在 2–255 个选项中择一；评分落在 2–10 个有序档位上。"),

        AIKey.decisionsRefusedChip.rawValue: L10nEntry(
            "Refused to answer", "拒答"),
        AIKey.decisionsConfidence.rawValue: L10nEntry(
            "Confidence %d%%", "置信度 %d%%"),
    ]
}
