// 文件职责：为扩展图标提供缓存与加载（本地文件、内联 data URL、远程 URL）并处理调色板颜色关键字重写。
// 分层：Service；缓存按图标/原图分开计量，不缩放原图以免 GIF 被压为首帧。
import AppKit

/// 扩展的图标资源；为何绘制得更小见 docs/features/extensions.md。
enum ExtensionIconCache {
    /// 小于 `IconCache.appIconExtent`；只在对照一整套渲染出的图标时才调整它。
    static let extent: CGFloat = 0.76

    /// `NSCache` 线程安全但不是 `Sendable`，因此在此一次性声明该保证。
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// 使用独立的内存预算：Detail markdown 缓存的图片远大于列表行图标。
    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    /// 刚解码且此后不再修改的 `NSImage` 可以安全地跨 actor 边界传递。
    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
    }

    // MARK: - Shipped with the extension

    /// 只读缓存，使已热缓存的行能在同一帧完成绘制。
    static func cached(atPath path: String) -> NSImage? {
        IconCache.cachedArtwork(atPath: path, extent: extent)
    }

    /// 直接读文件：交给 `NSWorkspace` 会把 PNG 解析为通用文档图标。
    static func icon(atPath path: String) -> NSImage {
        guard FileManager.default.fileExists(atPath: path) else {
            return IconCache.symbolIcon(named: "puzzlepiece.extension")
        }
        return IconCache.artwork(atPath: path, extent: extent)
    }

    /// 异步加载图标：文件不存在时回退到 `puzzlepiece.extension` 符号图标。
    static func loadAsync(atPath path: String) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            return IconCache.symbolIcon(named: "puzzlepiece.extension")
        }
        return await IconCache.loadArtworkAsync(atPath: path, extent: extent)
    }

    /// 绝不做栅格化缩放：缩放会把 GIF 压平为第一帧。
    static func loadOriginalAsync(atPath path: String) async -> NSImage? {
        let key = originalKey(path)
        if let cached = cache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(contentsOfFile: path))
        }.value
        guard let image = decoded.image else { return nil }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }

    // MARK: - Carried inline by the extension

    /// 不缓存也不缩放：数据已在内存中，尺寸也已由扩展自行决定。
    static func loadInlineAsync(_ url: URL, palette: [String: String]) async -> NSImage? {
        guard let data = inlineData(url) else { return nil }
        let names = isSVG(url) ? palette : [:]
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(data: resolvingPaletteNames(in: data, palette: names)))
        }.value.image
    }

    /// 没有渲染器认识 `raycast-*` 颜色关键字，否则图形会绘制不出内容。
    private static func resolvingPaletteNames(in data: Data, palette: [String: String]) -> Data {
        guard let source = String(data: data, encoding: .utf8) else { return data }
        let resolved = rewritingNames(in: source, palette: palette) ?? source
        let rewritten = resolved.replacing(#/(fill|stroke)(\s*=\s*["']|\s*:\s*)transparent\b/#) {
            "\($0.1)\($0.2)none"
        }
        return Data(rewritten.utf8)
    }

    /// 只匹配完整名称：`raycast-red` 是 `raycast-red-invented` 的前缀子串。
    private static func rewritingNames(in text: String, palette: [String: String]) -> String? {
        // 使用 `.literal`：默认搜索是 Unicode 规范等价匹配，在长文本上开销约 3 倍。
        guard text.range(of: paletteNamePrefix, options: .literal) != nil else { return nil }
        var resolved = ""
        var rest = Substring(text)
        while let match = rest.range(of: paletteNamePrefix, options: .literal) {
            let name = rest[match.lowerBound...].prefix { paletteNameCharacters.contains($0) }
            resolved += rest[..<match.lowerBound]
            resolved += palette[String(name)] ?? String(name)
            rest = rest[name.endIndex...]
        }
        return resolved + rest
    }

    private static let paletteNamePrefix = "raycast-"
    private static let paletteNameCharacters = Set("abcdefghijklmnopqrstuvwxyz-")

    /// 不区分大小写，因为媒体类型本身不区分：`image/SVG+XML` 是合法写法。
    private static func isSVG(_ url: URL) -> Bool {
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else { return false }
        return text[..<comma].range(of: "svg", options: .caseInsensitive) != nil
    }

    /// 去掉查询参数：Detail markdown 会追加 Raycast 的 `?raycast-width=…` 提示。
    private static func inlineData(_ url: URL) -> Data? {
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let payload = String(text[text.index(after: comma)...].prefix { $0 != "?" })
        guard text[..<comma].hasSuffix(";base64") else {
            return payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    // MARK: - Fetched by the extension

    /// 失败时不写缓存，因此瞬时错误可以重试；markdown 图片会关闭 `asIcon`。
    static func loadRemoteAsync(_ url: URL, asIcon: Bool = true) async -> NSImage? {
        let key = remoteKey(url, asIcon: asIcon)
        if let cached = cache.object(forKey: key) { return cached }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(data: data))
        }.value
        guard let source = decoded.image else { return nil }
        guard asIcon else {
            cache.setObject(source, forKey: key, cost: Int(source.size.width * source.size.height * 4))
            return source
        }
        let (icon, cost) = IconCache.fitted(source, to: extent)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// 不使用缓存，也不用 `URLSession.shared`：这些 URL 由扩展指定。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static func originalKey(_ path: String) -> NSString { ("raw:" + path) as NSString }
    private static func remoteKey(_ url: URL, asIcon: Bool) -> NSString {
        ((asIcon ? "remote:" : "full:") + url.absoluteString) as NSString
    }
}
