// 文件职责：定义所有内置启动器命令的稳定 id、展示名、图标、快捷键动作与建议优先级。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 内置启动器动作，与用户自建动作一同展示。
enum CommandID: String, CaseIterable, Sendable {
    /// 命令面板的聊天沿用最初发布的 id，因此它的快捷键与兜底项仍能命中。
    case quickAI = "command:ai-chat"
    case aiChat = "command:ai-chat-window"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case decide = "command:decide"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case define = "command:define"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"

    /// 命令的展示名，直接出现在启动器行与设置面板中。
    var name: String {
        switch self {
        case .quickAI: return "Quick AI"
        case .aiChat: return "AI Chat"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.title
        case .rewrite: return BuiltInQuickAction.rewrite.title
        case .translate: return BuiltInQuickAction.translate.title
        case .summarize: return BuiltInQuickAction.summarize.title
        case .decide: return BuiltInQuickAction.decide.title
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .define: return "Define Word"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "GearMac Settings"
        case .about: return "About GearMac"
        case .support: return "Support GearMac"
        case .quit: return "Quit GearMac"
        }
    }

    /// 命令在启动器中使用的 SF Symbol 名称。
    var sfSymbol: String {
        switch self {
        case .quickAI: return "sparkles"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .translate: return BuiltInQuickAction.translate.symbol
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .decide: return BuiltInQuickAction.decide.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .define: return "book.closed"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        }
    }

    /// 穷举所有情况，因此新增第五个内置动作时若未在此添加分支，就无法进入启动器。
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .translate: self = .translate
        case .summarize: self = .summarize
        case .decide: self = .decide
        }
    }

    /// 反查该命令对应的内置快捷动作；非快捷动作返回 nil。
    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .translate: return .translate
        case .summarize: return .summarize
        case .decide: return .decide
        default: return nil
        }
    }

    /// 在这些查询下该命令优先，直到用户更多次打开竞争项为止。
    var boostedTerms: Set<String> {
        switch self {
        case .quickAI: ["ai"]
        case .aiChat: ["chat"]
        default: []
        }
    }

    /// 建议排序，数值越高越靠前，直到用户自身的使用习惯填满该区块。
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .mySchedule: 60
        case .searchEmoji: 50
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// 查询驱动：输入文本即它们的输入，因此只在被提供处即时构建，从不列入目录。
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// 快捷键不携带查询参数，也不该有任何命令能直接终止应用。
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
