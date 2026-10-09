// 文件职责：统一管理所有运行中 MCP 服务器的连接集合，负责按设置启用/停用与空闲回收。
// 分层：Service（Observable）；@MainActor 维护 connections 字典，具体调用是否允许由 Coordinator 决定。
import Foundation
import Observation

/// 所有运行中服务器的生命周期管理者；某次调用是否可执行由 coordinator 决定。
@MainActor
@Observable
final class MCPServerManager {
    private(set) var connections: [UUID: MCPServerConnection] = [:]

    @ObservationIgnored private let oauth: MCPOAuthManager?
    @ObservationIgnored private let secrets: MCPSecretStore
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// 服务器可以跨多次召唤存活，但不应该活过一下午；常驻辅助进程占用的就是内存预算。
    private static let idleTimeout: Duration = .seconds(600)

    init(secrets: MCPSecretStore = MCPSecretStore(), oauth: MCPOAuthManager? = nil) {
        self.oauth = oauth
        self.secrets = secrets
    }

    /// 查询指定服务器的当前连接状态，未知服务器视为已停止。
    func status(of id: UUID) -> MCPServerStatus {
        connections[id]?.status ?? .stopped
    }

    var tools: [MCPTool] {
        connections.values.filter { $0.status.isReady }.flatMap(\.tools)
    }

    /// 使实际运行中的连接集与设置中保存的一致，只启动缺少的部分。
    func reconcile(_ servers: [MCPServer]) {
        let wanted = Dictionary(servers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, connection) in connections where wanted[id] != connection.server {
            connection.stop()
            connections[id] = nil
        }
        for server in servers {
            guard let existing = connections[server.id] else {
                let connection = MCPServerConnection(
                    server: server, secrets: secrets.secrets(for: server.id), oauth: oauth)
                connections[server.id] = connection
                Task { await connection.start() }
                continue
            }
            // 空闲状态包含失败，因此进入聊天会重试一次丢失网络的服务器。
            if existing.isIdle { Task { await existing.start() } }
        }
        armIdleTimer()
    }

    /// 按 slug 查找已建立的连接。
    func connection(slug: String) -> MCPServerConnection? {
        connections.values.first { $0.server.slug == slug }
    }

    /// 断开并移除指定服务器的连接。
    func disconnect(_ id: UUID) {
        connections.removeValue(forKey: id)?.stop()
    }

    /// 停止全部连接并取消空闲计时。
    func stop() {
        idleTask?.cancel()
        idleTask = nil
        for connection in connections.values { connection.stop() }
        connections = [:]
    }

    /// 每次使用都重新计时，因此倒计时衡量的是空闲时长而非运行时长。
    func markUsed() {
        armIdleTimer()
    }

    /// 启动或重置空闲计时器；没有连接时直接清除。
    private func armIdleTimer() {
        idleTask?.cancel()
        guard !connections.isEmpty else {
            idleTask = nil
            return
        }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
}
