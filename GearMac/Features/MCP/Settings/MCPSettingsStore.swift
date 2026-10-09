// 文件职责：在 UserDefaults 中持久化 MCP 服务器列表，并在写入前规范化名称、slug 与信任级别。
// 分层：Settings（Observable）；@MainActor，servers 变更时自动持久化。
import Foundation
import Observation

/// MCP 服务器配置的存储层，负责读写与 slug 唯一性维护。
@MainActor
@Observable
final class MCPSettingsStore {
    private let defaults: UserDefaults

    private(set) var servers: [MCPServer] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        servers = Self.decode(defaults.data(forKey: AppSettingsKey.mcpServers.rawValue))
    }

    /// 按 id 查找已配置的服务器。
    func server(id: UUID) -> MCPServer? {
        servers.first { $0.id == id }
    }

    /// 按 slug 查找已配置的服务器。
    func server(slug: String) -> MCPServer? {
        servers.first { $0.slug == slug }
    }

    /// 已启用的服务器列表。
    var enabledServers: [MCPServer] {
        servers.filter(\.isEnabled)
    }

    /// 写入或更新一个服务器（同名时按 id 覆盖）。
    func save(_ server: MCPServer) {
        let server = normalized(server)
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    /// 删除指定服务器。
    func remove(id: UUID) {
        servers.removeAll { $0.id == id }
    }

    /// 更新指定服务器的信任级别。
    func setTrust(_ trust: MCPTrust, for id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].trust = trust
    }

    /// slug 是推导出来的而非手写，因此 `@handle` 既不会重名也不会指向不存在的服务器。
    private func normalized(_ server: MCPServer) -> MCPServer {
        var server = server
        server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(servers.filter { $0.id != server.id }.map(\.slug))
        let derived = MCPSlug.normalize(server.name.isEmpty ? server.slug : server.name)
        if server.slug != derived || taken.contains(server.slug) {
            server.slug = MCPSlug.make(from: derived, existing: taken)
        }
        return server
    }

    /// 将当前 servers 编码写入 UserDefaults。
    private func persist() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: AppSettingsKey.mcpServers.rawValue)
    }

    /// 从 UserDefaults 数据解码服务器列表，失败时返回空数组。
    private static func decode(_ data: Data?) -> [MCPServer] {
        guard let data, let servers = try? JSONDecoder().decode([MCPServer].self, from: data)
        else { return [] }
        return servers
    }
}
