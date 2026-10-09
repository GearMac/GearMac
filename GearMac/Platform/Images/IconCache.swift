// 文件职责：集中管理与渲染应用/文件/符号/图标 artwork 的位图缓存，按路径、尺寸与样式代际分键。
// 分层：Service；@MainActor 入口与锁保护的可跨线程状态混用，解码在后台线程完成。
import AppKit
import Synchronization
import UniformTypeIdentifiers

/// 单调递增的代际计数器，用于丢弃旧代未完成的异步结果。
struct IconCacheGeneration {
    private(set) var value = 0

    /// 使代际前进一位（溢出回绕）。
    mutating func invalidate() {
        value &+= 1
    }

    /// 仅当代际仍与捕获时一致才写入；无论如何都返回 `item`。
    func publish<Value>(_ item: Value, capturedAt generation: Int, store: (Value) -> Void) -> Value {
        if value == generation { store(item) }
        return item
    }
}

/// SwiftUI 会追踪 `body` 中读到的任何 `@Observable` 值，因此把它放进 id 里就是订阅。
@MainActor
@Observable
final class IconStyleSignal {
    private(set) var generation = 0

    /// 使代际递增，通知所有依赖者重建图标。
    fileprivate func bump() { generation &+= 1 }
}

/// 视图自己的图标键加上样式代际。在 `body` 中构造一个实例，就完成了该视图的订阅。
struct IconRequest<Key: Hashable>: Hashable {
    let key: Key
    let generation: Int

    /// 捕获当前样式代际，使视图对该样式订阅。
    @MainActor
    init(_ key: Key) {
        self.key = key
        self.generation = IconCache.style.generation
    }
}

/// 一个格子的填充色与命名它的键，使 `IconCache` 无需知道颜色由谁选定。
struct SymbolTint: Hashable, Sendable {
    let key: String
    let color: NSColor
}

/// 符号名解析：修正目标 SF Symbols 运行时上与名字相反的表现。
enum SystemSymbolName {
    // 这对图标在目标 SF Symbols 运行时上与名字相反，两种外观下皆如此。
    /// 返回实际应使用的 SF Symbol 名称。
    static func resolve(_ name: String) -> String {
        switch name {
        case "face.smiling": "face.smiling.inverse"
        default: name
        }
    }
}

/// 功能项直接设一个而不是去分支 `AppEntry`；`artwork` 会携带其 extent。
enum EntryIcon: Hashable, Sendable {
    /// stamp 来自 `FileIconStamp`：文件图标变化时它也会变，从而淘汰旧位图。
    case file(stamp: Int)
    case symbol(String)
    case tintedSymbol(name: String, tint: SymbolTint)
    case artwork(path: String, extent: CGFloat)
    /// 某个已声明类型的图标，用于自身文件图标只是占位图的 bundle。
    case contentType(String)
}

/// 图标的点尺寸与缩放倍率。
struct IconSize: Hashable, Sendable {
    let points: CGFloat
    let scale: CGFloat

    /// 以像素表示的边长（向上取整）。
    var pixels: Int { Int((points * scale).rounded(.up)) }
}

/// 按路径缓存应用图标，降采样并对字节数设限，使列表行不必重复访问 `NSWorkspace`。
enum IconCache {
    /// `NSCache` 线程安全但不是 `Sendable`，所以在此一次性断言该保证。
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// 携带尺寸，使查找可以拒绝一个界面已缩放至更大尺寸前生成的位图。
    private final class RowImage {
        let size: IconSize
        let image: NSImage

        /// 记录该位图对应的尺寸与图像。
        init(size: IconSize, image: NSImage) {
            self.size = size
            self.image = image
        }
    }

    private final class RowCache: NSCache<NSString, RowImage>, @unchecked Sendable {}

