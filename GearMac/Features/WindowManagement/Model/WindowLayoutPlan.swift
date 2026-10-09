// 文件职责：在任何 AX 写入前纯计算一次布局运行的全部计划：每个条目的放置、跳过原因与启动项。
// 分层：Model；纯逻辑，仅依赖 CoreGraphics/Foundation，不 import AppKit/SwiftUI。
import CoreGraphics
import Foundation

/// 一块已连接的显示器：条目匹配所用的身份，加上它实时的 AX 空间几何。
struct WindowLayoutScreen: Equatable, Sendable {
    var display: WindowLayoutDisplay
    var screen: WindowPlacementEngine.Screen
}

/// 清单找到的一个窗口。只是一个句柄而非 `AXUIElement`：本层保持纯净。
struct WindowLayoutWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var frame: CGRect
    /// 仅用于让绑定顺序保持确定。
    var title: String

    init(handle: Int, bundleID: String, frame: CGRect, title: String = "") {
        self.handle = handle
        self.bundleID = bundleID
        self.frame = frame
        self.title = title
    }
}

/// 运行一次布局要做的全部事情，在任何 AX 写入之前就已决定。纯函数。
struct WindowLayoutPlan: Equatable, Sendable {
    /// 一个条目为何没有产生放置。每种都是预期行为，而非错误。
    enum Skip: Equatable, Sendable {
        case displayDisconnected(name: String)
        /// 显示器没有报告可用的可见区域，因此 `resolve` 拒绝。
        case unresolvableGeometry
        /// 更早的条目已占用该 app 与该参数；没有窗口可给了。
        case duplicateTarget
    }

    /// 放置所用窗口的来源。
    enum Source: Equatable, Sendable {
        case existing(handle: Int)
        /// 打开它，然后取出现的窗口。
        case launch
    }

    struct Placement: Equatable, Sendable {
        var entryID: UUID
        var bundleID: String
        var argument: String?
        var source: Source
        var frame: CGRect
        var screenID: Int
        var anchor: WindowLayoutAnchor
        /// app 拒绝缩到 `frame` 时要重新夹取进的盒子。
        var canvas: CGRect
    }

    struct Skipped: Equatable, Sendable {
        var entryID: UUID
        var reason: Skip
    }

    /// 按条目顺序，使同一 app 两个窗口的布局总能以相同方式落位。
    var placements: [Placement]
    var skipped: [Skipped]
    /// 布局的最前条目，仅当它产生了可提到前面的放置时才保留。
    var frontmostEntryID: UUID?

    /// 每个需启动的放置对应一次打开；计划已保证它们互不相同。
    var opens: [Placement] { placements.filter { $0.source == .launch } }

    /// HUD 的第二句文案，在此推导，使 coordinator 保持声明式。
    var skippedSummary: String? {
        guard !skipped.isEmpty else { return nil }
        let displays = Set(
            skipped.compactMap { skip -> String? in
                guard case .displayDisconnected(let name) = skip.reason else { return nil }
                return name
            })
        if !displays.isEmpty, displays.count == skipped.count {
            return displays.count == 1
                ? "1 display not connected" : "\(displays.count) displays not connected"
        }
        return skipped.count == 1 ? "1 entry skipped" : "\(skipped.count) entries skipped"
    }

    /// 按语言取跳过原因摘要；无跳过项时为 nil。
    func localizedSkippedSummary(_ language: AppLanguage) -> String? {
        guard !skipped.isEmpty else { return nil }
        let displays = Set(
            skipped.compactMap { skip -> String? in
                guard case .displayDisconnected(let name) = skip.reason else { return nil }
                return name
            })
        if !displays.isEmpty, displays.count == skipped.count {
            return displays.count == 1
                ? L10n.string(WindowKey.skipDisplayOne, language: language)
                : String(
                    format: L10n.string(WindowKey.skipDisplayMany, language: language),
                    displays.count)
        }
        return skipped.count == 1
            ? L10n.string(WindowKey.skipEntryOne, language: language)
            : String(
                format: L10n.string(WindowKey.skipEntryMany, language: language), skipped.count)
    }

    /// 有意不检查 `isEnabled`：该守卫只存在于 coordinator 中。
    static func make(
        layout: WindowLayout, screens: [WindowLayoutScreen], windows: [WindowLayoutWindow],
        preferredGap: CGFloat
    ) -> WindowLayoutPlan {
        let gap = layout.usesPreferredGap ? preferredGap : 0
        var screensByUUID: [String: WindowLayoutScreen] = [:]
        for screen in screens where screensByUUID[screen.display.uuid.lowercased()] == nil {
            screensByUUID[screen.display.uuid.lowercased()] = screen
        }
        var available = Dictionary(grouping: sorted(windows), by: \.bundleID)
        var launched: Set<String> = []
        var placements: [Placement] = []
        var skipped: [Skipped] = []

        for entry in layout.entries {
            guard let target = screensByUUID[entry.display.uuid.lowercased()] else {
                skipped.append(
                    Skipped(
                        entryID: entry.id, reason: .displayDisconnected(name: entry.display.name)))
                continue
            }
            guard
                let frame = WindowLayoutGeometry.resolve(entry, on: target.screen, gap: gap)
            else {
                skipped.append(Skipped(entryID: entry.id, reason: .unresolvableGeometry))
                continue
            }

            let source: Source
            if entry.argument == nil,
                let index = nearest(to: frame, among: available[entry.bundleID] ?? [])
            {
                source = .existing(handle: available[entry.bundleID]!.remove(at: index).handle)
            } else {
                // 用同一参数打开同一个 app 两次只会得到一个窗口，而不是两个。
                let key = entry.bundleID + "\u{0}" + (entry.argument ?? "")
                guard launched.insert(key).inserted else {
                    skipped.append(Skipped(entryID: entry.id, reason: .duplicateTarget))
                    continue
                }
                source = .launch
            }

            placements.append(
                Placement(
                    entryID: entry.id, bundleID: entry.bundleID, argument: entry.argument,
                    source: source, frame: frame, screenID: target.screen.id, anchor: entry.anchor,
                    canvas: WindowLayoutGeometry.box(target.screen, gap: gap)))
        }
        let frontmost = placements.first { $0.entryID == layout.frontmostEntryID }?.entryID
        return WindowLayoutPlan(
            placements: placements, skipped: skipped, frontmostEntryID: frontmost)
    }

    /// 中心最近者胜出，因此已就绪的桌面是空操作，也不会有窗口换显示器。
    private static func nearest(to frame: CGRect, among windows: [WindowLayoutWindow]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, window) in windows.enumerated() {
            let distance =
                abs(window.frame.midX - frame.midX) + abs(window.frame.midY - frame.midY)
            if distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    /// 阅读顺序，使清单被打乱也无法改变计划。
    private static func sorted(_ windows: [WindowLayoutWindow]) -> [WindowLayoutWindow] {
        windows.sorted {
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.handle < $1.handle
        }
    }
}
