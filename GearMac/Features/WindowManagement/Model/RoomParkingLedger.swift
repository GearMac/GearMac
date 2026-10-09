// 文件职责：在暂存窗口移动前先把它的归属地写盘，保证任何窗口都不会丢失（事务账本）。
// 分层：Model；保持纯净（MainActor），以原子写 JSON 文件持久化，不 import AppKit/SwiftUI。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// 每个被暂存窗口的归属地，在它移动之前先落盘，所以不会丢失任何一个。
@MainActor
final class RoomParkingLedger {
    struct Entry: Codable, Equatable, Sendable {
        var windowID: UInt32
        var bundleID: String
        var title: String
        var frame: CGRect
    }

    private let fileURL: URL
    private(set) var entries: [UInt32: Entry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var isEmpty: Bool { entries.isEmpty }

    func entry(for windowID: UInt32) -> Entry? {
        entries[windowID]
    }

    /// 当返回位置不在磁盘上时返回 false，此时窗口不得移动。
    func record(_ entry: Entry) -> Bool {
        // 再次暂存一个已暂存窗口，必须保留其最初的返回位置，而非暂存后的 frame。
        if entries[entry.windowID] == nil { entries[entry.windowID] = entry }
        return save()
    }

    func forget(_ windowIDs: some Sequence<UInt32>) {
        let before = entries.count
        for id in windowIDs { entries[id] = nil }
        if entries.count != before { save() }
    }

    func keepOnly(bundleIDs: Set<String>) {
        let kept = entries.filter { bundleIDs.contains($0.value.bundleID) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    // 故意同步：写入必须在它所保护的窗口移动之前落盘。
    @discardableResult
    private func save() -> Bool {
        do {
            let list = entries.values.sorted { $0.windowID < $1.windowID }
            try JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 不可读的账本是它那些窗口归属的唯一记录，因此把它移开保留。
    private static func load(from url: URL) -> [UInt32: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            let name = url.deletingPathExtension().lastPathComponent
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(name).unreadable-\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return [:]
        }
        return Dictionary(list.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
