// 文件职责：管理 ChatGPT/Codex 的 app-server 连接与订阅态，并使用用户已登录的 Codex 账号。
// 分层：Service；连接与空闲关停由本类统一管理，UI 只读取它对外暴露的状态。
import Foundation
import Observation

/// 拥有 app-server 生命周期，复用用户 Codex 安装中已配置的账号。
@MainActor
@Observable
final class ChatGPTSubscriptionManager {
    /// 足够跨越一轮对话；重启一次约一秒，常驻服务约 20 MB。
    private static let idleShutdown: Duration = .seconds(600)

    private let client: CodexAppServerClient
    let turns: CodexTurnRunner
    /// 转发给 app-server 的启动参数；修改会在它下次启动时生效。
    @ObservationIgnored var launchSettings: () -> InstalledAILaunch {
        get { client.launchSettings }
        set { client.launchSettings = newValue }
    }

    private(set) var phase = ChatGPTSubscription.Phase.idle
    private(set) var access: ChatGPTSubscription.Access?
    private(set) var models: [ChatGPTSubscription.Model] = []
    private(set) var rateLimits: ChatGPTSubscription.RateLimits?
    /// 每次检查时从 client 拷贝而来：client 不被观察，而设置页展示的是这个值。
    private(set) var executable: URL?

    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// 构造时指定支持目录；Codex 的工作区与 app-server 客户端均定位于其下。
    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        let root = supportDirectory.appending(path: "InstalledAI/Codex", directoryHint: .isDirectory)
        client = CodexAppServerClient(
            workspace: root.appending(path: "Workspace", directoryHint: .isDirectory))
        turns = CodexTurnRunner(client: client)
        turns.connect = { [weak self] servers in
            guard let self else { throw CancellationError() }
            try await self.ensureConnected(toolServers: servers)
            return self.models
        }
        turns.onTurnEnded = { [weak self] in self?.turnDidEnd() }
        client.onNotification = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        client.onExit = { [weak self] message in
            self?.forget()
            self?.phase = .failed(message)
        }
    }

    /// 当前登录的账号；尚未确认身份时为 `nil`。
    var account: ChatGPTSubscription.Account? {
        if case .account(let account) = access { account } else { nil }
    }

    /// 是否已完成连接校验（已拿到访问权限且阶段为已连接）。
    var isConnected: Bool { access != nil && phase == .connected }

    /// 触发一次账号检查，并返回其任务；可在已有检查进行时再次调用。
    @discardableResult
    func refresh() -> Task<Void, Never> {
        // 一旦发出请求，检查就已经在进行中，所以 `.idle` 意味着还没人发起过。
        if phase == .idle { phase = .starting }
        return runOperation { [weak self] in await self?.refreshNow() }
    }

    /// 返回当前正在进行的操作任务，供调用方等待或取消；无任务时返回一个空任务。
    func currentRefreshTask() -> Task<Void, Never> { operationTask ?? Task {} }

    /// 释放进程、定时器与状态；回到 `.idle` 后，下次访问会重新检查。
    func stop() {
        operationTask?.cancel()
        // 中断存活的轮次会重新激活空闲关停，所以必须先 forget 再 cancel。
        forget()
        phase = .idle
        idleTask?.cancel()
        client.stop()
    }

    /// 用已不再提供的服务器启动的助手会立即停止，而不是等到空闲十分钟后。
    func dropWithdrawnServers(keeping offered: Set<String>) {
        guard !turns.isActive, client.toolServers.contains(where: { !offered.contains($0.handle) })
        else { return }
        idleTask?.cancel()
        turns.reset()
        client.stop()
    }

    /// 一轮开始前所需的条件：服务已运行且访问权限已确认。
    private func ensureConnected(toolServers: [AIToolServer]) async throws {
        idleTask?.cancel()
        // 服务器清单在 exec 时固定，因此清单变化会重启进程；访问权限则不受进程生命周期影响。
        try await client.start(toolServers: toolServers)
        guard access == nil else { return }
        guard try await verifyAccess() else {
            throw AIProviderError.unavailable("Sign in with `codex login`, then check Codex again.")
        }
    }

    /// 一轮结束后刷新用量限制，并安排空闲关停。
    private func turnDidEnd() {
        Task { [weak self] in await self?.loadRateLimits() }
        scheduleIdleShutdown()
    }

    /// 取消上一次操作并启动新任务，保证同一时刻只跑一个操作。
    @discardableResult
    private func runOperation(
        _ operation: @escaping @MainActor () async -> Void
    )
        -> Task<Void, Never>
    {
        operationTask?.cancel()
        let task = Task { await operation() }
        operationTask = task
        return task
    }

    /// 执行一次实际的账号检查：启动服务、确认访问权限，并安排空闲关停。
    private func refreshNow() async {
        phase = .starting
        do {
            try await client.startForCheck()
            executable = client.executable
            guard try await verifyAccess() else { return }
            scheduleIdleShutdown()
        } catch {
            apply(error)
        }
    }

    /// 检查与轮次得出同一结论，因此两者都不会留下一个已登出的服务在运行。
    private func verifyAccess() async throws -> Bool {
        guard try await restoreAccess() else {
            phase = .signedOut
            client.stop()
            return false
        }
        phase = .connected
        await loadModelsAndLimits()
        return true
    }

    /// 服务只在使用期间常驻；已停止的服务会在需要时重新启动。
    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, let self, !self.turns.isActive else { return }
            self.turns.reset()
            self.client.stop()
        }
    }

    /// 读取可用模型清单并同步刷新用量限制。
    private func loadModelsAndLimits() async {
        do {
            let response = try await client.request(
                method: "model/list", params: ["includeHidden": false, "limit": 100])
            models = (response["data"]?.arrayValue ?? []).compactMap { value in
                guard let raw = value.objectValue, let id = raw["model"]?.stringValue else {
                    return nil
                }
                let rawEfforts = raw["supportedReasoningEfforts"]?.arrayValue ?? []
                let efforts = rawEfforts.compactMap { effort -> ChatGPTSubscription.Effort? in
                    guard let raw = effort.objectValue,
                        let id = raw["reasoningEffort"]?.stringValue
                    else { return nil }
                    return ChatGPTSubscription.Effort(
                        id: id, detail: raw["description"]?.stringValue)
                }
                return ChatGPTSubscription.Model(
                    id: id,
                    name: raw["displayName"]?.stringValue ?? id,
                    efforts: efforts,
                    defaultEffort: raw["defaultReasoningEffort"]?.stringValue,
                    isDefault: raw["isDefault"]?.boolValue ?? false)
            }
        } catch {
            models = []
        }
        await loadRateLimits()
    }

    /// 读取账号的用量限制窗口（主/次），失败时置空。
    private func loadRateLimits() async {
        do {
            let response = try await client.request(method: "account/rateLimits/read")
            guard let limits = response["rateLimits"]?.objectValue else {
                rateLimits = nil
                return
            }
            rateLimits = ChatGPTSubscription.RateLimits(
                primary: usageWindow(limits["primary"]),
                secondary: usageWindow(limits["secondary"]))
        } catch {
            rateLimits = nil
        }
    }

    /// 把单个用量窗口的原始 JSON 转换为模型对象，字段缺失时返回 `nil`。
    private func usageWindow(_ value: JSONValue?) -> ChatGPTSubscription.UsageWindow? {
        guard let raw = value?.objectValue, let used = raw["usedPercent"]?.intValue else {
            return nil
        }
        return ChatGPTSubscription.UsageWindow(
            usedPercent: used,
            durationMinutes: raw["windowDurationMins"]?.intValue,
            resetsAt: raw["resetsAt"]?.intValue.map {
                Date(timeIntervalSince1970: Double($0))
            })
    }

    /// 读取账号信息：区分具体账号、提供方登录与未登录三种情况，未登录时清空状态。
    private func restoreAccess() async throws -> Bool {
        let response = try await client.request(
            method: "account/read", params: ["refreshToken": false])
        if let rawAccount = response["account"]?.objectValue {
            let type = rawAccount["type"]?.stringValue ?? "unknown"
            access = .account(
                ChatGPTSubscription.Account(
                    email: rawAccount["email"]?.stringValue,
                    plan: rawAccount["planType"]?.stringValue ?? type))
        } else if response["requiresOpenaiAuth"]?.boolValue == false {
            access = .provider
        } else {
            forget()
            return false
        }
        return true
    }

    /// 处理服务端通知：账号变更触发重新检查，其余交给轮次运行器。
    private func handleNotification(method: String, params: [String: JSONValue]) {
        switch method {
        case "account/updated":
            runOperation { [weak self] in await self?.refreshNow() }
        default:
            turns.handle(method: method, params: params)
        }
    }

    /// 清空账号、模型、用量限制与轮次状态。
    private func forget() {
        access = nil
        models = []
        rateLimits = nil
        turns.reset()
    }

    /// 把操作错误落到对外阶段：被取消的检查不算结论，其余区分可执行文件缺失与一般失败。
    private func apply(_ error: Error) {
        // 被取消的检查没有结论：取消它的调用方已经设定了它想要的状态。
        guard !Task.isCancelled else { return }
        forget()
        let message = Self.userFacing(error).localizedDescription
        if let clientError = error as? CodexAppServerClient.ClientError,
            case .executableMissing = clientError
        {
            phase = .unavailable(message)
        } else {
            phase = .failed(message)
        }
    }

    /// 把任意错误归一为适合展示的错误：已是 `AIProviderError` 则原样返回。
    static func userFacing(_ error: Error) -> Error {
        if error is AIProviderError { return error }
        let message =
            (error as? LocalizedError)?.errorDescription
            ?? "The Codex connection failed."
        return AIProviderError.responseFailed(message)
    }
}

/// Codex 订阅路由的提供方：把流式请求转发给 `CodexTurnRunner`。
struct CodexInstalledProvider: AIProvider {
    let turns: CodexTurnRunner
    let model: String
    let effort: String?
    /// 仅由聊天设置：快捷操作没有可调用的工具，因此也不会启用服务器。
    var toolServers: AIToolServerSession?

    func stream(_ request: AIRequest) -> AIProviderStream {
        turns.stream(request, model: model, effort: effort, toolServers: toolServers)
    }
}
