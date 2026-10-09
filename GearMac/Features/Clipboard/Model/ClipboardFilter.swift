// 文件职责：定义剪贴板列表的类型筛选器，并对条目做文本形态判定（纯文本/颜色/链接/邮箱）。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，分类均按文本推导、不落盘。
import Foundation

/// 剪贴板列表的类型筛选器。参见 docs/features/clipboard.md#type-filter。
enum ClipboardFilter: CaseIterable, Sendable {
    case all
    case text
    case image
    case file
    case color
    case link
    case email

    /// 英文标题；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .all: return "All Types"
        case .text: return "Text Only"
        case .image: return "Images Only"
        case .file: return "Files Only"
        case .color: return "Colors Only"
        case .link: return "Links Only"
        case .email: return "Emails Only"
        }
    }

    /// 按界面语言给出的标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .all: .filterAll
            case .text: .filterText
            case .image: .filterImage
            case .file: .filterFile
            case .color: .filterColor
            case .link: .filterLink
            case .email: .filterEmail
            }
        return L10n.string(key, language: language)
    }

    /// 同时作为标题栏按钮的图标，无需展开菜单即可表明当前筛选。
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .text: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "eyedropper"
        case .link: return "link"
        case .email: return "at"
        }
    }

    /// 空列表时显示的文案，使某个筛选隐去全部条目时能自我说明。
    func emptyMessage(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .all: .emptyAll
            case .text: .emptyText
            case .image: .emptyImage
            case .file: .emptyFile
            case .color: .emptyColor
            case .link: .emptyLink
            case .email: .emptyEmail
            }
        return L10n.string(key, language: language)
    }

    /// 各类型互斥：复制的 URL 属于链接，而不是更窄的一类文本。
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        case .text: return item.textForm == .plain
        case .color: return item.textForm == .color
        case .link: return item.textForm == .link
        case .email: return item.textForm == .email
        }
    }

    /// 对 `all` 直接返回原数组，使未筛选的列表无需付出一份拷贝的代价。
    func apply(to items: [ClipboardItem]) -> [ClipboardItem] {
        self == .all ? items : items.filter(matches)
    }
}

extension ClipboardItem {
    /// 文本条目承载的内容形态；`Kind` 说明条目如何存储，这里说明它到底是什么。
    enum TextForm: Sendable {
        case plain
        case color
        case link
        case email
    }

    /// `.color` 条目解析出的颜色值；其他条目一律为 nil。
    var colorValue: ColorValue? {
        guard kind == .text, let text else { return nil }
        return ColorValue.parse(text)
    }

    /// 由推导得出、从不持久化，因此重新分类只是改代码，而不是数据迁移。
    var textForm: TextForm? {
        guard kind == .text, let text else { return nil }
        return Self.classify(text)
    }

    /// 链接或邮箱地址都只是一个短 token，超过这个长度的一律按正文看待。
    private static let detectionLimit = 2048

    /// 无 scheme 的链接必须使用人们真正常复制的顶级域名，否则 `report.pdf` 之流都会被当作链接。
    private static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "co", "ai", "app", "dev", "me", "info", "biz",
        "xyz", "tv", "ly", "gg", "to", "uk", "us", "eu", "de", "fr", "es", "it", "nl", "se", "no",
        "fi", "dk", "ch", "at", "be", "ie", "cz", "ru", "ua", "tr", "cn", "jp", "kr", "hk", "sg",
        "au", "nz", "ca", "mx", "br", "ar", "za"
    ]

    /// 把一段文本归类为 plain/color/link/email，是 `TextForm` 的唯一判定入口。
    private static func classify(_ text: String) -> TextForm {
        // `utf8.count` 是 O(1)；`count` 会在数 MB 的复制内容上逐字素遍历。
        guard text.utf8.count <= detectionLimit else { return .plain }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .plain }
        // 必须先于空白字符拒绝：`rgb(255, 87, 51)` 是带空格书写的单个颜色值。
        if ColorValue.parse(token) != nil { return .color }
        guard !token.contains(where: \.isWhitespace) else { return .plain }
        if let form = schemeForm(of: token) { return form }
        if isAddress(token) { return .email }
        return isBareDomain(token) ? .link : .plain
    }

    /// `mailto:` 视为邮箱地址，其他 `scheme://` 一律视为链接，因此 `vscode://` 无需白名单。
    private static func schemeForm(of token: String) -> TextForm? {
        if token.range(of: "mailto:", options: [.caseInsensitive, .anchored]) != nil {
            return .email
        }
        guard let separator = token.range(of: "://") else { return nil }
        let scheme = token[token.startIndex..<separator.lowerBound]
        guard !scheme.isEmpty,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "+" || $0 == "-" || $0 == ".") })
        else { return nil }
        return .link
    }

    /// `local@domain.tld`：恰好一个 `@`、local 部分非空，且域名部分形如主机名。
    private static func isAddress(_ token: String) -> Bool {
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return topLevelLabel(of: parts[1]) != nil
    }

    /// 这是一个启发式判断，而且是有意为之：最坏情况只是把某一行归入错误的类型。
    private static func isBareDomain(_ token: String) -> Bool {
        let host = token.prefix { !"/?#:".contains($0) }
        if host.range(of: "www.", options: [.caseInsensitive, .anchored]) != nil { return true }
        // 主机名规范上为小写，这正是 `Safari.app` 不会被当作链接的原因。
        guard !host.contains(where: \.isUppercase), let tld = topLevelLabel(of: host) else {
            return false
        }
        return commonTopLevelDomains.contains(String(tld))
    }

    /// 仅当每一段标签都合法时才返回顶级域名，因此能在此前先排除 `@apple.com` 这类输入。
    private static func topLevelLabel(of host: Substring) -> Substring? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isHostLabel), let tld = labels.last,
            tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return tld
    }

    /// 单个主机名标签是否合法：非空且仅由 ASCII 字母、数字与 `-` 组成。
    private static func isHostLabel(_ label: Substring) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
