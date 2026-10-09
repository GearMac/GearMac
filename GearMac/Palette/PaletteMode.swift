// 文件职责：定义调色板的所有屏幕模式（launcher/clipboard/ai/…）及其图标与占位文案，并提供粘贴目标 `PasteTarget`。
// 分层：Model；纯枚举与值类型，仅用 AppKit 类型解析粘贴目标，不含 UI。
import AppKit

/// 调色板的各个屏幕模式，作为模式路由与导航栈的标识。
enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case rooms
    /// 选择一个房间的窗口与应用；房间名是在 Rooms 屏幕上指定的。
    case roomWindows
    case schedule
    /// 单个会议的只读页面，由该会议自己的动作推入。
    case meetingDetails
    case uninstall
    case quicklinks
    case snippets
    case dictionary
    /// 一个渲染到调色板中的 Raycast 扩展命令。
    case extensionCommand

    var id: String { rawValue }

    /// 该模式在 UI 中使用的 SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .rooms: return "door.left.hand.open"
        case .roomWindows: return "macwindow.badge.plus"
        case .schedule: return "calendar"
        case .meetingDetails: return "calendar"
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        case .snippets: return "curlybraces"
        case .dictionary: return "book.closed"
        case .extensionCommand: return "puzzlepiece.extension"
        }
    }
    /// 该模式搜索框的占位文案（按当前界面语言解析）。
    func placeholder(_ language: AppLanguage) -> String {
        L10n.string(placeholderKey, language: language)
    }

    /// 该模式占位文案对应的本地化键。
    private var placeholderKey: PaletteKey {
        switch self {
        case .launcher: return .placeholderLauncher
        case .clipboard: return .placeholderClipboard
        case .ai: return .placeholderAI
        case .aiHistory: return .placeholderAIHistory
        case .calculatorHistory: return .placeholderCalculatorHistory
        case .emoji: return .placeholderEmoji
        case .fileSearch: return .placeholderFileSearch
        case .menuSearch: return .placeholderMenuSearch
        case .switchWindows: return .placeholderSwitchWindows
        case .rooms: return .placeholderRooms
        case .roomWindows: return .placeholderRoomWindows
        case .schedule: return .placeholderSchedule
        case .meetingDetails: return .placeholderMeetingDetails
        case .uninstall: return .placeholderUninstall
        case .quicklinks: return .placeholderQuicklinks
        case .snippets: return .placeholderSnippets
        case .dictionary: return .placeholderDictionary
        // 只要命令声明了自己的 `searchBarPlaceholder`，就会被它替换。
        case .extensionCommand: return .placeholderExtensionCommand
        }
    }
}

/// 粘贴要落入的目标应用，每次显示时解析一次，避免逐次渲染重读。
struct PasteTarget: Equatable {
    let name: String
    /// 供 `IconCache` 使用的 bundle 路径——没有磁盘 bundle 的目标为 nil。
    let iconPath: String?

    /// 由目标应用构造；无应用或无本地化名称时返回 nil。
    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    /// 粘贴操作的标题文案，形如「Paste to <应用名>」。
    var pasteTitle: String { "Paste to \(name)" }
}
