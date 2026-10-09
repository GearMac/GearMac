// 文件职责：仅凭字符串形态识别 Quicklink 的目标类型（网页、网络共享、deeplink、本地路径），并提供相关判定与展示文本。
// 分层：Model；仅依赖 Foundation，不执行实际的打开操作。
import Foundation

/// 解析后的链接所指向的目标，仅凭字符串形态识别。详见 docs/features/quicklinks.md。
enum QuicklinkDestination: Hashable, Sendable {
    case web(URL)
    /// 可挂载的网络共享：`smb://`、`afp://`、`nfs://`、`ftp://`、`sftp://`、`ftps://`。
    case network(URL)
    /// 其他已注册的 scheme——`spotify://`、`slack://`、`shortcuts://`、`mailto:`。
    case deeplink(URL)
    /// 绝对本地路径，波浪号已展开。
    case path(String)

    /// 该目标类型默认使用的 SF Symbol 图标。
    var defaultSymbol: String {
        switch self {
        case .web: return "globe"
        case .network: return "externaldrive.connected.to.line.below"
        case .deeplink: return "arrow.up.forward.app"
        case .path: return "folder"
        }
    }

    /// 列表行与编辑器预览在名称下方展示的文本。
    var displayText: String {
        switch self {
        case .web(let url), .network(let url), .deeplink(let url): return url.absoluteString
        case .path(let path): return path
        }
    }

    /// 被视为网络共享的 scheme 集合。
    private static let networkSchemes: Set<String> = ["smb", "afp", "nfs", "ftp", "sftp", "ftps"]

    /// 注入 `homeDirectory` 而非直接读取，使测试运行不依赖具体机器。
    static func detect(_ link: String, homeDirectory: String = NSHomeDirectory()) -> Self? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let path = absolutePath(trimmed, homeDirectory: homeDirectory) {
            return .path(path)
        }
        if let scheme = scheme(of: trimmed) {
            guard let url = url(from: trimmed) else { return nil }
            // file: URL 指向本地路径，因此归为路径而非 deeplink。
            if scheme == "file" { return url.isFileURL ? .path(url.path) : nil }
            if scheme == "http" || scheme == "https" { return .web(url) }
            return networkSchemes.contains(scheme) ? .network(url) : .deeplink(url)
        }
        // 裸主机名是人们书写网址的常见方式，因此按 https 处理。
        guard looksLikeBareHost(trimmed), let url = url(from: "https://" + trimmed) else {
            return nil
        }
        return .web(url)
    }

    /// 替换值是否需要百分号编码；在占位符解析之前判定。
    static func usesURLEncoding(_ link: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolutePath(trimmed, homeDirectory: homeDirectory) == nil
    }

    /// 仍存在占位符时为真；校验阶段接受它，由打开路径负责上报。
    static func containsPlaceholder(_ link: String) -> Bool {
        guard let opening = link.firstIndex(of: "{") else { return false }
        return link[link.index(after: opening)...].contains("}")
    }

    /// 将绝对路径或 `~` 开头的路径展开为绝对路径，不匹配时返回 nil。
    private static func absolutePath(_ value: String, homeDirectory: String) -> String? {
        if value.hasPrefix("/") { return value }
        guard value.hasPrefix("~") else { return nil }
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if value == "~" { return home }
        guard value.hasPrefix("~/") else { return nil }
        return home + String(value.dropFirst(1))
    }

    /// 当值以符合 RFC 3986 的 `scheme:` 开头时，返回小写的 scheme。
    private static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[value.startIndex..<colon]
        guard let first = candidate.first, first.isLetter else { return nil }
        guard candidate.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" })
        else { return nil }
        // 排除 Windows 盘符与 host:port，两者都比它们所遮蔽的情况更常见。
        guard candidate.count > 1 else { return nil }
        let remainder = value[value.index(after: colon)...]
        guard !remainder.isEmpty, !remainder.allSatisfy(\.isNumber) else { return nil }
        return candidate.lowercased()
    }

    /// 空格是唯一值得补救的错误；重新编码会破坏已有的 `%xx`。
    private static func url(from value: String) -> URL? {
        URL(string: value) ?? URL(string: value.replacingOccurrences(of: " ", with: "%20"))
    }

    /// 判断字符串是否形如裸主机名（含可选端口）。
    private static func looksLikeBareHost(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace) else { return false }
        var host = value.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return false }
            host = host[host.startIndex..<colon]
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        // 要求顶级标签以字母开头，可排除版本号与小数。
        guard let tld = labels.last, tld.count >= 2, tld.first?.isLetter == true else { return false }
        return tld.allSatisfy(\.isLetter)
    }
}
