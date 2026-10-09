// 文件职责：从事件文本中识别会议加入链接及其所属服务商，并构造桌面 App 跳转 URL、带账号的 Web URL。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，URL 识别为手写扫描。
import Foundation

/// 会议的加入链接及其背后的服务，从事件自身的文本中读出。
struct MeetingLink: Hashable, Sendable {
    let provider: Provider
    let url: URL
    /// 提供该链接的日历所属账号，供需要预选身份的提供商使用。
    let account: String?

    /// 桌面 App 自身的 URL（在不需猜测的情况下可构造）；为 nil 表示应打开网页。
    var appURL: URL? { provider.appURL(for: url) }

    /// 原样写出的链接，在提供商支持账号时会带上账号。
    var webURL: URL { provider.accountURL(for: url, account: account) ?? url }

    /// 按优先级检查各字段；找到任意已知提供商就优先于先发现的裸链接。
    static func detect(fields: [String?], account: String? = nil) -> MeetingLink? {
        var fallback: MeetingLink?
        for field in fields.compactMap({ $0 }) {
            for url in webURLs(in: field) {
                guard let provider = classify(url) else { continue }
                let link = MeetingLink(provider: provider, url: url, account: account)
                if provider != .generic { return link }
                if fallback == nil { fallback = link }
            }
        }
        return fallback
    }

    /// 在单段文本中识别会议链接。
    static func detect(in text: String) -> MeetingLink? {
        detect(fields: [text])
    }

    /// 仅当参与者是当前用户时返回其邮箱地址，否则返回 nil。
    static func accountAddress(of participantURL: URL, isCurrentUser: Bool) -> String? {
        isCurrentUser ? address(of: participantURL) : nil
    }

    /// EventKit 的 `mailto:` 参与者 URL 是不透明的：`path` 取不到任何东西，只能从字符串入手。
    static func address(of participantURL: URL) -> String? {
        let string = participantURL.absoluteString
        guard string.lowercased().hasPrefix("mailto:") else { return nil }
        let raw = string.dropFirst("mailto:".count)
        let address = raw.removingPercentEncoding ?? String(raw)
        guard address.contains("@") else { return nil }
        return address
    }

    /// 已知主机的链接若不符合其路径规则就丢弃，绝不会降级为 `.generic`。
    private static func classify(_ url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host()?.lowercased()
        else { return nil }
        guard let provider = Provider(host: host) else { return .generic }
        return provider.admits(path: url.path()) ? provider : nil
    }

    private static let terminators: Set<Character> = [
        " ", "\t", "\n", "\r", "\"", "'", "<", ">", "«", "»", "\u{00A0}"
    ]
    private static let trailingNoise: Set<Character> = [".", ",", ";", ":", ")", "]", "}", "!", "?"]

    /// 手写实现：`NSDataDetector` 不是 `Sendable` 且开销高于本次扫描。
    private static func webURLs(in text: String) -> [URL] {
        var found: [URL] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
            let start = text.range(
                of: "http", options: .caseInsensitive, range: cursor..<text.endIndex)?.lowerBound
        {
            let end = text[start...].firstIndex(where: terminators.contains) ?? text.endIndex
            var candidate = text[start..<end]
            while let last = candidate.last, trailingNoise.contains(last) {
                candidate = candidate.dropLast()
            }
            let lowered = candidate.lowercased()
            if lowered.hasPrefix("http://") || lowered.hasPrefix("https://"),
                let url = URL(string: String(candidate))
            {
                found.append(url)
            }
            cursor = end > start ? end : text.index(after: start)
        }
        return found
    }
}

extension MeetingLink {
    /// 已识别的会议服务提供商；`.generic` 表示无法识别的其他 join 链接。
    enum Provider: String, CaseIterable, Sendable {
        case zoom
        case googleMeet
        case teams
        case webex
        case jitsi
        case whereby
        case chime
        case gotoMeeting
        case blueJeans
        case skype
        /// 事件携带的任意其他 http(s) 链接 —— 可加入，但无法识别具体提供商。
        case generic

        /// 提供商的展示名称（英文）；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
        var title: String {
            switch self {
            case .zoom: return "Zoom"
            case .googleMeet: return "Google Meet"
            case .teams: return "Microsoft Teams"
            case .webex: return "Webex"
            case .jitsi: return "Jitsi"
            case .whereby: return "Whereby"
            case .chime: return "Amazon Chime"
            case .gotoMeeting: return "GoTo Meeting"
            case .blueJeans: return "BlueJeans"
            case .skype: return "Skype"
            case .generic: return "Meeting Link"
            }
        }

