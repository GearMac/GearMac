// 文件职责：定义 Quicklink 导入/导出的 JSON 交换格式，并提供编解码与按名称/目标去重的合并逻辑。
// 分层：Model；仅依赖 Foundation，不包含文件读写等副作用。
import Foundation

/// Quicklinks 导入/导出的 JSON 交换格式。
enum QuicklinkArchive {
    /// 当前归档格式版本号。
    static let version = 1

    /// 归档顶层文档结构：版本号与 Quicklink 列表。
    struct Document: Codable, Sendable {
        var version: Int
        var quicklinks: [Quicklink]
    }

    /// 导入结果，便于汇总时同时说明新增与跳过两部分。
    struct MergeResult: Equatable, Sendable {
        var additions: [Quicklink]
        var skipped: Int
        var imported: Int { additions.count }
    }

    /// 导入归档时可能出现的错误。
    enum ArchiveError: LocalizedError, Equatable {
        case unreadable
        case empty

        /// 面向用户的错误描述。
        var errorDescription: String? {
            switch self {
            case .unreadable: return "This file isn't a GearMac quicklinks export."
            case .empty: return "This file contains no quicklinks."
            }
        }

        /// 按界面语言解析的面向用户错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .unreadable:
                return L10n.string(QuicklinksKey.archiveUnreadable, language: language)
            case .empty:
                return L10n.string(QuicklinksKey.archiveEmpty, language: language)
            }
        }
    }

    /// 将 Quicklink 列表编码为带版本号的 JSON 归档数据。
    static func encode(_ quicklinks: [Quicklink]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(version: version, quicklinks: quicklinks))
    }

    /// 同时接受包裹式文档与裸数组，因此手写的列表也能导入。
    static func decode(_ data: Data) throws(ArchiveError) -> [Quicklink] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded =
            (try? decoder.decode(Document.self, from: data))?.quicklinks
            ?? (try? decoder.decode([Quicklink].self, from: data))
        guard let decoded else { throw .unreadable }
        guard !decoded.isEmpty else { throw .empty }
        return decoded
    }

    /// 按名称或目标地址判重。详见 docs/features/quicklinks.md#import--export。
    static func merge(_ incoming: [Quicklink], into existing: [Quicklink]) -> MergeResult {
        var names = Set(existing.map(normalizedName))
        var links = Set(existing.map(normalizedLink))
        var additions: [Quicklink] = []
        var skipped = 0
        for candidate in incoming {
            let name = normalizedName(candidate)
            let link = normalizedLink(candidate)
            guard !name.isEmpty, !link.isEmpty else {
                skipped += 1
                continue
            }
            guard names.insert(name).inserted, links.insert(link).inserted else {
                skipped += 1
                continue
            }
            // 使用全新标识，避免导入项与既有引用发生冲突。
            additions.append(
                Quicklink(
                    name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    link: candidate.link.trimmingCharacters(in: .whitespacesAndNewlines),
                    openWithBundleID: candidate.openWithBundleID,
                    iconSymbol: candidate.iconSymbol,
                    isEnabled: candidate.isEnabled,
                    showsInRootSearch: candidate.showsInRootSearch,
                    pinnedAt: candidate.pinnedAt,
                    createdAt: candidate.createdAt))
        }
        return MergeResult(additions: additions, skipped: skipped)
    }

    /// 归一化名称：去除首尾空白并忽略大小写，用于判重。
    private static func normalizedName(_ quicklink: Quicklink) -> String {
        quicklink.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: .current)
    }

    /// 归一化目标地址：仅去除首尾空白，用于判重。
    private static func normalizedLink(_ quicklink: Quicklink) -> String {
        quicklink.link.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
