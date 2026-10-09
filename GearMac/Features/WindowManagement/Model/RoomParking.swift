// 文件职责：计算房间在外时窗口的暂存（parking）位置，以及窗口回到连接显示器上的返回位置。
// 分层：Model；纯几何计算，仅依赖 CoreGraphics，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// 窗口在房间不在别处时等待的位置，以及它回来的位置。
enum RoomParking {
    /// 1pt 的细条保留在 `visible` 内，macOS 才会留存它；任何角不得溢出到其他显示器。
    static func origin(for size: CGSize, on visible: CGRect, avoiding others: [CGRect]) -> CGPoint {
        let corners = [
            CGPoint(x: visible.maxX - 1, y: visible.maxY - 1),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.maxY - 1),
            CGPoint(x: visible.maxX - 1, y: visible.minY + 1 - size.height),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.minY + 1 - size.height)
        ]
        func spill(_ origin: CGPoint) -> CGFloat {
            let parked = CGRect(origin: origin, size: size)
            return others.reduce(0) { $0 + overlapArea($1, parked) }
        }
        return corners.first { spill($0) == 0 }
            ?? corners.min { spill($0) < spill($1) } ?? corners[0]
    }

    /// 回到已连接显示器上的方式：显示器已消失的窗口回到第一块屏，并适配尺寸。
    static func returnFrame(for frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let first = screens.first, !screens.contains(where: { overlapArea($0, frame) > 0 })
        else { return frame }
        let size = CGSize(width: min(frame.width, first.width), height: min(frame.height, first.height))
        return WindowPlacementEngine.rounded(
            CGRect(
                x: first.midX - size.width / 2, y: first.midY - size.height / 2,
                width: size.width, height: size.height))
    }

    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let shared = lhs.intersection(rhs)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
