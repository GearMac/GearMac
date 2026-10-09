// 文件职责：调用 macOS Dictionary Services 在本机已启用的辞典中查询词条，优先返回可分区块的结构化 XHTML，否则回退到纯文本。
// 分层：Service；通过 dlsym 动态解析私有符号，不联网、不写磁盘。
import CoreServices
import Darwin

/// 在 Dictionary.app 已启用的辞典中查询词条，完全在本机完成。
enum DictionaryService {
    /// 长词条的解析会阻塞，因此由会话切到主 actor 之外执行。
    nonisolated static func entry(for term: String) -> DictionaryEntry? {
        if let blocks = DictionaryRecords.resolved?.blocks(for: term) {
            return DictionaryEntry(term: term, blocks: blocks)
        }
        return plainText(for: term).map { DictionaryEntry(term: term, plainText: $0) }
    }

    /// 公开 API 的纯文本查询，作为无法读到结构化记录时的回退。
    private nonisolated static func plainText(for term: String) -> String? {
        let range = CFRange(location: 0, length: term.utf16.count)
        guard let text = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue()
        else { return nil }
        let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Dictionary Services 的记录读取接口：Dictionary.app 实际使用的调用，但没有头文件声明。
private struct DictionaryRecords: Sendable {
    private typealias ActiveDictionaries = @convention(c) () -> Unmanaged<CFArray>?
    private typealias CopyRecords =
        @convention(c) (
            DCSDictionary, CFString, UnsafeRawPointer?, UnsafeRawPointer?
        ) -> Unmanaged<CFArray>?
    private typealias CopyData = @convention(c) (CFTypeRef, CFIndex) -> Unmanaged<CFString>?

    /// `DCSRecordCopyData` 的 XHTML 版本；纯文本版本即公开 API 返回的内容。
    private static let xhtml: CFIndex = 0

    private let activeDictionaries: ActiveDictionaries
    private let copyRecords: CopyRecords
    private let copyData: CopyData

    /// 运行时查找符号：若某个 macOS 版本移除了符号，只会丢失排版，不会导致启动失败。
    static let resolved: DictionaryRecords? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let active = dlsym(rtldDefault, "DCSGetActiveDictionaries"),
            let records = dlsym(rtldDefault, "DCSCopyRecordsForSearchString"),
            let data = dlsym(rtldDefault, "DCSRecordCopyData")
        else { return nil }
        return DictionaryRecords(
            activeDictionaries: unsafeBitCast(active, to: ActiveDictionaries.self),
            copyRecords: unsafeBitCast(records, to: CopyRecords.self),
            copyData: unsafeBitCast(data, to: CopyData.self))
    }()

    /// 按 Dictionary.app 自身的顺序，返回第一个认识该词条且已启用的辞典的结构。
    func blocks(for term: String) -> [DictionaryEntry.Block]? {
        guard let dictionaries = activeDictionaries()?.takeUnretainedValue() as? [DCSDictionary]
        else { return nil }
        for dictionary in dictionaries {
            guard
                let records = copyRecords(dictionary, term as CFString, nil, nil)?
                    .takeRetainedValue() as? [CFTypeRef]
            else { continue }
            let blocks = records.flatMap { record in
                (copyData(record, Self.xhtml)?.takeRetainedValue() as String?)
                    .map(DictionaryMarkup.blocks(fromXHTML:)) ?? []
            }
            if !blocks.isEmpty { return blocks }
        }
        return nil
    }
}
