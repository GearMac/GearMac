// 文件职责：定义窗口命令目录——每个命令的标识、名称、图标、行为类别与分组。
// 分层：Model；保持纯净，仅依赖 Foundation，不 import AppKit/SwiftUI。
import Foundation

/// 一个窗口命令的目录条目：标识、显示名、图标、行为类别与分组。
struct WindowCommand: Identifiable, Hashable, Sendable {
    /// 每个窗口命令的稳定标识；原始值即设置文件中使用的键。
    enum ID: String, CaseIterable, Sendable {
        case leftHalf = "left-half"
        case rightHalf = "right-half"
        case topHalf = "top-half"
        case bottomHalf = "bottom-half"
        case topLeftQuarter = "top-left-quarter"
        case topRightQuarter = "top-right-quarter"
        case bottomLeftQuarter = "bottom-left-quarter"
        case bottomRightQuarter = "bottom-right-quarter"
        case firstThreeFourths = "first-three-fourths"
        case lastThreeFourths = "last-three-fourths"
        case firstThird = "first-third"
        case centerThird = "center-third"
        case lastThird = "last-third"
        case firstTwoThirds = "first-two-thirds"
        case lastTwoThirds = "last-two-thirds"
        case maximize
        case almostMaximize = "almost-maximize"
        case reasonableSize = "reasonable-size"
        case maximizeHeight = "maximize-height"
        case maximizeWidth = "maximize-width"
        case center
        case centerHalf = "center-half"
        case centerTwoThirds = "center-two-thirds"
        case makeLarger = "make-larger"
        case makeSmaller = "make-smaller"
        case restore
        case moveLeft = "move-left"
        case moveRight = "move-right"
        case moveUp = "move-up"
        case moveDown = "move-down"
        case nextDisplay = "next-display"
        case previousDisplay = "previous-display"
        case toggleFullscreen = "toggle-fullscreen"
        case previousSpace = "previous-space"
        case nextSpace = "next-space"
    }

    /// 移动器必须做什么，使它的分发对整个目录保持穷尽。
    enum Kind: String, Sendable {
        /// 从屏幕解算目标 frame 并写入。
        case geometry
        /// 也是几何，但来源是记录的动手前 frame，而非计算得出。
        case restore
        /// 完全没有几何——原生 `AXFullScreen` 切换。
        case fullscreen
        /// 完全没有窗口——在 Space 之间移动的合成 Dock 手势。
        case space
    }

    /// 命令所属的启动器分区，也是设置面板列出它们的顺序。
    enum Group: String, CaseIterable, Sendable {
        case halves
        case quarters
        case fourths
        case thirds
        case sizing
        case moving
        case fullscreen
        case spaces

        /// 按语言取分组标题。
        func localizedTitle(_ language: AppLanguage) -> String {
            switch self {
            case .halves: return L10n.string(WindowKey.groupHalves, language: language)
            case .quarters: return L10n.string(WindowKey.groupQuarters, language: language)
            case .fourths: return L10n.string(WindowKey.groupFourths, language: language)
            case .thirds: return L10n.string(WindowKey.groupThirds, language: language)
            case .sizing: return L10n.string(WindowKey.groupSizing, language: language)
            case .moving: return L10n.string(WindowKey.groupMoving, language: language)
            case .fullscreen: return L10n.string(WindowKey.groupFullscreen, language: language)
            case .spaces: return L10n.string(WindowKey.groupSpaces, language: language)
            }
        }
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let kind: Kind
    let group: Group
    /// 只有四个半屏会遵循 `WindowCycle`；其余忽略传给它们的步进。
    let cyclesOnRepeat: Bool
    /// 对于微调类为 false，使移动器绝不为它们写 `kAXSizeAttribute`。
    let resizes: Bool

    var entryID: String { "window-command:" + id.rawValue }

