// 文件职责：CLI 路由自带客户端所运行的 MCP 服务器模型，以及这类路由向 GearMac 申请工具授权、读取服务器的会话协议。
// 分层：Model；只定义数据与回调，不直接做 I/O，不得 import AppKit/SwiftUI。
import Foundation

/// 由 CLI 路由自带客户端运行的服务器；对应于 GearMac 自己那个工具循环所使用的 `AITool`。
struct AIToolServer: Equatable, Sendable {
    enum Transport: Equatable, Sendable {
        /// 本地进程传输。参数通过子进程环境变量传递，绝不放进其 argv。
        case command(path: String, arguments: [String], environment: [String: String])
        /// 远程端点传输。值为空时不发送该 header，与 GearMac 自身的传输层行为一致。
        case url(String, headerName: String, headerValue: String)
    }

    /// 工具名路由回该服务器的句柄，也是 CLI 认识该服务器所用的名称。
    let handle: String
    let title: String
    let transport: Transport
}

/// 路由自带客户端正在申请授权的一次调用，用 GearMac 的寻址方式命名。
struct AIToolServerCall: Equatable, Sendable {
    let handle: String
    let tool: String
}

/// 由自带客户端运行工具循环的路由，如何访问 GearMac 的服务器及其读取器。
struct AIToolServerSession: Sendable {
    let servers: @Sendable () async -> [AIToolServer]
    let consent: @Sendable (AIToolServerCall) async -> Bool
    /// 与 BYOK 循环一致的上限，`nil` 表示不限制；施加于 CLI 自己的循环，使回复以相同方式终止。
    let rounds: Int?

    /// 构造会话，并把外部传入的授权回调包进串行队列，使同一个对话框不会并发出现。
    init(
        rounds: Int?,
        servers: @escaping @Sendable () async -> [AIToolServer],
        consent: @escaping @Sendable (AIToolServerCall) async -> Bool
    ) {
        self.rounds = rounds
        self.servers = servers
        let queue = ConsentQueue()
        self.consent = { call in await queue.ask { await consent(call) } }
    }

    /// 一次只问一个问题：第二个询问会遇到对话框忙碌，且必须能看到第一个询问的授权结果。
    @MainActor
    private final class ConsentQueue {
        private var isAsking = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        /// 串行化提问：若已有提问在进行则排队等待，否则直接占用；返回问题的答案。
        func ask(_ question: @Sendable () async -> Bool) async -> Bool {
            if isAsking {
                await withCheckedContinuation { waiting.append($0) }
            } else {
                isAsking = true
            }
            defer {
                if waiting.isEmpty { isAsking = false } else { waiting.removeFirst().resume() }
            }
            guard !Task.isCancelled else { return false }
            return await question()
        }
    }
}

/// 记录行中可展示 CLI 所报告调用的哪些内容；这些名称来自外部，不可信任。
enum AIToolServerRow {
    /// 记录行只有一行：返回上千字节名称的服务器不能把行撑开。
    static let maxNameLength = 64

    /// 超长名称截断到 `maxNameLength` 并补省略号。
    static func label(_ name: String) -> String {
        name.count <= maxNameLength ? name : String(name.prefix(maxNameLength)) + "\u{2026}"
    }

    /// 在已知服务器中按 handle 找到标题，找不到则退回 handle 本身。
    static func title(of server: String, in servers: [AIToolServer]) -> String {
        label(servers.first { $0.handle == server }?.title ?? server)
    }
}
