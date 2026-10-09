// 文件职责：记录每个来自商店的扩展对应的商店版本（commit SHA），用于判断安装是否落后于商店。
// 分层：Service；@MainActor 隔离，数据持久化到单个 JSON 文件，文件夹或 GitHub 安装的扩展不记录条目。
import Foundation

/// 记录每个商店来源扩展的商店版本；文件夹或 GitHub 安装的扩展没有条目。
@MainActor
final class ExtensionVersionStore {
    private struct Entry: Codable, Equatable {
        /// 在下次检查采纳商店版本之前为 nil，导入流程正是从这里开始。
        var commitSHA: String?
    }

    private let fileURL: URL
    private var entries: [String: Entry]

    /// 从给定文件加载已有记录；文件不存在或解码失败时从空表开始。
    init(fileURL: URL) {
        self.fileURL = fileURL
        entries =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// 当前受版本跟踪的扩展名集合。
    var tracked: Set<String> { Set(entries.keys) }

    /// 记录（或更新）某个扩展当前的 commit SHA。
    func record(_ commitSHA: String?, for name: String) {
        update { $0[name] = Entry(commitSHA: commitSHA) }
    }

    /// 不再跟踪某个扩展的版本。
    func forget(_ name: String) {
        update { $0[name] = nil }
    }

    /// 哪些已安装项落后于商店。版本未知的会采纳商店版本（与 Raycast 保持一致）。
    func reconcile(with latest: [ExtensionListing]) -> [ExtensionListing] {
        var behind: [ExtensionListing] = []
        update { entries in
            for listing in latest {
                guard let entry = entries[listing.name], let latestSHA = listing.commitSHA else {
                    continue
                }
                if let installedSHA = entry.commitSHA {
                    if installedSHA != latestSHA { behind.append(listing) }
                } else {
                    entries[listing.name] = Entry(commitSHA: latestSHA)
                }
            }
        }
        return behind
    }

    /// 每次变更只写一次盘，且无实际变化时不写。
    private func update(_ body: (inout [String: Entry]) -> Void) {
        var next = entries
        body(&next)
        guard next != entries else { return }
        entries = next
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
