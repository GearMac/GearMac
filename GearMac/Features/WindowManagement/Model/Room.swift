// 文件职责：定义房间（room）模型——一个有名字的窗口集合及它们的布局，并处理其编解码与排序。
// 分层：Model；保持纯净，仅依赖 Foundation，手写解码以兼容旧备份。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// 一个你走进去的项目：它的窗口（有序）以及它们的排布方式。见 window-rooms.md。
struct Room: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-room:"
    static let sfSymbol = "door.left.hand.open"

    let id: UUID
    var name: String
    /// 第一个是主窗口：它占据最大的位置，并最终位于最前。
    var windows: [RoomWindow]
    var layout: RoomLayoutKind
    /// 在某块显示器上选定的布局，以该显示器 UUID 的小写形式为键；`layout` 覆盖其余显示器。
    var layoutsByDisplay: [String: RoomLayoutKind]
    var lastEnteredAt: Date?

    init(
        id: UUID = UUID(), name: String, windows: [RoomWindow] = [],
        layout: RoomLayoutKind = .auto, layoutsByDisplay: [String: RoomLayoutKind] = [:],
        lastEnteredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.windows = windows
        self.layout = layout
        self.layoutsByDisplay = layoutsByDisplay
        self.lastEnteredAt = lastEnteredAt
    }

    func layout(onDisplay uuid: String?) -> RoomLayoutKind {
        uuid.flatMap { layoutsByDisplay[$0.lowercased()] } ?? layout
    }

    /// 房间在别处被写入时的形态，保留进入 `learned` 时这台 Mac 学到的东西。
    func keepingRuntime(of learned: Room) -> Room {
        var room = self
        room.lastEnteredAt = learned.lastEnteredAt
        // 窗口编号只会回到同一 app 的窗口，因此一次编辑不会造成错配。
        for (index, window) in zip(room.windows.indices, learned.windows)
        where window.bundleID == room.windows[index].bundleID {
            room.windows[index].windowID = window.windowID
        }
        return room
    }

    var summary: String { windows.count == 1 ? "1 window" : "\(windows.count) windows" }

    /// 按语言取副标题：窗口数量。
    func localizedSummary(_ language: AppLanguage) -> String {
        windows.count == 1
            ? L10n.string(WindowKey.summaryWindowOne, language: language)
            : String(format: L10n.string(WindowKey.summaryWindowMany, language: language), windows.count)
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// 唯一的名称排序，store 与 `AppIndex` 切片都按它排序。
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// 最近进入的排在最前，这样你刚离开的房间只需一行之遥。
    static func enteredMoreRecently(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = lhs.lastEnteredAt ?? .distantPast
        let right = rhs.lastEnteredAt ?? .distantPast
        return left != right ? left > right : precedes(lhs, rhs)
    }

    // 手写实现，使新增字段不会破坏已存房间与旧备份的可读性。
    private enum CodingKeys: String, CodingKey {
        case id, name, windows, layout, layoutsByDisplay, lastEnteredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        windows = try container.decodeIfPresent([RoomWindow].self, forKey: .windows) ?? []
        // 本构建不认识的布局会重置为 Auto，而不是丢弃整个房间。
        layout = (try? container.decodeIfPresent(RoomLayoutKind.self, forKey: .layout)) ?? .auto
        let stored =
            (try? container.decodeIfPresent([String: String].self, forKey: .layoutsByDisplay)) ?? [:]
        layoutsByDisplay = stored.compactMapValues(RoomLayoutKind.init(rawValue:))
        lastEnteredAt = try container.decodeIfPresent(Date.self, forKey: .lastEnteredAt)
    }
}

/// 房间记录校验失败的原因，附带面向用户的错误描述。
enum RoomValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noWindows
    case invalidCharacter

    var errorDescription: String? { localizedMessage(.system) }

    /// 按语言取面向用户的错误描述。
    func localizedMessage(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName: return L10n.string(WindowKey.errorRoomEmptyName, language: language)
        case .duplicateName:
            return L10n.string(WindowKey.errorRoomDuplicateName, language: language)
        case .noWindows: return L10n.string(WindowKey.errorRoomNoWindows, language: language)
        case .invalidCharacter:
            return L10n.string(WindowKey.errorNameNullCharacter, language: language)
        }
    }
}