    /// 按语言取命令名称；`name` 保持英文不变，继续作为搜索与索引的稳定键。
    func localizedTitle(_ language: AppLanguage) -> String { id.localizedTitle(language) }
}

/// 窗口命令目录：从 `WindowCommand.ID` 派生全部命令元数据，并提供查询与分组。
enum WindowCommandCatalog {
    static let all: [WindowCommand] = WindowCommand.ID.allCases.map { id in
        WindowCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id), kind: kind(for: id),
            group: group(for: id), cyclesOnRepeat: cyclesOnRepeat.contains(id),
            resizes: !movesOnly.contains(id))
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(id: WindowCommand.ID) -> WindowCommand? { byID[id] }

    static func command(forEntryID entryID: String) -> WindowCommand? { byEntryID[entryID] }

    /// 按设置面板分组后的目录顺序；`ID.allCases` 本身即分组顺序，因此这是一次分区。
    static func grouped() -> [(group: WindowCommand.Group, commands: [WindowCommand])] {
        WindowCommand.Group.allCases.compactMap { group in
            let commands = all.filter { $0.group == group }
            return commands.isEmpty ? nil : (group, commands)
        }
    }

    static let cyclesOnRepeat: Set<WindowCommand.ID> = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf
    ]

    /// 微调只改变位置，绝不触碰尺寸。
    static let movesOnly: Set<WindowCommand.ID> = [.moveLeft, .moveRight, .moveUp, .moveDown]

    private static func name(for id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeftQuarter: return "Top Left Quarter"
        case .topRightQuarter: return "Top Right Quarter"
        case .bottomLeftQuarter: return "Bottom Left Quarter"
        case .bottomRightQuarter: return "Bottom Right Quarter"
        case .firstThreeFourths: return "First Three Fourths"
        case .lastThreeFourths: return "Last Three Fourths"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .reasonableSize: return "Reasonable Size"
        case .maximizeHeight: return "Maximize Height"
        case .maximizeWidth: return "Maximize Width"
        case .center: return "Center"
        case .centerHalf: return "Center Half"
        case .centerTwoThirds: return "Center Two Thirds"
        case .makeLarger: return "Make Larger"
        case .makeSmaller: return "Make Smaller"
        case .restore: return "Restore Window"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        case .nextDisplay: return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        case .toggleFullscreen: return "Toggle Fullscreen"
        case .previousSpace: return "Switch to Previous Space"
        case .nextSpace: return "Switch to Next Space"
        }
    }

    private static func symbol(for id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleading.filled"
        case .topRightQuarter: return "rectangle.inset.toptrailing.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleading.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomtrailing.filled"
        case .firstThreeFourths: return "rectangle.lefthalf.inset.filled"
        case .lastThreeFourths: return "rectangle.righthalf.inset.filled"
        case .firstThird, .firstTwoThirds: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .lastThird, .lastTwoThirds: return "rectangle.trailingthird.inset.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: return "rectangle.inset.filled"
        case .reasonableSize: return "macwindow"
        case .maximizeHeight: return "arrow.up.and.down"
        case .maximizeWidth: return "arrow.left.and.right"
        case .center: return "rectangle.center.inset.filled"
        case .centerHalf: return "rectangle.split.3x1"
        case .centerTwoThirds: return "rectangle.split.3x1.fill"
        case .makeLarger: return "plus.magnifyingglass"
        case .makeSmaller: return "minus.magnifyingglass"
        case .restore: return "arrow.uturn.backward"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        case .nextDisplay: return "rectangle.on.rectangle.angled"
        case .previousDisplay: return "rectangle.on.rectangle.angled"
        case .toggleFullscreen: return "arrow.up.left.and.arrow.down.right.square"
        case .previousSpace: return "chevron.backward.2"
        case .nextSpace: return "chevron.forward.2"
        }
    }

    private static func kind(for id: WindowCommand.ID) -> WindowCommand.Kind {
        switch id {
        case .restore: return .restore
        case .toggleFullscreen: return .fullscreen
        case .previousSpace, .nextSpace: return .space
        default: return .geometry
        }
    }

    private static func group(for id: WindowCommand.ID) -> WindowCommand.Group {
        switch id {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return .quarters
        case .firstThreeFourths, .lastThreeFourths:
            return .fourths
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            return .thirds
        case .maximize, .almostMaximize, .reasonableSize, .maximizeHeight, .maximizeWidth, .center,
            .centerHalf, .centerTwoThirds, .makeLarger, .makeSmaller, .restore:
            return .sizing
        case .moveLeft, .moveRight, .moveUp, .moveDown, .nextDisplay, .previousDisplay:
            return .moving
        case .toggleFullscreen:
            return .fullscreen
        case .previousSpace, .nextSpace:
            return .spaces
        }
    }
}