    // 每个文件一条，而非“文件×尺寸”：缩放时必须替换行内图标，绝不能累积。
    private static let rowCache: RowCache = {
        let cache = RowCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private static let displayPixel: CGFloat = 48

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    // 一份 200 行的结果集放得下；与启动器图标不同，这些会随列表一同丢弃。
    private static let fittedCache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let fittedGeneration = Mutex(IconCacheGeneration())

    /// 只查缓存（绝不触发解码），使行能在同一帧内画出已经预热的图标。
    static func cached(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage? {
        let key = fileKey(path, stamp)
        guard let size else { return cache.object(forKey: key) }
        guard let entry = rowCache.object(forKey: key), entry.size == size else { return nil }
        return entry.image
    }
    /// 只查缓存中的符号图标，未命中时返回 nil。
    static func cachedSymbol(named name: String, tint: SymbolTint? = nil) -> NSImage? {
        cache.object(forKey: symbolKey(name, tint))
    }

    /// 格子在非主线程光栅化，那里动态 `NSColor` 会解析错误，因此需要携带当前表面。
    private static let darkSurface = Mutex(true)

    /// 只有真实变化才使缓存失效：大多数 `effectiveAppearance` 通知并不会改变它。
    @MainActor static func setDarkSurface(_ isDark: Bool) {
        let changed = darkSurface.withLock { surface -> Bool in
            defer { surface = isDark }
            return surface != isDark
        }
        if changed { invalidateStyled() }
    }

    /// 全局而非注入：菜单或列表中谝一次注入就会导致静默的陈旧图标。
    @MainActor static let style = IconStyleSignal()

    /// 与上面同一计数，可在非主线程读取，因为每个缓存键都携带它。
    private static let styleGeneration = Mutex(0)

    /// 供在 `body` 中同步解析图标的场景：这次读取本身就是订阅，所以并非空操作。
    @MainActor static func observeStyle() { _ = style.generation }

    /// 表面或图标样式变化会使所有位图陈旧；每个键中的代际会修正这一点。
    @MainActor static func invalidateStyled() {
        styleGeneration.withLock { $0 &+= 1 }
        cache.removeAllObjects()
        rowCache.removeAllObjects()
        purgeFitted()
        style.bump()
    }

    /// macOS 会就地重绘 `NSWorkspace` 的图像，因此这些字节是样式已落地的唯一凭证。
    static func styleFingerprint() -> Data? {
        let side = 32
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSWorkspace.shared.icon(forFile: styleProbePath)
            .draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private static let styleProbePath = "/System/Library/CoreServices/Finder.app"

    /// 出现在每个键中，使进行中的解码写入一个不可达的位置，而不会重新填满缓存。
    private static func key(_ body: String) -> NSString {
        "\(styleGeneration.withLock { $0 }):\(body)" as NSString
    }

    /// 符号图标的缓存键，包含表面与 tint。
    private static func symbolKey(_ name: String, _ tint: SymbolTint?) -> NSString {
        let surface = darkSurface.withLock { $0 } ? "dark" : "light"
        return key("symbol:\(surface):\(tint?.key ?? "plain"):\(name)")
    }

    /// 刚解码、此后不变的 `NSImage` 可以安全地跨 actor 边界传递。
    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
        let cost: Int

        /// 记录解码结果与其字节开销。
        init(image: NSImage?, cost: Int = 0) {
            self.image = image
            self.cost = cost
        }
    }

    /// 直接返回解码结果，使解码中途的清理不会留下占位图。
    static func loadAsync(forFile path: String, stamp: Int = 0, size: IconSize? = nil) async -> NSImage? {
        if let cached = cached(forFile: path, stamp: stamp, size: size) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path, stamp: stamp, size: size))
        }.value.image
    }
    /// 异步加载符号图标，优先命中缓存。
    static func loadSymbolAsync(named name: String, tint: SymbolTint? = nil) async -> NSImage? {
        if let cached = cachedSymbol(named: name, tint: tint) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: symbolIcon(named: name, tint: tint))
        }.value.image
    }

    /// 同步渲染文件图标（先查缓存，未命中则降采样并写入缓存）。
    static func icon(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage {
        if let size { return rowIcon(forFile: path, stamp: stamp, size: size) }
        let key = fileKey(path, stamp)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// 行内尺寸的文件图标：命中行缓存则直接返回，否则降采样并重绘到目标尺寸。
    private static func rowIcon(forFile path: String, stamp: Int, size: IconSize) -> NSImage {
        if let warm = cached(forFile: path, stamp: stamp, size: size) { return warm }
        let (image, cost) = autoreleasepool { () -> (NSImage, Int) in
            let (source, sourceCost) = downsampled(NSWorkspace.shared.icon(forFile: path))
            return resized(source, to: size) ?? (source, sourceCost)
        }
        rowCache.setObject(RowImage(size: size, image: image), forKey: fileKey(path, stamp), cost: cost)
        return image
    }

    /// 重绘 96px 的结果而非文件的图标：AppKit 的描边与阴影就在那个尺寸下选定。
    private static func resized(_ source: NSImage, to size: IconSize) -> (NSImage, Int)? {
        guard size.pixels < Int(displayPixel * 2) else { return nil }
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size.pixels, pixelsHigh: size.pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: size.points, height: size.points)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }

    /// 应用图标形状格子上的符号；有 tint 时用它填充，并把字形提亮为白色。
    static func symbolIcon(named name: String, tint: SymbolTint? = nil) -> NSImage {
        let key = symbolKey(name, tint)
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let isDark = darkSurface.withLock { $0 }
        let plainInk: CGFloat = isDark ? 1 : 0
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // 格子的内缩量对应 macOS 应用图标在画布中保留的边距。
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            (tint?.color ?? .srgbInk(plainInk, alpha: 0.09)).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            // 带 tint 的格子两种外观下都保持白色油墨；对比度由 tint 承担。
            let ink = tint == nil ? NSColor.srgbInk(plainInk, alpha: 0.85) : .white
            guard let symbol = glyph(named: name, tint: ink)
            else { return true }
            let size = symbol.size
            symbol.draw(
                in: NSRect(
                    x: (side - size.width) / 2, y: (side - size.height) / 2,
                    width: size.width, height: size.height))
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// 优先使用系统符号；SF Symbols 没有的名字回退到模板资源。
    private static func glyph(named name: String, tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
            .applying(.init(paletteColors: [tint]))
        if let symbol = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name), accessibilityDescription: nil
        )?
        .withSymbolConfiguration(config) {
            return symbol
        }
        guard let asset = NSImage(named: name) else { return nil }
        // 24pt 的方框恰好把资源的油墨放在符号约 22pt 的视觉高度上。
        let assetSize = NSSize(width: 24, height: 24)
        return NSImage(size: assetSize, flipped: false) { rect in
            asset.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// 应用图标实际绘制的比例：其他所有 artwork 都以它为基准。
    static let appIconExtent: CGFloat = 0.83

    /// extent 由调用方决定；这里只负责测量与光栅化。
    static func fitted(_ source: NSImage, to extent: CGFloat) -> (NSImage, Int) {
        let painted = paintedExtent(source) ?? appIconExtent
        let side = displayPixel * extent / painted
        let inset = (displayPixel - side) / 2
        return rasterized(source, into: NSRect(x: inset, y: inset, width: side, height: side))
    }

    /// 按路径与 extent 分键，使两个需要不同尺寸的功能不会互相接到对方的图。
    static func artwork(atPath path: String, extent: CGFloat) -> NSImage {
        let key = artworkKey(path, extent)
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = NSImage(contentsOfFile: path) else {
            return symbolIcon(named: "questionmark.square.dashed")
        }
        let (icon, cost) = fitted(source, to: extent)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// 读取缓存中的 artwork，未命中时返回 nil。
    static func cachedArtwork(atPath path: String, extent: CGFloat) -> NSImage? {
        cache.object(forKey: artworkKey(path, extent))
    }

    /// 异步加载 artwork。
    static func loadArtworkAsync(atPath path: String, extent: CGFloat) async -> NSImage? {
        if let cached = cachedArtwork(atPath: path, extent: extent) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: artwork(atPath: path, extent: extent))
        }.value.image
    }

    /// 同步渲染某个已声明类型的图标。
    static func contentTypeIcon(_ identifier: String) -> NSImage {
        let key = contentTypeKey(identifier)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(for: UTType(identifier) ?? .item))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// 读取缓存中的类型图标。
    static func cachedContentTypeIcon(_ identifier: String) -> NSImage? {
        cache.object(forKey: contentTypeKey(identifier))
    }

    /// 异步加载类型图标。
    static func loadContentTypeIconAsync(_ identifier: String) async -> NSImage? {
        if let cached = cachedContentTypeIcon(identifier) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: contentTypeIcon(identifier))
        }.value.image
    }

    /// 类型图标的缓存键。
    private static func contentTypeKey(_ identifier: String) -> NSString {
        key("type:\(identifier)")
    }

    /// artwork 的缓存键，包含 extent。
    private static func artworkKey(_ path: String, _ extent: CGFloat) -> NSString {
        key("artwork:\(extent):\(path)")
    }

    // MARK: - Drawing an `EntryIcon`

    /// 一个 switch 处理全部分支，使行无需知道自己要的是哪种图标。
    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage {
        switch source {
        case .file(let stamp): return icon(forFile: fileURL.path, stamp: stamp)
        case .symbol(let name): return symbolIcon(named: name)
        case .tintedSymbol(let name, let tint): return symbolIcon(named: name, tint: tint)
        case .artwork(let path, let extent): return artwork(atPath: path, extent: extent)
        case .contentType(let identifier): return contentTypeIcon(identifier)
        }
    }

    /// 按 `EntryIcon` 只查缓存。
    static func cached(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) -> NSImage? {
        switch source {
        case .file(let stamp): return cached(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name): return cachedSymbol(named: name)
        case .tintedSymbol(let name, let tint): return cachedSymbol(named: name, tint: tint)
        case .artwork(let path, let extent): return cachedArtwork(atPath: path, extent: extent)
        case .contentType(let identifier): return cachedContentTypeIcon(identifier)
        }
    }

    /// 按 `EntryIcon` 异步加载图标。
    static func loadAsync(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) async -> NSImage? {
        switch source {
        case .file(let stamp): return await loadAsync(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name): return await loadSymbolAsync(named: name)
        case .tintedSymbol(let name, let tint): return await loadSymbolAsync(named: name, tint: tint)
        case .artwork(let path, let extent):
            return await loadArtworkAsync(atPath: path, extent: extent)
        case .contentType(let identifier): return await loadContentTypeIconAsync(identifier)
        }
    }

    /// 读取缓存中已归一化尺寸的文件图标。
    static func cachedFitted(forFile path: String) -> NSImage? {
        fittedCache.object(forKey: fittedKey(path))
    }

    /// 类似 `loadAsync`，但会归一化，使每种文件类型都画出相同的视觉尺寸。
    static func loadFittedAsync(forFile path: String) async -> NSImage? {
        if let cached = cachedFitted(forFile: path) { return cached }
        let generation = fittedGeneration.withLock { $0.value }
        let decoded = await Task.detached(
            priority: .userInitiated,
            operation: { () -> Decoded in
                guard FileManager.default.fileExists(atPath: path) else {
                    return Decoded(image: nil)
                }
                return fittedIcon(forFile: path)
            }
        ).value
        guard let image = decoded.image, !Task.isCancelled else { return nil }
        return fittedGeneration.withLock { current in
            current.publish(image, capturedAt: generation) { image in
                fittedCache.setObject(image, forKey: fittedKey(path), cost: decoded.cost)
            }
        }
    }

    /// 丢弃已归一化图标的缓存并使代际失效。
    static func purgeFitted() {
        fittedGeneration.withLock { generation in
            generation.invalidate()
            fittedCache.removeAllObjects()
        }
    }

    /// 文件图标的缓存键，包含 stamp。
    private static func fileKey(_ path: String, _ stamp: Int) -> NSString {
        key("file:\(stamp):\(path)")
    }
    /// 已归一化图标的缓存键。
    private static func fittedKey(_ path: String) -> NSString { key("fit:" + path) }

    /// 把文件图标归一化到应用图标尺寸并包装为 `Decoded`。
    private static func fittedIcon(forFile path: String) -> Decoded {
        let (icon, cost) = fittedToArtwork(NSWorkspace.shared.icon(forFile: path))
        return Decoded(image: icon, cost: cost)
    }

    /// 把非应用图标的图标补上应用图标所绘制的那部分，真实应用图标则保持原样。
    private static func fittedToArtwork(_ source: NSImage) -> (NSImage, Int) {
        fitted(source, to: appIconExtent)
    }

    /// artwork 较大边所占比例，在 2× 下测量：用 1× 网格会高估该比例。
    private static func paintedExtent(_ source: NSImage) -> CGFloat? {
        let pixels = Int(displayPixel * 2)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 32),
            let data = rep.bitmapData,
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, maxX = -1, minY = pixels, maxY = -1
        for y in 0..<pixels {
            let row = data.advanced(by: y * rep.bytesPerRow)
            for x in 0..<pixels {
                // Alpha 大于 0.06 的像素从第 16 字节开始；更淡的阴影不算作 artwork。
                guard row[x * 4 + 3] >= 16 else {
                    continue
                }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let side = max(maxX - minX + 1, maxY - minY + 1)
        return CGFloat(side) / CGFloat(pixels)
    }

    /// 把多表示的图标光栅化为单个方形位图，并返回其解码字节开销。
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        rasterized(
            source, into: NSRect(origin: .zero, size: NSSize(width: displayPixel, height: displayPixel)))
    }

    /// 把 `source` 画到 `displayPixel` 见方的画布上的 `frame` 区域内。
    private static func rasterized(_ source: NSImage, into frame: NSRect) -> (NSImage, Int) {
        // 固定 2×：`NSScreen.main` 只能在主线程访问，因此脱离主线程解码仍可工作。
        let pixels = Int(displayPixel * 2)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (source, fallbackCost)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}
