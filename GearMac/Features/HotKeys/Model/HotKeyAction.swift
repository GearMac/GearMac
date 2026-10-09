// 文件职责：枚举 GearMac 中所有可被全局快捷键绑定的目标，并给出每个目标唯一的 UserDefaults 键与注册 id。
// 分层：Model；纯枚举，不引入副作用。
import Foundation

/// GearMac 中所有可绑定全局快捷键的目标。
enum HotKeyAction: Hashable, Sendable {
    /// 没有自己命令行的固定动作。
    case togglePalette
    case dictation
    /// 以命令目录为参数，因此新增内置命令无需在此添加分支即可绑定。
    case command(CommandID)
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case windowLayout(id: UUID)
    case windowRoom(id: UUID)
    case customWindowSize(id: UUID)
    case quicklink(id: UUID)
    case quickAction(id: UUID)
    case appleShortcut(id: UUID)
    case snippet(id: StoredSnippet.ID)
    /// 以 `AppEntry.id` 为键，扩展重装后该标识仍然保留。
    case extensionCommand(entryID: String)

    /// UserDefaults 键，同时也是 `HotKeyCenter` 的注册 id：每个动作唯一。
    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .dictation: "hotkey.dictation"
        case .command(let id): "hotkey." + id.rawValue
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .customCommand(let id): "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .windowLayout(let id): "hotkey.windowLayout." + id.uuidString.lowercased()
        case .windowRoom(let id): "hotkey.windowRoom." + id.uuidString.lowercased()
        case .customWindowSize(let id):
            "hotkey.customWindowSize." + id.uuidString.lowercased()
        case .quicklink(let id): "hotkey.quicklink." + id.uuidString.lowercased()
        case .quickAction(let id): "hotkey.quickAction." + id.uuidString.lowercased()
        case .appleShortcut(let id): "hotkey.appleShortcut." + id.uuidString.lowercased()
        case .snippet(let id): "hotkey.snippet." + id
        case .extensionCommand(let entryID): "hotkey.extensionCommand." + entryID
        }
    }

    /// 每个安装都可绑定的固定动作；各条目目录会在启动时扩展它们。
    static let builtInActions: [HotKeyAction] =
        [.togglePalette, .dictation] + CommandID.allCases.compactMap(\.hotKeyAction)
}
