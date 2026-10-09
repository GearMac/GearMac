// 文件职责：定义房间持有的单个窗口及其识别信息（bundleID、标题、windowID、单位化 frame、grid 单元格）。
// 分层：Model；保持纯净，仅依赖 CoreGraphics/Foundation，手写解码以兼容旧备份。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// 房间持有的一个窗口，以及重新找到它的依据。
struct RoomWindow: Codable, Hashable, Sendable {
    var bundleID: String
    var appName: String
    /// 当窗口 ID 在其 app 重启后失效时，靠它重新找到窗口。
    var title: String
    /// 窗口服务器分配的编号；仅在窗口保持打开期间有效。
    var windowID: UInt32?
    /// `.saved` 下它所在的位置，用显示器可见区域的比例表示。
    var unitFrame: CGRect
    var cell: RoomGrid.Cell?

    init(
        bundleID: String, appName: String, title: String, windowID: UInt32? = nil,
        unitFrame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), cell: RoomGrid.Cell? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowID = windowID
        self.unitFrame = unitFrame
        self.cell = cell
    }

    /// 保留四位小数，使存储的比例读起来干净，并总能解析回同一个点。
    static func unitFrame(of frame: CGRect, in visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        func fraction(_ value: CGFloat) -> CGFloat { (value * 10_000).rounded() / 10_000 }
        return CGRect(
            x: fraction((frame.minX - visible.minX) / visible.width),
            y: fraction((frame.minY - visible.minY) / visible.height),
            width: fraction(frame.width / visible.width),
            height: fraction(frame.height / visible.height))
    }

    func frame(in visible: CGRect) -> CGRect {
        WindowPlacementEngine.rounded(
            CGRect(
                x: visible.minX + unitFrame.minX * visible.width,
                y: visible.minY + unitFrame.minY * visible.height,
                width: unitFrame.width * visible.width,
                height: unitFrame.height * visible.height))
    }

    // 手写实现，使新增字段不会破坏已存房间与旧备份的可读性。
    private enum CodingKeys: String, CodingKey {
        case bundleID, appName, title, windowID, unitFrame, cell
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? bundleID
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        windowID = try container.decodeIfPresent(UInt32.self, forKey: .windowID)
        unitFrame =
            try container.decodeIfPresent(CGRect.self, forKey: .unitFrame)
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        cell = try container.decodeIfPresent(RoomGrid.Cell.self, forKey: .cell)
    }
}
