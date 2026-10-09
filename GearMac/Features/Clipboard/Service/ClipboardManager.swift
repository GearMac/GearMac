// 文件职责：轮询系统剪贴板，捕获文本、文件与图片并写入 ClipboardStore，同时过滤自身写入与敏感内容。
// 分层：Service；@MainActor 隔离，只负责捕获与去重基准，不直接触碰 UI。
import AppKit

/// 剪贴板捕获服务：轮询系统剪贴板，把文本、文件与图片写入 ClipboardStore。
@MainActor
final class ClipboardManager {
    /// 我们自己写入剪贴板时打上的标记，使轮询忽略自身的写入。
    static let internalType = NSPasteboard.PasteboardType("com.gearmac.internal")

    /// 允许捕获的最长文本；更长的复制会被跳过，避免截断丢失尾部内容。
    static let maxTextLength = 32_000

    /// 密码管理器、浏览器和系统打在机密复制内容上的标记。
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private var lastChangeCount = 0
    private var isCapturing = false

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // 使用 isolated，使析构阶段可以访问 main actor 的 timer；轮询闭包本身已弱引用。
    isolated deinit {
        timer?.invalidate()
    }

    /// 启动剪贴板捕获：安装会话观察者并开始轮询。
    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        installSessionObservers()
        startPolling()
    }

    /// 关闭该功能时，轮询器、观察者和排空逻辑一并停止。
    func stop() {
        isCapturing = false
        sessionTokens = []
        stopPolling()
    }

    // 快速用户切换：其它会话的剪贴板不属于我们，因此停止为其唤醒轮询。
    private func installSessionObservers() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPolling() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                }, center: center)
        ]
    }

    // 先重新建立基准，才能避免在其它会话中产生的复制内容在恢复时被读取为新增。
    private func startPolling() {
        guard isCapturing, timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // 先排空：真实复制内容必须在我们覆盖剪贴板之前进入历史记录。
    func prepareForGearMacPasteboardMutation() {
        guard isCapturing else { return }
        poll()
    }

    // 关键逻辑：changeCount 不匹配说明存在外部写入，下一次轮询仍必须能感知到。
    func synchronizeAfterGearMacPasteboardMutation(changeCount: Int) {
        guard NSPasteboard.general.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    /// 防止 Finder 全选时在单次轮询内插入上万条记录。
    nonisolated static let maxCapturedFiles = 32

    /// 视为可回收的根路径，不含被 `resolvingSymlinksInPath` 去掉的 `/private` 前缀。
    nonisolated static let volatileRoots = [
        "/tmp/", "/var/tmp/", "/var/folders/", NSHomeDirectory() + "/Library/Caches/"
    ]

    /// 两个参数都是注入的环境事实，便于测试框架驱动自己的临时环境。
    nonisolated static func fileURLs(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        let durable = PasteboardFiles.urls(on: pasteboard, limit: maxCapturedFiles) {
            isDurable($0, roots: roots)
        }
        // 返回 nil 而非空数组，使复制的 `http` URL 继续走后续分支并保留为链接。
        guard !durable.isEmpty else { return nil }
        // 插入时反转顺序，使最先复制的文件排在历史记录最前面。
        return durable.map(\.standardizedFileURL.path).reversed()
    }

    /// 若某应用在更优的内联内容旁暂存了临时文件，应保留内联内容。
    nonisolated private static func isDurable(_ url: URL, roots: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return !roots.contains { path.hasPrefix($0) }
    }

    /// 单次轮询：检测 changeCount 变化，并分派到文本、文件或图片处理。
    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        // 绝不记录机密内容：跳过被任一标记方标注为敏感复制内容。
        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        // 剪贴板不携带来源信息，因此归因到最前台的应用。
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }

        // 放在文本分支之前：Finder 会把文件名写到 `.string` 上，同时还有文件 URL。
        if let paths = Self.fileURLs(on: pb) {
            store.addFiles(paths, sourceBundleID: sourceBundleID)
            return
        }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let isPNG = type == .png
            let store = store
            // 大型 TIFF→PNG 重编码可能耗时 100ms 以上，因此避免阻塞轮询。
            Task.detached(priority: .utility) {
                let png =
                    isPNG
                    ? data
                    : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                guard let png else { return }
                await store.addImage(png, sourceBundleID: sourceBundleID)
            }
        }
    }
}
