// 文件职责：管理单个命令运行的 JavaScriptCore 上下文，提供 JS→Swift 宿主对象与命令生命周期（boot/start/dispatch/stop）。
// 分层：Service；内部状态只在私有串行队列 queue 上访问，跨边界的只有 Sendable 值（JSON 字符串/RenderValue）。
import Foundation
import JavaScriptCore

/// JS→Swift 的接缝。回答统一用 JSON，因此不会有非 `Sendable` 值回传到 JS 队列。
@MainActor
protocol ExtensionHostAPI: AnyObject, Sendable {
    func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String
    /// 上下文已销毁；释放为它打开的资源。
    func sessionEnded()
}

/// 运行中命令的 UI 结果或失败上报入口。所有回调都在主 actor 上送达。
@MainActor
protocol ExtensionRuntimeDelegate: AnyObject {
    func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree)
    func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String)
    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth: Int)
    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void)
    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String)
}

/// 单个命令唯一个 `JSContext` 的宿主；所有对上下文的触碰都在 `queue` 上，跨线程的只有值。
final class ExtensionRuntime: @unchecked Sendable {
    private let queue: DispatchQueue
    private var context: JSContext?
    private var timers: [String: DispatchSourceTimer] = [:]
    private var hostTasks: [String: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let nodeShims = ExtensionNodeShims()

    /// 启动时设置一次；只在 JS 队列上读取，因此写入发生在运行时启动之前。
    private nonisolated(unsafe) weak var delegate: ExtensionRuntimeDelegate?
    private let hostAPI: ExtensionHostAPI
    private let runtimeOverride: URL?

    /// `runtimeURL` 可覆盖内置运行时；仅测试脚手架会传入。
    init(hostAPI: ExtensionHostAPI, runtimeURL: URL? = nil, priority: DispatchQoS = .userInitiated) {
        queue = DispatchQueue(
            label: "com.gearmac.extensions.js", qos: priority, autoreleaseFrequency: .workItem)
        self.hostAPI = hostAPI
        self.runtimeOverride = runtimeURL
    }

    /// 在主 actor 上设置回调委托。
    @MainActor
    func setDelegate(_ delegate: ExtensionRuntimeDelegate) {
        self.delegate = delegate
    }

    // MARK: - Lifecycle

    /// 运行时启动阶段的错误。
    enum RuntimeError: LocalizedError {
        case runtimeResourceMissing
        case bootFailed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeResourceMissing:
                return "RaycastRuntime.generated.js is missing from the app bundle."
            case .bootFailed(let message):
                return "The extension runtime failed to start: \(message)"
            }
        }
    }

    /// 幂等操作，使任一命令都能懒加载地确保引擎已启动。
    func boot(config: ExtensionBootConfig) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.bootOnQueue(config: config)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func bootOnQueue(config: ExtensionBootConfig) throws {
        guard context == nil else { return }
        guard
            let url = runtimeOverride
                ?? Bundle.main.url(forResource: "RaycastRuntime.generated", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { throw RuntimeError.runtimeResourceMissing }

        guard let context = JSContext() else { throw RuntimeError.bootFailed("no JSContext") }

        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = ExtensionRuntime.describe(exception)
        }
        installHost(in: context)
        context.evaluateScript(source, withSourceURL: url)
        if let thrown { throw RuntimeError.bootFailed(thrown) }
        // 只有在确认可用后才保存：半成品上下文会让后续每次 boot 都变成空操作。
        self.context = context

        // 从这里开始，异常就是命令自身的 bug：上报后继续运行。
        context.exceptionHandler = { [weak self] _, exception in
            self?.report(level: "error", message: ExtensionRuntime.describe(exception))
        }

        let payload = config.jsonString()
        _ = context.objectForKeyedSubscript("__gearmac")?
            .invokeMethod("boot", withArguments: [payload])
    }

    /// 加载并挂载单个命令。`code` 是它预构建的 CommonJS 包。
    func start(
        session: String, code: String, file: URL, mode: ExtensionCommandMode,
        context launchContext: ExtensionLaunchContext
    ) async {
        let payload = launchContext.jsonString()
        await onQueue { context in
            let compiled = context.objectForKeyedSubscript("__gearmac")
            _ = compiled?.invokeMethod(
                "start",
                withArguments: [
                    session, code, file.path, file.deletingLastPathComponent().path,
                    mode.rawValue, payload
                ])
        }
    }

    /// 预先编码：`[Any]` 不是 Sendable，因此只有 JSON 字符串会被传过队列。
    func dispatch(session: String, handler: String, payload: String, completesSession: Bool = false) async {
        await onQueue { context in
            _ = context.objectForKeyedSubscript("__gearmac")?
                .invokeMethod("dispatch", withArguments: [session, handler, payload, completesSession])
        }
    }

    /// 在已压栈页面内向上退出（如按下返回箭头）；返回是否有页面被弹出。
    func popNavigation(session: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let context = self.context else { return continuation.resume(returning: false) }
                let result = context.objectForKeyedSubscript("__gearmac")?
                    .invokeMethod("popNavigation", withArguments: [session])
                continuation.resume(returning: result?.toString() == "1")
            }
        }
    }

    /// 触发一个 toast 操作回调。
    func runToastAction(token: String) async {
        await onQueue { context in
            _ = context.objectForKeyedSubscript("__gearmac")?
                .invokeMethod("runToastAction", withArguments: [token])
        }
    }

    /// 停止会话对应的命令，并关闭该会话打开的文件句柄。
    func stop(session: String) async {
        await onQueue { context in
            _ = context.objectForKeyedSubscript("__gearmac")?
                .invokeMethod("stop", withArguments: [session])
        }
        queue.async { self.nodeShims.closeFiles() }
    }

    /// 在 JS 队列上执行 body；上下文已销毁时直接跳过。
    private func onQueue(_ body: @escaping @Sendable (JSContext) -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let context = self.context { body(context) }
                continuation.resume()
            }
        }
    }

    // MARK: - Host object

    /// 安装 `__gearmacHost`（JS→Swift 接缝）与 `__gearmacCompile`。
    private func installHost(in context: JSContext) {
        let host = JSValue(newObjectIn: context)

        let log: @convention(block) (String, String) -> Void = { [weak self] level, message in
            self?.report(level: level, message: message)
        }
        let render: @convention(block) (String, String) -> Void = { [weak self] session, json in
            self?.deliverRender(session: session, json: json)
        }
        let failed: @convention(block) (String, String) -> Void = { [weak self] session, message in
            guard let self else { return }
            let delegate = self.delegate
            Task { @MainActor in delegate?.runtime(self, session: session, didFail: message) }
        }
        let navigation: @convention(block) (String, String) -> Void = { [weak self] session, depth in
            guard let self else { return }
            let delegate = self.delegate
            let value = Int(depth) ?? 1
            Task { @MainActor in delegate?.runtime(self, session: session, navigationDepth: value) }
        }
        let finished: @convention(block) (String) -> Void = { [weak self] session in
            guard let self else { return }
            let delegate = self.delegate
            Task { @MainActor in delegate?.runtime(self, session: session, didFinish: ()) }
        }
        let fieldCommand: @convention(block) (String, String) -> Void = { _, _ in
            // 字段聚焦请求尚无原生目标；调色板会聚焦第一个字段。
        }
        let invoke: @convention(block) (String, String, String, String) -> Void = {
            [weak self] callId, api, method, argsJSON in
            self?.invokeAsync(callId: callId, api: api, method: method, argsJSON: argsJSON)
        }
        let invokeSync: @convention(block) (String, String, String) -> String = {
            [weak self] api, method, argsJSON in
            guard let self else { return #"{"ok":false,"error":"runtime gone"}"# }
            return self.nodeShims.perform(api: api, method: method, argsJSON: argsJSON)
        }
        let startTimer: @convention(block) (String, Double, Bool) -> Void = {
            [weak self] id, milliseconds, repeats in
            self?.startTimer(id: id, milliseconds: milliseconds, repeats: repeats)
        }
        let clearTimer: @convention(block) (String) -> Void = { [weak self] id in
            self?.clearTimer(id: id)
        }

        host?.setObject(log, forKeyedSubscript: "log" as NSString)
        host?.setObject(render, forKeyedSubscript: "render" as NSString)
        host?.setObject(failed, forKeyedSubscript: "failed" as NSString)
        host?.setObject(navigation, forKeyedSubscript: "navigationDepthChanged" as NSString)
        host?.setObject(finished, forKeyedSubscript: "finished" as NSString)
        host?.setObject(fieldCommand, forKeyedSubscript: "fieldCommand" as NSString)
        host?.setObject(invoke, forKeyedSubscript: "invoke" as NSString)
        host?.setObject(invokeSync, forKeyedSubscript: "invokeSync" as NSString)
        host?.setObject(startTimer, forKeyedSubscript: "startTimer" as NSString)
        host?.setObject(clearTimer, forKeyedSubscript: "clearTimer" as NSString)
        context.setObject(host, forKeyedSubscript: "__gearmacHost" as NSString)

        // 全局作用域正是关键：扩展代码不应看到运行时的局部变量。
        let compile: @convention(block) (String, String) -> JSValue? = { [weak self] code, filename in
            guard let context = self?.context else { return nil }
            let wrapped = "(function (exports, require, module, __filename, __dirname) {\n\(code)\n})"
            return context.evaluateScript(wrapped, withSourceURL: URL(fileURLWithPath: filename))
        }
        context.setObject(compile, forKeyedSubscript: "__gearmacCompile" as NSString)
    }

    // MARK: - Host call plumbing

    /// 异步调用宿主 API：先在 JS 队列解码参数，避免非 Sendable 值进入主 actor。
    private func invokeAsync(callId: String, api: String, method: String, argsJSON: String) {
        // 在这里解码为 `RenderValue`，保证只有 `Sendable` 值到达主 actor。
        let arguments = RenderValue.arguments(from: argsJSON)
        let hostAPI = self.hostAPI
        let generation = self.generation
        hostTasks[callId] = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let json = try await hostAPI.perform(
                    api: api, method: method, arguments: arguments)
                await self?.settle(callId: callId, generation: generation, ok: true, payload: json)
            } catch {
                await self?.settle(
                    callId: callId, generation: generation, ok: false,
                    payload: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 将宿主调用结果回传给 JS；generation 不匹配（运行时已重启）时丢弃结果。
    private func settle(callId: String, generation: UUID, ok: Bool, payload: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                defer { continuation.resume() }
                guard generation == self.generation else { return }
                self.hostTasks[callId] = nil
                _ = self.context?.objectForKeyedSubscript("__gearmac")?
                    .invokeMethod("settle", withArguments: [callId, ok, payload])
                if self.hostTasks.isEmpty { self.resumeIdleWaiters() }
            }
        }
    }

    /// 等待所有未完成的宿主调用结束（队列空闲）。
    func drainHostCalls() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.hostTasks.isEmpty {
                    continuation.resume()
                } else {
                    self.idleWaiters.append(continuation)
                }
            }
        }
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// 在主 actor 之外解析较大的渲染树：列表解析是开销最大的部分。
    private func deliverRender(session: String, json: String) {
        guard let delegate else { return }
        // 解析大列表开销最大，应放在主 actor 之外。
        guard let tree = RenderTree(json: json) else {
            report(level: "error", message: "Could not decode the render tree for \(session).")
            return
        }
        Task { @MainActor in delegate.runtime(self, session: session, didRender: tree) }
    }

    private func report(level: String, message: String) {
        guard let delegate else { return }
        Task { @MainActor in delegate.runtime(self, log: level, message: message) }
    }

    // MARK: - Timers

    /// 启动一个 JS 定时器，到点后回调 JS 侧的 `fireTimer`。
    private func startTimer(id: String, milliseconds: Double, repeats: Bool) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = max(milliseconds, 0) / 1000
        if repeats {
            timer.schedule(deadline: .now() + interval, repeating: max(interval, 0.001))
        } else {
            timer.schedule(deadline: .now() + interval)
        }
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !repeats { self.timers[id] = nil }
            _ = self.context?.objectForKeyedSubscript("__gearmac")?
                .invokeMethod("fireTimer", withArguments: [id])
        }
        timers[id]?.cancel()
        timers[id] = timer
        timer.resume()
    }

    /// 取消并移除指定定时器。
    private func clearTimer(id: String) {
        timers[id]?.cancel()
        timers[id] = nil
    }

    /// 定时器是全局的而且 React 调度器依赖它们，因此上下文绝不重用。
    func shutdown() {
        let hostAPI = self.hostAPI
        Task { @MainActor in hostAPI.sessionEnded() }
        queue.async {
            for timer in self.timers.values { timer.cancel() }
            self.timers.removeAll()
            for task in self.hostTasks.values { task.cancel() }
            self.hostTasks.removeAll()
            self.resumeIdleWaiters()
            self.generation = UUID()
            self.context = nil
            self.nodeShims.closeFiles()
        }
    }

    // MARK: - JSON helpers

    /// 将 JS 异常转为可读描述（消息 + 可选堆栈）。
    private static func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "unknown JavaScript error" }
        let stack = exception.objectForKeyedSubscript("stack")?.toString()
        let message = exception.toString() ?? "JavaScript error"
        if let stack, !stack.isEmpty, stack != "undefined" { return "\(message)\n\(stack)" }
        return message
    }

    /// 将 JSON 数组字符串解析为 `[Any]`，失败时返回空数组。
    static func jsonArray(from json: String) -> [Any] {
        guard let data = json.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return array
    }

    /// 容忍片段的编码：宿主结果经常是裸字符串、数字或 nil。
    static func jsonString(from value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.fragmentsAllowed])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
