// 文件职责：定义 snippet 的领域模型（`Snippet`、`StoredSnippet`）与文件内容的指纹 `SnippetSourceRevision`。
// 分层：Model；纯值类型且均为 `Sendable`，不依赖文件系统与 UI。
import Foundation

/// 单个 snippet 的领域模型：名称、正文、可选触发关键词与行为开关。
struct Snippet: Sendable, Hashable {
    var name: String
    var text: String
    var keyword: String?
    var isEnabled: Bool
    var showsConfirmation: Bool

    init(
        name: String,
        text: String,
        keyword: String? = nil,
        isEnabled: Bool = true,
        showsConfirmation: Bool = false
    ) {
        self.name = name
        self.text = text
        self.keyword = keyword
        self.isEnabled = isEnabled
        self.showsConfirmation = showsConfirmation
    }
}

/// snippet 文件字节的指纹，用于在保存或删除前检测外部修改。
struct SnippetSourceRevision: Sendable, Hashable {
    private let value: String

    /// 由文件内容计算 FNV-1a 哈希，得到「字节数:十六进制哈希」形式的指纹。
    init(content: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        var byteCount = 0
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
            byteCount += 1
        }
        value = "\(byteCount):\(String(hash, radix: 16))"
    }
}

/// 已落盘的 snippet：文件位置、内容，以及读取时的源文件指纹。
struct StoredSnippet: Identifiable, Sendable, Hashable {
    static let entryIDPrefix = "snippet:"

    let fileURL: URL
    var snippet: Snippet
    let sourceRevision: SnippetSourceRevision

    var id: String { fileURL.standardizedFileURL.path }

    var entryID: String { Self.entryIDPrefix + id }

    /// 从 entry ID 还原文件路径；前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> ID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }
}
