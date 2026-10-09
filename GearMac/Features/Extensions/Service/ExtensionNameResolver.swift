// 文件职责：为 `dgram` shim 提供主机名解析，把域名解析为 IPv4 地址列表。
// 分层：Service；不依赖 UI，仅使用系统解析器（对 `.local` 由 Bonjour 应答）。
import Foundation

/// `dgram` shim 使用的主机名查询：对 `.local` 由系统解析器经 Bonjour 应答。
enum ExtensionNameResolver {
    /// 异步解析主机名；名称为空时直接返回空列表。
    static func resolve(_ name: RenderValue?) async -> [String] {
        let host = name?.stringValue ?? ""
        guard !host.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { addresses(of: host) }.value
    }

    /// 同步阻塞解析，因此调用方需置于 detached task 中。
    private static func addresses(of host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let first = head else { return [] }
        defer { freeaddrinfo(first) }

        var found: [String] = []
        var entry: UnsafeMutablePointer<addrinfo>? = first
        while let current = entry {
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                current.pointee.ai_addr, current.pointee.ai_addrlen, &text, socklen_t(text.count),
                nil, 0, NI_NUMERICHOST) == 0
            {
                let digits = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                let address = String(decoding: digits, as: UTF8.self)
                if !found.contains(address) { found.append(address) }
            }
            entry = current.pointee.ai_next
        }
        return found
    }
}
