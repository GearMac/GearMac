// 文件职责：已固定表情（用户收藏）的有序存储，并持久化为 JSON 文件。
// 分层：Service；状态在主 actor 上维护，与学到的使用频次分开保存，互不覆盖。
import Foundation

/// 有序的用户收藏；与学到的使用频次分开持久化，使两者不会彼此改写。
@MainActor
@Observable
final class PinnedEmojiStore {
    /// 当前目录远小于此值；它只用于限制损坏或被手工编辑过的文件。
    private static let cap = 3_000

    private let fileURL: URL
    private(set) var glyphs: [String]
    private(set) var revision = 0
    /// 写入失败时的回调，由外部决定如何提示用户。
    @ObservationIgnored var onPersistenceFailure: (() -> Void)?

    /// 从磁盘读取已保存的固定列表；无文件或解析失败时以空列表开始。
    init(fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("emoji-pinned.json")) {
        self.fileURL = fileURL
        let decoded =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        glyphs = Self.normalized(decoded)
    }

    /// 切换固定状态：已固定则移除，未固定则追加到末尾，并写入磁盘。
    func toggle(_ glyph: String) {
        guard !glyph.isEmpty else { return }
        if let index = glyphs.firstIndex(of: glyph) {
            glyphs.remove(at: index)
        } else {
            glyphs.append(glyph)
        }
        didChange()
    }

    /// 从备份恢复固定项，保持原顺序并丢弃无效重复项。
    func replace(_ imported: [String]) {
        glyphs = Self.normalized(imported)
        didChange()
    }

    /// 相邻项由调用方指定：目录无法展示的已存固定项不算相邻项。
    func swap(_ glyph: String, with other: String) {
        guard let source = glyphs.firstIndex(of: glyph),
            let destination = glyphs.firstIndex(of: other)
        else { return }
        glyphs.swapAt(source, destination)
        didChange()
    }

    /// 递增版本号并将当前列表原子写入磁盘；失败时调用失败回调。
    private func didChange() {
        revision &+= 1
        do {
            let data = try JSONEncoder().encode(glyphs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            onPersistenceFailure?()
        }
    }

    /// 去除空串与重复项并截断到上限，保持原顺序。
    private static func normalized(_ glyphs: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(min(glyphs.count, cap))
        for glyph in glyphs where !glyph.isEmpty && seen.insert(glyph).inserted {
            result.append(glyph)
            if result.count == cap { break }
        }
        return result
    }
}
