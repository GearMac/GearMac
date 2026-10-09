// 文件职责：记录并持久化每个 app 实测得到的最小窗口尺寸（拒绝再缩小的下界）。
// 分层：Model；保持纯净（MainActor），用 UserDefaults 存储，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// 每个 app 拒绝再缩小的最小尺寸，通过尝试学到，并跨启动保留。
@MainActor
final class RoomMinimumSizeStore {
    private static let defaultsKey = "roomMinimumWindowSizes"

    private let defaults: UserDefaults
    private(set) var sizes: [String: CGSize]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sizes =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: CGSize].self, from: $0) } ?? [:]
    }

    func size(for bundleID: String) -> CGSize {
        sizes[bundleID] ?? .zero
    }

    /// 当 `size` 抬高了已知下界时返回 true：只有此时才值得重新排布房间。
    @discardableResult
    func learn(_ size: CGSize, for bundleID: String) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        let known = self.size(for: bundleID)
        let raised = CGSize(width: max(known.width, size.width), height: max(known.height, size.height))
        guard raised != known else { return false }
        sizes[bundleID] = raised
        if let data = try? JSONEncoder().encode(sizes) { defaults.set(data, forKey: Self.defaultsKey) }
        return true
    }
}
