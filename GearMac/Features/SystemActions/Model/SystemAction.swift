// 文件职责：系统动作的模型定义，枚举全部动作 ID、确认策略与展示名/图标，并提供目录查询。
// 分层：Model；纯数据，不 import AppKit/SwiftUI，也不执行任何副作用。
import Foundation

/// 一个系统动作：稳定 ID、展示名、SF Symbol 图标名与确认策略。
struct SystemAction: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case lockScreen = "lock-screen"
        case sleep
        case sleepDisplays = "sleep-displays"
        case restart
        case shutDown = "shut-down"
        case logOut = "log-out"
        case showScreenSaver = "show-screen-saver"
        case playPause = "play-pause"
        case nextTrack = "next-track"
        case previousTrack = "previous-track"
        case toggleMute = "toggle-mute"
        case toggleMicrophoneMute = "toggle-microphone-mute"
        case volumeUp = "volume-up"
        case volumeDown = "volume-down"
        case setVolume = "set-volume"
        case volume0 = "volume-0"
        case volume25 = "volume-25"
        case volume50 = "volume-50"
        case volume75 = "volume-75"
        case volume100 = "volume-100"
        case showDesktop = "show-desktop"
        case toggleAppearance = "toggle-system-appearance"
        case toggleStageManager = "toggle-stage-manager"
        case openTrash = "open-trash"
        case emptyTrash = "empty-trash"
        case ejectAllDisks = "eject-all-disks"
        case toggleHiddenFiles = "toggle-hidden-files"
        case hideOtherApps = "hide-all-apps-except-frontmost"
        case unhideAllApps = "unhide-all-hidden-apps"
        case quitAllApps = "quit-all-apps"
        case dismissNotifications = "dismiss-notifications"
        case toggleBluetooth = "toggle-bluetooth"
    }

    /// 是否先弹确认及其文案；需要确认的动作一律具有破坏性。
    enum Confirmation: Hashable, Sendable {
        case none
        case required(title: SystemActionsKey, message: SystemActionsKey)
        /// 仅在 Finder 自身的「清空废纸篓前显示警告」开启时才询问。
        case followsFinder(title: SystemActionsKey, message: SystemActionsKey)
        /// 仅 Quit All 需要先统计目标数量，因此它的文案在调用时构建。
        case computed
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let confirmation: Confirmation

    /// 该条目的稳定标识，其持久化键也一并基于它。
    var entryID: String { "system-action:" + id.rawValue }

    /// 动作的本地化展示名。
    func localizedTitle(_ language: AppLanguage) -> String {
        L10n.string(SystemActionCatalog.nameKey(for: id), language: language)
    }
}

/// 系统动作目录：构建全部动作及其按 ID / entryID 的索引。
enum SystemActionCatalog {
    static let all: [SystemAction] = SystemAction.ID.allCases.map { id in
        SystemAction(
            id: id, name: L10n.string(nameKey(for: id), language: .english),
            sfSymbol: symbol(for: id),
            confirmation: confirmation(for: id))
    }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func action(forEntryID entryID: String) -> SystemAction? {
        byEntryID[entryID]
    }

    static func action(id: SystemAction.ID) -> SystemAction {
        // 按构造每个 ID 都在 `all` 中，因此查不到属于程序员错误。
        byID[id]!
    }

    /// 动作展示名对应的本地化键。
    static func nameKey(for id: SystemAction.ID) -> SystemActionsKey {
        switch id {
        case .lockScreen: return .lockScreen
        case .sleep: return .sleep
        case .sleepDisplays: return .sleepDisplays
        case .restart: return .restart
        case .shutDown: return .shutDown
        case .logOut: return .logOut
        case .showScreenSaver: return .showScreenSaver
        case .playPause: return .playPause
        case .nextTrack: return .nextTrack
        case .previousTrack: return .previousTrack
        case .toggleMute: return .toggleMute
        case .toggleMicrophoneMute: return .toggleMicrophoneMute
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .setVolume: return .setVolume
        case .volume0: return .volume0
        case .volume25: return .volume25
        case .volume50: return .volume50
        case .volume75: return .volume75
        case .volume100: return .volume100
        case .showDesktop: return .showDesktop
        case .toggleAppearance: return .toggleAppearance
        case .toggleStageManager: return .toggleStageManager
        case .openTrash: return .openTrash
        case .emptyTrash: return .emptyTrash
        case .ejectAllDisks: return .ejectAllDisks
        case .toggleHiddenFiles: return .toggleHiddenFiles
        case .hideOtherApps: return .hideOtherApps
        case .unhideAllApps: return .unhideAllApps
        case .quitAllApps: return .quitAllApps
        case .dismissNotifications: return .dismissNotifications
        case .toggleBluetooth: return .toggleBluetooth
        }
    }

    /// 动作对应的图标名（SF Symbol 或内置资源名）。
    private static func symbol(for id: SystemAction.ID) -> String {
        switch id {
        case .lockScreen: return "lock"
        case .sleep: return "moon.zzz"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .showScreenSaver: return "rectangle.inset.filled"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .toggleMute: return "speaker.slash"
        case .toggleMicrophoneMute: return "mic.slash"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .setVolume, .volume0, .volume25, .volume50, .volume75, .volume100:
            return "speaker.wave.2"
        case .showDesktop: return "macwindow.on.rectangle"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .toggleStageManager: return "squares.leading.rectangle"
        case .openTrash: return "trash"
        case .emptyTrash: return "trash.slash"
        case .ejectAllDisks: return "eject"
        case .toggleHiddenFiles: return "eye.slash"
        case .hideOtherApps: return "eye.slash.circle"
        case .unhideAllApps: return "eye.circle"
        case .quitAllApps: return "xmark.circle"
        case .dismissNotifications: return "bell.slash"
        // 这不是 SF Symbol：蓝牙标志是商标，因此使用内置资源。
        case .toggleBluetooth: return "bluetooth"
        }
    }

    /// 动作的确认策略。
    private static func confirmation(for id: SystemAction.ID) -> SystemAction.Confirmation {
        switch id {
        case .restart:
            return .required(
                title: .confirmRestartTitle, message: .confirmSessionEndingMessage)
        case .shutDown:
            return .required(
                title: .confirmShutDownTitle, message: .confirmSessionEndingMessage)
        case .logOut:
            return .required(title: .confirmLogOutTitle, message: .confirmSessionEndingMessage)
        case .emptyTrash:
            return .followsFinder(
                title: .confirmEmptyTrashTitle, message: .confirmEmptyTrashMessage)
        case .quitAllApps:
            return .computed
        default:
            return .none
        }
    }
}
