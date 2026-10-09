// 文件职责：内置命令目录，把 `CommandID` 构造成启动器可展示的 `AppEntry` 行，并维护命令与设置面板的双向归属。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 内置命令目录：为所有命令提供 `AppEntry` 行，并负责命令与设置面板之间的归属查询。
enum CommandCatalog {
    /// 按名称排序以满足 `AppIndex` 的不变量；此处的 URL 只是占位符。
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .filter { !$0.isQueryDriven }
        .map { makeEntry($0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// 构造某个设置面板所拥有的全部命令行。
    nonisolated static func entries(ownedBy owner: SettingsTab) -> [AppEntry] {
        owner.ownedCommands.map { makeEntry($0) }
    }

    /// 由条目 id 反查对应的内置命令；非命令条目返回 nil。
    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }

    /// 从目录而非 `AppIndex` 中查找：被禁用功能的命令不会出现在索引里。
    static func entry(for command: CommandID) -> AppEntry? {
        all.first { $0.id == command.rawValue }
    }

    /// 查询驱动型行只回答某一次查询，因此对它做学习或固定会让 URL 的排序失真。
    static func isQueryDriven(_ entry: AppEntry) -> Bool {
        command(for: entry)?.isQueryDriven ?? false
    }

    /// 输入网址时获得的行；与目录条目不同，它的 URL 就是真实目标地址。
    static func openInBrowser(for query: String) -> AppEntry? {
        guard case .web(let url)? = QuicklinkDestination.detect(query) else { return nil }
        return makeEntry(.openInBrowser, url: url, subtitle: "URL")
    }

    /// 构建命令对应的行，而不是查找得到——`all` 中不包含任何查询驱动型命令。
    nonisolated static func makeEntry(
        _ id: CommandID, url: URL? = nil, subtitle: String? = nil
    ) -> AppEntry {
        AppEntry(
            id: id.rawValue, name: id.name, url: url ?? placeholderURL(id), bundleID: nil,
            kind: id.entryKind, settingsOwner: id.owner, subtitle: subtitle)
    }

    /// 为命令生成占位 URL；命令条目本身靠 id 派发，URL 不参与实际跳转。
    nonisolated private static func placeholderURL(_ id: CommandID) -> URL {
        URL(string: "gearmac://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!
    }
}

/// 某个面板自行列出的命令；它们是否存在由该面板自己的开关决定，而非 `Enable Commands`。
extension SettingsTab {
    var ownedCommands: [CommandID] {
        switch self {
        case .quicklinks:
            [.createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks]
        case .ai: [.quickAI, .aiChat]
        case .quickActions: [.fixGrammar, .rewrite, .translate, .summarize, .decide]
        case .fileSearch: [.searchFiles]
        case .notes: [.showNotes, .createNote, .searchNotes]
        case .snippets: [.searchSnippets, .createSnippet]
        case .navigation: [.switchWindows, .searchMenuItems]
        case .windowManagement:
            [.createWindowLayout, .captureWindowLayout, .switchRoom, .createRoom]
        case .clipboard: [.clipboardHistory, .pasteSequentially]
        case .emoji: [.searchEmoji]
        case .calendar:
            [.joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar]
        default: []
        }
    }
}

extension CommandID {
    /// 列出该命令控件所在的面板；为 nil 时归到 Settings › Commands。
    var owner: SettingsTab? { Self.owners[self] }

    nonisolated private static let owners: [CommandID: SettingsTab] =
        SettingsTab.allCases.reduce(into: [:]) { table, tab in
            for command in tab.ownedCommands { table[command] = tab }
        }

    /// 该命令在启动器中的条目类别：内置快捷动作与普通命令区分展示。
    var entryKind: AppEntry.Kind {
        builtInQuickAction == nil ? .command : .quickAction
    }
}