        /// 按界面语言给出的提供商名称；品牌名保持原样，仅通用链接需要翻译。
        func localizedTitle(_ language: AppLanguage) -> String {
            self == .generic ? L10n.string(CalendarKey.providerGeneric, language: language) : title
        }

        /// 未随 App 发布会标素材，因此图标只表达类别而非品牌。
        var sfSymbol: String { self == .generic ? "link" : "video.fill" }

        /// 主机后缀，按全等或子域匹配。各提供商的后缀集合构造上互不相交。
        private static let hostSuffixes: [Provider: [String]] = [
            .zoom: ["zoom.us", "zoom.com", "zoomgov.com"],
            .googleMeet: ["meet.google.com"],
            .teams: ["teams.microsoft.com", "teams.microsoft.us", "teams.live.com"],
            .webex: ["webex.com", "webex.com.cn"],
            .jitsi: ["meet.jit.si", "8x8.vc"],
            .whereby: ["whereby.com"],
            .chime: ["chime.aws"],
            .gotoMeeting: ["gotomeeting.com", "gotomeet.me", "app.goto.com"],
            .blueJeans: ["bluejeans.com"],
            .skype: ["join.skype.com"]
        ]

        /// 根据主机名匹配提供商，无匹配时返回 nil。
        init?(host: String) {
            let match = Self.hostSuffixes.first { _, suffixes in
                suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
            }
            guard let match else { return nil }
            self = match.key
        }

        /// 判断路径形状是会议页面，而不是下载页或拨号辅助页。
        func admits(path: String) -> Bool {
            let segments = path.split(separator: "/").map { $0.lowercased() }
            switch self {
            case .zoom:
                return segments.contains { ["j", "w", "s", "my"].contains($0) }
            case .googleMeet:
                return segments.count == 1 && segments[0] != "tel"
            case .teams:
                return segments.contains("meetup-join") || segments.contains("meet")
            case .webex, .jitsi, .whereby, .chime, .gotoMeeting, .blueJeans, .skype, .generic:
                return !segments.isEmpty
            }
        }

        private static let accountQuery = "authuser"
        /// Meet 自身的链接保留可读的 `@`；`+` 不能保留，因为服务端可能将其读作空格。
        private static let accountAllowed = CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(charactersIn: "+&="))

        /// 只有 Google Meet 接受账号；`authuser` 用于在已登录身份之间选择。
        func accountURL(for url: URL, account: String?) -> URL? {
            guard self == .googleMeet, let account,
                let encoded = account.addingPercentEncoding(withAllowedCharacters: Self.accountAllowed),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            let items = components.percentEncodedQueryItems ?? []
            // 链接自身已指定账号时视为有意为之，优先于日历携带的账号。
            guard !items.contains(where: { $0.name == Self.accountQuery }) else { return nil }
            components.percentEncodedQueryItems =
                items + [URLQueryItem(name: Self.accountQuery, value: encoded)]
            return components.url
        }

        /// 仅处理 Apple 处理器能无歧义重写的两种情况；其余一律打开网页。
        func appURL(for url: URL) -> URL? {
            switch self {
            case .zoom: return zoomAppURL(for: url)
            case .teams: return teamsAppURL(for: url)
            default: return nil
            }
        }

        /// 把 Zoom 的 Web 链接重写为 `zoommtg://` 协议的 App 跳转链接。
        private func zoomAppURL(for url: URL) -> URL? {
            let segments = url.path().split(separator: "/")
            guard let marker = segments.firstIndex(where: { ["j", "w", "s"].contains($0.lowercased()) }),
                let conference = segments.dropFirst(marker + 1).first
            else { return nil }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = "zoom.us"
            components.path = "/join"
            var query = [URLQueryItem(name: "confno", value: String(conference))]
            if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pwd" })?.value
            {
                query.append(URLQueryItem(name: "pwd", value: password))
            }
            components.queryItems = query
            return components.url
        }

        /// 把 Teams 的 Web 链接重写为 `msteams:` 协议的 App 跳转链接。
        private func teamsAppURL(for url: URL) -> URL? {
            guard url.host()?.lowercased().hasSuffix("teams.microsoft.com") == true else { return nil }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
            return URL(string: "msteams:" + url.path() + (query.map { "?" + $0 } ?? ""))
        }
    }
}
