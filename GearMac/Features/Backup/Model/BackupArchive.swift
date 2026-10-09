// 文件职责：把 `BackupBundle` 目录封装为单个 `.gearmac` 归档文件，并支持将归档重新解包。
// 分层：Model；基于 AppleArchive 做归档读写，需防范恶意归档的路径穿越。
import AppleArchive
import Foundation
import System

/// 把 `BackupBundle` 目录封装成单个 `.gearmac` 文件，并支持将归档重新打开。
enum BackupArchive {
    static let fileExtension = "gearmac"

    /// 归档读写失败的错误类型。
    enum ArchiveError: LocalizedError, Equatable {
        case cannotWrite
        case cannotRead

        var errorDescription: String? {
            switch self {
            case .cannotWrite: return L10n.string(BackupKey.errorCannotWrite, language: .english)
            case .cannotRead: return L10n.string(BackupKey.errorCannotRead, language: .english)
            }
        }

        /// 按指定语言解析错误文案。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .cannotWrite: return L10n.string(BackupKey.errorCannotWrite, language: language)
            case .cannotRead: return L10n.string(BackupKey.errorCannotRead, language: language)
            }
        }
    }

    /// 不写入 `UID`/`GID` 以免还原出外部属主，不写 `IDX` 以免索引悬空；`MTM`（修改时间）供笔记排序使用。
    private static var keySet: ArchiveHeader.FieldKeySet? {
        ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM")
    }

    /// 使用 LZFSE 而非 LZMA：负载主要是已压缩过的 PNG。
    static func seal(directory: URL, into file: URL) throws {
        guard let keySet,
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(file.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else { throw ArchiveError.cannotWrite }
        var sealed = false
        defer {
            if !sealed {
                try? compressor.close()
                try? destination.close()
            }
        }
        try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
            try encoder.writeDirectoryContents(
                archiveFrom: FilePath(directory.path), keySet: keySet)
        }
        // 显式调用而非 `try?`：最后一个数据块在 `close` 时才刷出，写入被截断必须抛出错误。
        try compressor.close()
        try destination.close()
        sealed = true
    }

    /// 将归档文件解包到指定目录，并校验解包结果中不含符号链接。
    static func open(file: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let source = ArchiveByteStream.fileStream(
                path: FilePath(file.path), mode: .readOnly, options: [], permissions: []),
            let decompressor = ArchiveByteStream.decompressionStream(readingFrom: source)
        else { throw ArchiveError.cannotRead }
        defer {
            try? decompressor.close()
            try? source.close()
        }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompressor) else {
            throw ArchiveError.cannotRead
        }
        defer { try? decoder.close() }
        do {
            try ArchiveStream.withExtractStream(
                extractingTo: FilePath(directory.path), selectUsing: containedEntry
            ) { extractor in
                _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
            }
        } catch {
            throw ArchiveError.cannotRead
        }
        guard !containsSymbolicLink(directory) else { throw ArchiveError.cannotRead }
    }

    /// 符号链接条目能通过路径过滤，若滲着它读取会越出解包目录。
    private static func containsSymbolicLink(_ directory: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        guard
            let entries = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys))
        else { return true }
        for case let url as URL in entries
        where (try? url.resourceValues(forKeys: keys))?.isSymbolicLink == true {
            return true
        }
        return false
    }

    /// 跳过任何使用绝对路径或 `..` 的条目，防止恶意归档逃逸出目标目录。
    private static func containedEntry(
        _ message: ArchiveHeader.EntryMessage, _ path: FilePath,
        _ data: ArchiveHeader.EntryFilterData?
    ) -> ArchiveHeader.EntryMessageStatus {
        guard !path.isAbsolute, !path.components.contains(where: { $0.string == ".." }) else {
            return .skip
        }
        return .ok
    }
}
