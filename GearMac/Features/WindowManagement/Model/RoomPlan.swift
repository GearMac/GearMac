// 文件职责：在任何 AX 写入前纯计算进入一个房间在某显示器上的全部动作（放置、缺失、暂存）。
// 分层：Model；纯逻辑，仅依赖 CoreGraphics/Foundation，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// 扫描找到的一个窗口。只是一个句柄而非 `AXUIElement`：本层保持纯净。
struct RoomLiveWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var appName: String
    var title: String
    var windowID: UInt32?
    var frame: CGRect
    var isMinimized = false
    var isAppHidden = false
    /// 窗口服务器由前到后的顺序；不在屏幕上时为 `.max`。
    var frontRank = Int.max
    var appURL: URL?
}

/// 进入房间在一块显示器上要做的全部事情，在任何 AX 写入前就已决定。纯函数。
struct RoomPlan: Equatable, Sendable {
    struct Placement: Equatable, Sendable {
        var index: Int
        var handle: Int
        var frame: CGRect
    }

    /// 房间顺序，主窗口在前：逆序抬起，它最终位于最前。
    var placements: [Placement]
    var missing: [Int]
    /// 房间所涉 app 的其他窗口：它们被暂存，因为隐藏它们会连房间一起隐藏。
    var parks: [Int]
    var keeps: Set<String>

    /// 其他 app 隐藏时桌面自身的 app 总会回来，因此它的窗口改为暂存。
    static let parksInsteadOfHiding: Set<String> = ["com.apple.finder"]

    /// 有意不检查功能开关：该守卫存在于 coordinator 中。
    static func make(
        _ room: Room, windows: [RoomLiveWindow], on screen: WindowLayoutScreen, gap: CGFloat,
        minimums: [String: CGSize], claimed: Set<UInt32> = []
    ) -> RoomPlan {
        let assignment = RoomWindowMatcher.assign(room.windows, to: windows, claimed: claimed)
        let found = room.windows.indices.filter { assignment[$0] != nil }
        let frames = frames(
            for: room, indices: found, kind: room.layout(onDisplay: screen.display.uuid),
            in: screen.screen.visibleFrame, gap: gap,
            minimums: found.map { minimums[room.windows[$0].bundleID] ?? .zero })
        let placements = zip(found, frames).compactMap { index, frame -> Placement? in
            assignment[index].map { Placement(index: index, handle: windows[$0].handle, frame: frame) }
        }
        let placed = Set(placements.map(\.handle))
        let roomApps = Set(placements.map { room.windows[$0.index].bundleID })
        let parks = windows.filter {
            !placed.contains($0.handle) && !$0.isMinimized
                && (roomApps.contains($0.bundleID) || parksInsteadOfHiding.contains($0.bundleID))
        }.map(\.handle)
        return RoomPlan(
            placements: placements, missing: room.windows.indices.filter { assignment[$0] == nil },
            parks: parks,
            keeps: Set(room.windows.map(\.bundleID)).union(parksInsteadOfHiding))
    }

    /// `indices` 处窗口的去向；不再放得下的布局会回退为 Auto。
    static func frames(
        for room: Room, indices: [Int], kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize]
    ) -> [CGRect] {
        let count = indices.count
        let auto = {
            RoomLayoutEngine.frames(
                count: count, kind: .auto, in: visible, gap: gap, minimums: minimums)
        }
        switch kind {
        case .saved:
            let rects = indices.map { index in
                WindowPlacementEngine.clamped(
                    RoomParking.returnFrame(
                        for: room.windows[index].frame(in: visible), screens: [visible]),
                    into: visible)
            }
            return rects.allSatisfy(visible.contains) ? rects : auto()
        case .custom:
            let cells = indices.compactMap { room.windows[$0].cell }
            guard cells.count == count, count == room.windows.count,
                let rects = RoomGrid.frames(cells, in: visible, gap: gap, minimums: minimums)
            else { return auto() }
            let box = RoomLayoutEngine.Area(visible: visible, gap: gap).canvas
            return RoomLayoutEngine.isClean(rects, in: box.insetBy(dx: -1, dy: -1)) ? rects : auto()
        case .focus, .columns, .grid:
            guard
                RoomLayoutEngine.fits(
                    count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
            else { return auto() }
            return RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
        case .auto, .stack:
            return RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
        }
    }

    /// 此处 Tab 会步进的内容：所有放得下且看起来互不相同的布局。
    static func layoutChoices(
        for room: Room, windows: [RoomLiveWindow], on screen: WindowLayoutScreen, gap: CGFloat,
        minimums: [String: CGSize], claimed: Set<UInt32> = []
    ) -> [RoomLayoutKind] {
        let visible = screen.screen.visibleFrame
        let assignment = RoomWindowMatcher.assign(room.windows, to: windows, claimed: claimed)
        let present = room.windows.indices.filter { assignment[$0] != nil }
        let count = present.count
        let current = room.layout(onDisplay: screen.display.uuid)
        guard count > 1 else { return current == .auto ? [.auto] : [.auto, current] }
        let sizes = present.map { minimums[room.windows[$0].bundleID] ?? .zero }
        let auto = RoomLayoutEngine.frames(
            count: count, kind: .auto, in: visible, gap: gap, minimums: sizes)
        var seen: [[CGRect]] = []
        var choices: [RoomLayoutKind] = []
        for kind in RoomLayoutKind.allCases {
            switch kind {
            case .custom:
                let complete =
                    count == room.windows.count
                    && present.allSatisfy { room.windows[$0].cell != nil }
                if complete,
                    frames(
                        for: room, indices: present, kind: .custom, in: visible, gap: gap,
                        minimums: sizes) != auto
                {
                    choices.append(kind)
                }
            case .saved:
                // 只有 Remember Arrangement 会产生它，Tab 从不凭空造出。
                if current == .saved { choices.append(kind) }
            case .auto, .focus, .stack, .columns, .grid:
                guard
                    RoomLayoutEngine.fits(
                        count: count, kind: kind, in: visible, gap: gap, minimums: sizes)
                else { continue }
                let rects = RoomLayoutEngine.frames(
                    count: count, kind: kind, in: visible, gap: gap, minimums: sizes)
                if kind != .auto, seen.contains(rects) { continue }
                seen.append(rects)
                choices.append(kind)
            }
        }
        // 只有在没有更整齐的布局可用时才用 Stack 的重叠卡片。
        if current != .stack, choices.contains(where: { [.focus, .columns, .grid].contains($0) }) {
            choices.removeAll { $0 == .stack }
        }
        return choices
    }

    /// `current` 之后的选择（循环）；仅一种布局可用时返回 nil，以便 Tab 说明。
    static func nextLayout(
        after current: RoomLayoutKind, in choices: [RoomLayoutKind], backwards: Bool
    ) -> RoomLayoutKind? {
        guard choices.count > 1 else { return nil }
        let index = choices.firstIndex(of: current) ?? 0
        return choices[(index + (backwards ? choices.count - 1 : 1)) % choices.count]
    }
}
