// 文件职责：定义 Quicklink 数据模型（用户自建的 URL、搜索、文件、文件夹或 deeplink），并包含其排序、编解码与错误类型。
// 分层：Model；保持纯净，仅依赖 Foundation，不得 import AppKit/SwiftUI。
import Foundation

/// 用户自建的 URL、搜索、文件、文件夹或 deeplink，以启动器命令的形式呈现。
struct Quicklink: Codable, Hashable, Identifiable, Sendable {
    /// 启动器条目标识前缀。
    static let entryIDPrefix = "quicklink:"
    /// 没有图标且无法识别目标类型时使用的兜底图标。
    static let sfSymbol = "link"

    let id: UUID
    var name: String
    /// 原始目标模板；其中可能仍包含 `{argument}` 形式的占位符。
    var link: String
    /// 用于打开目标的应用 bundle id；为 nil 时使用系统默认处理程序。
    var openWithBundleID: String?
    /// SF Symbol 覆盖值；为 nil 时采用识别出的目标类型所建议的图标。
    var iconSymbol: String?
    /// 关闭后条目及其附属数据都保留，但任何地方都不再提供或打开它。
    var isEnabled: Bool
    var showsInRootSearch: Bool
    /// 使用时间戳而非布尔标记，使置顶区块按置顶时间排序。
    var pinnedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, link: String, openWithBundleID: String? = nil,
        iconSymbol: String? = nil, isEnabled: Bool = true, showsInRootSearch: Bool = true,
        pinnedAt: Date? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.openWithBundleID = openWithBundleID
        self.iconSymbol = iconSymbol
        self.isEnabled = isEnabled
        self.showsInRootSearch = showsInRootSearch
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
    }

    /// 是否已置顶。
    var isPinned: Bool { pinnedAt != nil }

    /// 统一的图标规则：优先使用覆盖值，否则采用识别出的目标类型所建议的图标。
    var symbol: String {
        iconSymbol ?? QuicklinkDestination.detect(link)?.defaultSymbol ?? Self.sfSymbol
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// 从条目 ID 反解出 Quicklink 的 UUID，前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// 统一的展示顺序，存储与启动器切片都以此排序。
    static func precedes(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case (let left?, let right?):
            return left != right ? left < right : lhs.id.uuidString < rhs.id.uuidString
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order != .orderedSame
                ? order == .orderedAscending
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // 手写编解码，使新增字段不影响旧导出的导入，且导入保持最小依赖。
    private enum CodingKeys: String, CodingKey {
        case id, name, link, openWithBundleID, iconSymbol, isEnabled, showsInRootSearch, pinnedAt
        case createdAt
    }

    /// 以容错方式解码，缺失字段回退到默认值。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        link = try container.decode(String.self, forKey: .link)
        openWithBundleID = try container.decodeIfPresent(String.self, forKey: .openWithBundleID)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showsInRootSearch =
            try container.decodeIfPresent(Bool.self, forKey: .showsInRootSearch) ?? true
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// 目标应用无法读取选中文本时，`{selection}` 占位符的回退行为。
enum QuicklinkSelectionFallback: String, CaseIterable, Identifiable, Sendable {
    case ask
    case clipboard

    var id: String { rawValue }

    /// 面向用户展示的标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .ask: return L10n.string(QuicklinksKey.fallbackAsk, language: language)
        case .clipboard: return L10n.string(QuicklinksKey.fallbackClipboard, language: language)
        }
    }
}

/// Quicklink 编辑与存储过程中可能出现的错误。
enum QuicklinkError: LocalizedError, Equatable {
    case emptyName
    case emptyLink
    case duplicateName
    case unresolvableLink
    case invalidCharacter
    case storageUnavailable

    /// 面向用户的错误描述。
    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the quicklink."
        case .emptyLink: return "Enter a link to open."
        case .duplicateName: return "A quicklink with this name already exists."
        case .unresolvableLink:
            return "This doesn't look like a URL, file path, or deeplink."
        case .invalidCharacter: return "Names and links cannot contain null characters."
        case .storageUnavailable:
            return "The quicklinks database could not be opened, so changes can't be saved."
        }
    }

    /// 按界面语言解析的面向用户错误描述。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName: return L10n.string(QuicklinksKey.errorEmptyName, language: language)
        case .emptyLink: return L10n.string(QuicklinksKey.errorEmptyLink, language: language)
        case .duplicateName:
            return L10n.string(QuicklinksKey.errorDuplicateName, language: language)
        case .unresolvableLink:
            return L10n.string(QuicklinksKey.errorUnresolvableLink, language: language)
        case .invalidCharacter:
            return L10n.string(QuicklinksKey.errorInvalidCharacter, language: language)
        case .storageUnavailable:
            return L10n.string(QuicklinksKey.errorStorageUnavailable, language: language)
        }
    }
}
