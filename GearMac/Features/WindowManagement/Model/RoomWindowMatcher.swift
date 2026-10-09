// 文件职责：把房间记录的窗口与当前打开的活窗口做一对一配对，每个活窗口最多用一次。
// 分层：Model；纯逻辑，仅依赖 Foundation，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// 哪个打开的窗口填入房间的哪个窗口。每个打开的窗口最多只用一次。
enum RoomWindowMatcher {
    /// 房间窗口下标 → 打开窗口下标。`claimed` 的窗口排到最后：它们被其他房间持有。
    static func assign(
        _ windows: [RoomWindow], to live: [RoomLiveWindow], claimed: Set<UInt32> = []
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var used = Set<Int>()
        func pass(_ accepts: (RoomWindow, RoomLiveWindow) -> Bool) {
            for (index, window) in windows.enumerated() where result[index] == nil {
                guard
                    let match = live.indices.first(where: {
                        !used.contains($0) && live[$0].bundleID == window.bundleID
                            && accepts(window, live[$0])
                    })
                else { continue }
                result[index] = match
                used.insert(match)
            }
        }
        pass { saved, open in saved.windowID != nil && saved.windowID == open.windowID }
        pass { saved, open in !saved.title.isEmpty && saved.title == open.title }
        // 只是看起来相似的标题，绝不能抢走其他房间的窗口。
        pass { saved, open in
            isSimilar(saved.title, open.title) && !isClaimed(open, by: claimed)
        }
        // 标题会随当前标签页变化，所以最后一步是取该 app 的任意窗口，优先取空闲的。
        pass { _, open in !isClaimed(open, by: claimed) }
        pass { _, _ in true }
        return result
    }

    /// 标题共享有意义部分时视为相似：“Report — draft 3” 与 “Report — draft 4”。
    static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let left = folded(lhs)
        let right = folded(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        if left.contains(right) || right.contains(left) { return true }
        let common = zip(left, right).prefix { $0 == $1 }.count
        return common >= min(12, min(left.count, right.count) * 2 / 3)
    }

    private static func isClaimed(_ window: RoomLiveWindow, by claimed: Set<UInt32>) -> Bool {
        window.windowID.map(claimed.contains) ?? false
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