extension WindowCommand.ID {
    /// 按语言取命令的显示名称。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .leftHalf: return L10n.string(WindowKey.commandLeftHalf, language: language)
        case .rightHalf: return L10n.string(WindowKey.commandRightHalf, language: language)
        case .topHalf: return L10n.string(WindowKey.commandTopHalf, language: language)
        case .bottomHalf: return L10n.string(WindowKey.commandBottomHalf, language: language)
        case .topLeftQuarter: return L10n.string(WindowKey.commandTopLeftQuarter, language: language)
        case .topRightQuarter:
            return L10n.string(WindowKey.commandTopRightQuarter, language: language)
        case .bottomLeftQuarter:
            return L10n.string(WindowKey.commandBottomLeftQuarter, language: language)
        case .bottomRightQuarter:
            return L10n.string(WindowKey.commandBottomRightQuarter, language: language)
        case .firstThreeFourths:
            return L10n.string(WindowKey.commandFirstThreeFourths, language: language)
        case .lastThreeFourths:
            return L10n.string(WindowKey.commandLastThreeFourths, language: language)
        case .firstThird: return L10n.string(WindowKey.commandFirstThird, language: language)
        case .centerThird: return L10n.string(WindowKey.commandCenterThird, language: language)
        case .lastThird: return L10n.string(WindowKey.commandLastThird, language: language)
        case .firstTwoThirds:
            return L10n.string(WindowKey.commandFirstTwoThirds, language: language)
        case .lastTwoThirds: return L10n.string(WindowKey.commandLastTwoThirds, language: language)
        case .maximize: return L10n.string(WindowKey.commandMaximize, language: language)
        case .almostMaximize:
            return L10n.string(WindowKey.commandAlmostMaximize, language: language)
        case .reasonableSize:
            return L10n.string(WindowKey.commandReasonableSize, language: language)
        case .maximizeHeight:
            return L10n.string(WindowKey.commandMaximizeHeight, language: language)
        case .maximizeWidth:
            return L10n.string(WindowKey.commandMaximizeWidth, language: language)
        case .center: return L10n.string(WindowKey.commandCenter, language: language)
        case .centerHalf: return L10n.string(WindowKey.commandCenterHalf, language: language)
        case .centerTwoThirds:
            return L10n.string(WindowKey.commandCenterTwoThirds, language: language)
        case .makeLarger: return L10n.string(WindowKey.commandMakeLarger, language: language)
        case .makeSmaller: return L10n.string(WindowKey.commandMakeSmaller, language: language)
        case .restore: return L10n.string(WindowKey.commandRestore, language: language)
        case .moveLeft: return L10n.string(WindowKey.commandMoveLeft, language: language)
        case .moveRight: return L10n.string(WindowKey.commandMoveRight, language: language)
        case .moveUp: return L10n.string(WindowKey.commandMoveUp, language: language)
        case .moveDown: return L10n.string(WindowKey.commandMoveDown, language: language)
        case .nextDisplay: return L10n.string(WindowKey.commandNextDisplay, language: language)
        case .previousDisplay:
            return L10n.string(WindowKey.commandPreviousDisplay, language: language)
        case .toggleFullscreen:
            return L10n.string(WindowKey.commandToggleFullscreen, language: language)
        case .previousSpace:
            return L10n.string(WindowKey.commandPreviousSpace, language: language)
        case .nextSpace: return L10n.string(WindowKey.commandNextSpace, language: language)
        }
    }
}
