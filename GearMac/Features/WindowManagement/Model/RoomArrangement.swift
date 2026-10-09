// 文件职责：阅读手动调好的窗口摆放，推断它最接近哪种房间布局及每个窗口的位置。
// 分层：Model；纯逻辑，仅依赖 CoreGraphics/Foundation，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// 阅读手动调好的摆法：它最接近的布局，以及谁坐在哪里。
enum RoomArrangement {
    struct Reading: Equatable, Sendable {
        var kind: RoomLayoutKind
        /// 该布局下按房间顺序排列的窗口下标，主窗口在前。
        var order: [Int]
        /// 任一窗口离自己位置最远的值，对四条边取平均。
        var distance: CGFloat
        /// 当 Reading 为 `.custom` 时，按 `order` 排列的每个窗口的单元格。
        var cells: [RoomGrid.Cell]?
    }

    /// 每个窗口都在自己的位置这么多点以内时，就认为它属于该布局。
    static let tolerance: CGFloat = 40

    static func read(
        _ frames: [CGRect], in visible: CGRect, gap: CGFloat, minimums: [CGSize] = []
    ) -> Reading {
        let count = frames.count
        guard count > 1 else {
            return Reading(kind: count == 1 ? .focus : .saved, order: Array(0..<count), distance: 0)
        }
        var best = Reading(kind: .saved, order: Array(0..<count), distance: .infinity)
        for kind in [RoomLayoutKind.focus, .stack, .columns, .grid] {
            let spots = RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
            var used = Set<Int>()
            var order: [Int] = []
            var worst: CGFloat = 0
            for spot in spots {
                guard
                    let nearest = frames.indices.filter({ !used.contains($0) }).min(by: {
                        distance(frames[$0], spot) < distance(frames[$1], spot)
                    })
                else { break }
                used.insert(nearest)
                order.append(nearest)
                worst = max(worst, distance(frames[nearest], spot))
            }
            // 每个窗口都必须落位，否则三列整齐的三分屏会掩盖下方的 ⅔ + ⅓。
            if worst < best.distance { best = Reading(kind: kind, order: order, distance: worst) }
        }
        if best.distance <= tolerance { return best }
        if let cells = RoomGrid.cells(for: frames, in: visible, gap: gap) {
            return Reading(
                kind: .custom, order: Array(0..<count), distance: best.distance, cells: cells)
        }
        return Reading(kind: .saved, order: Array(0..<count), distance: best.distance)
    }

    /// 用打开的窗口重建 `room`，再加上 `kept`：没有任何打开窗口填充的成员。
    static func learn(
        _ room: Room, from windows: [RoomLiveWindow], keeping kept: [RoomWindow] = [],
        on screen: WindowLayoutScreen, spansDisplays: Bool, gap: CGFloat, minimums: [CGSize],
        keepsOrder: Bool
    ) -> (room: Room, reading: Reading) {
        let visible = screen.screen.visibleFrame
        var reading = read(windows.map(\.frame), in: visible, gap: gap, minimums: minimums)
        // 来自多块显示器的窗口无法读出摆法；房间会落到其中一块上。
        if spansDisplays || (keepsOrder && reading.kind == .saved) {
            reading = Reading(
                kind: .auto, order: Array(windows.indices), distance: reading.distance)
        }
        let ordered = keepsOrder ? windows : reading.order.map { windows[$0] }
        var learned = ordered.map { window in
            RoomWindow(
                bundleID: window.bundleID, appName: window.appName, title: window.title,
                windowID: window.windowID,
                unitFrame: RoomWindow.unitFrame(of: window.frame, in: visible))
        }
        if reading.kind == .custom, let cells = reading.cells, cells.count == learned.count {
            for index in learned.indices { learned[index].cell = cells[index] }
        }
        var updated = room
        updated.windows = learned + kept
        updated.layoutsByDisplay[screen.display.uuid.lowercased()] = reading.kind
        return (updated, reading)
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        (abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.maxX - rhs.maxX)
            + abs(lhs.maxY - rhs.maxY)) / 4
    }
}
