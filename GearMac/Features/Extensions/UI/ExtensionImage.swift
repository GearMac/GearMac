// 文件职责：将 Raycast 的 `Icon` / `Color` / `Image.ImageLike` 值解析为调色板可绘制的图标来源，并负责加载、着色与 SVG 调色板改写。
// 分层：UI；解析为纯函数，图片加载走 `ExtensionIconCache` / `IconCache`，不直接改动模型。
import SwiftUI

/// 把 Raycast 的 `Icon` / `Color` / `Image.ImageLike` 值映射为调色板可绘制的内容。
extension EnvironmentValues {
    /// 派生而非存储，使 `{light, dark}` 图标跟随它所绘制于其上的外观。
    var isDarkAppearance: Bool { colorScheme == .dark }
}

/// 把扩展提供的各类图标值解析为可绘制来源，并负责加载、着色与 SVG 调色板改写。
enum ExtensionImage {
    /// 已解析的图标：SF Symbol、图片文件、Finder 图标、URL 或裸字形。
    enum Source: Equatable {
        case symbol(String)
        case file(String)
        /// Raycast 的 `{ fileIcon }`：该路径指向一个交由 `NSWorkspace` 查询的 bundle。
        case fileIcon(String)
        case remote(URL)
        /// `data:` URL —— 扩展自行渲染 SVG 时直接交付的字节数据。
        case inline(URL)
        case glyph(String)
    }

    /// 解析结果：来源、可选 tint，以及是否为圆形遮罩。
    struct Resolved: Equatable {
        var source: Source
        var tint: Color?
        var isCircular = false
    }

    /// 图标来源，以及 SVG 调色板颜色解析所依据的外观。
    struct LoadKey: Equatable {
        var source: Source?
        var isDark: Bool
    }

    /// 一个 `ImageLike`：字符串，或带主题化 `source` 的 `{source, tintColor, mask, fallback}`。
    static func resolve(_ value: RenderValue?, assetsPath: String?, isDark: Bool) -> Resolved? {
        guard let value else { return nil }
        switch value {
        case .string(let text):
            guard let source = source(from: text, assetsPath: assetsPath, isDark: isDark) else {
                return nil
            }
            return Resolved(source: source)
        case .object(let fields):
            // Raycast 的「带 tooltip 的图标」形式；仅当形似时才拆包。
            if let wrapped = fields["value"]?.objectValue,
                wrapped["source"] != nil || wrapped["value"] != nil || wrapped["fileIcon"] != nil
            {
                return resolve(.object(wrapped), assetsPath: assetsPath, isDark: isDark)
            }
            // `{fileIcon}` 与裸的 `{light, dark}` 对本身就是来源，而非承载来源。
            let raw = fields["source"] ?? fields["value"] ?? .object(fields)
            guard let source = source(from: raw, assetsPath: assetsPath, isDark: isDark) else {
                // 有 tint 但无可用来源的图标仍应得到兜底图块。
                return nil
            }
            return Resolved(
                source: source,
                tint: color(fields["tintColor"], isDark: isDark),
                isCircular: fields["mask"]?.stringValue == "circle")
        default:
            return nil
        }
    }

    /// 始终能解析：无 tint 的破坏性操作会取红色，与原生命令菜单一致。
    static func actionIcon(
        _ value: RenderValue?, assetsPath: String?, isDark: Bool, isDestructive: Bool
    ) -> Resolved {
        var icon =
            resolve(value, assetsPath: assetsPath, isDark: isDark)
            ?? Resolved(source: .symbol(isDestructive ? "trash" : "bolt"))
        // 仅限 SF Symbol：tint 会遮蔽图稿，把删除行自带的 PNG 染红会将其抹去。
        if isDestructive, icon.tint == nil, case .symbol = icon.source { icon.tint = .red }
        return icon
    }

    /// 当扩展只提供一侧（light/dark）时回退到另一侧。
    private static func string(from value: RenderValue?, isDark: Bool) -> String? {
        switch value {
        case .string(let text): return text
        case .object(let fields):
            let preferred = fields[isDark ? "dark" : "light"]?.stringValue
            return preferred ?? fields[isDark ? "light" : "dark"]?.stringValue
        default: return nil
        }
    }

    /// 一个 `Image.Source`：字符串、`{fileIcon}`，或指向二者的 `{light, dark}` 对。
    private static func source(
        from value: RenderValue, assetsPath: String?, isDark: Bool
    ) -> Source? {
        switch value {
        case .string(let text):
            return source(from: text, assetsPath: assetsPath, isDark: isDark)
        case .object(let fields):
            if let path = fields["fileIcon"]?.stringValue, !path.isEmpty {
                return .fileIcon((path as NSString).expandingTildeInPath)
            }
            let preferred = fields[isDark ? "dark" : "light"] ?? fields[isDark ? "light" : "dark"]
            return preferred.flatMap { source(from: $0, assetsPath: assetsPath, isDark: isDark) }
        default:
            return nil
        }
    }

    private static func source(from text: String, assetsPath: String?, isDark: Bool) -> Source? {
        guard !text.isEmpty else { return nil }
        // 图标枚举值都带有 Raycast 生成枚举所用的 `-16` 后缀。
        if text.hasSuffix("-16") {
            if let digits = numberGlyph(forIcon: text) { return .glyph(digits) }
            if let symbol = symbolName(forIcon: text) { return .symbol(symbol) }
        }
        if let url = URL(string: text), let scheme = url.scheme {
            if scheme.hasPrefix("http") { return .remote(url) }
            if scheme == "data" { return .inline(url) }
        }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return .file((text as NSString).expandingTildeInPath)
        }
        // 裸名称是相对于扩展 `assets/` 目录的资源。
        if let assetsPath, text.contains(".") {
            return .file((assetsPath as NSString).appendingPathComponent(text))
        }
        // 其余短到足以是 emoji 或两三个首字母的内容按字形绘制。
        return text.count <= 4 ? .glyph(text) : nil
    }

    /// 每种外观解析一次：该转换是主线程工作，解码时必须跳过。
    static func svgPalette(isDark: Bool) -> [String: String] {
        isDark ? darkSVGPalette : lightSVGPalette
    }

    private static let darkSVGPalette = svgPalette(from: palette, isDark: true)
    private static let lightSVGPalette = svgPalette(from: palette, isDark: false)

    private static func svgPalette(from palette: [String: Color], isDark: Bool) -> [String: String] {
        palette.compactMapValues { cssColor($0, isDark: isDark) }
    }

    /// 依据实际绘制外观解析，因为 `.primary` 与色阶都是动态的。
    private static func cssColor(_ color: Color, isDark: Bool) -> String? {
        var css: String?
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            css =
                "rgba(\(channel(srgb.redComponent)),\(channel(srgb.greenComponent)),"
                + "\(channel(srgb.blueComponent)),\((srgb.alphaComponent * 1000).rounded() / 1000))"
        }
        return css
    }

    /// 四舍五入而非截断：对存储的浮点做 `* 255` 时常会令通道值低 1。
    private static func channel(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }

    static func color(_ value: RenderValue?, isDark: Bool) -> Color? {
        guard let value else { return nil }
        if let text = value.stringValue { return color(named: text) }
        if let fields = value.objectValue {
            return color(named: string(from: .object(fields), isDark: isDark) ?? "")
        }
        return nil
    }

    /// SwiftUI tint 与 SVG 自身 `stroke` 改写为 CSS 时共用的唯一来源。
    private static let palette: [String: Color] = [
        "raycast-blue": .blue,
        "raycast-green": .green,
        "raycast-magenta": Color(red: 0.85, green: 0.24, blue: 0.62),
        "raycast-orange": .orange,
        "raycast-purple": .purple,
        "raycast-red": .red,
        "raycast-yellow": .yellow,
        "raycast-primary-text": .primary,
        "raycast-secondary-text": Theme.Colors.textSecondary
    ]

    private static func color(named raw: String) -> Color? {
        // 扩展也会传入原始 CSS，涵盖 `ColorValue` 支持的各种写法。
        palette[raw]
            ?? ColorValue.parse(raw).map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
            }
    }

    /// SF 只枚举 0…50，因此把全部一百个都按字形绘制，使外观一致。
    private static func numberGlyph(forIcon icon: String) -> String? {
        guard icon.hasPrefix("number-") else { return nil }
        let digits = icon.dropFirst("number-".count).dropLast(3)
        guard digits.count == 2, let value = Int(digits) else { return nil }
        return String(value)
    }

    /// 只手工映射有明确语义的图标；通用形状胜过空白占位。
    private static func symbolName(forIcon icon: String) -> String? {
        let name = String(icon.dropLast(3))
        if let mapped = symbolMap[name] { return mapped }
        // 许多名称已接近某个 SF Symbol；回退前先尝试显而易见的变换。
        let candidates = [name, name.replacingOccurrences(of: "-", with: ".")]
        for candidate in candidates
        where NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
            return candidate
        }
        return "circle.dashed"
    }

    private static let symbolMap: [String: String] = [
        "add-person": "person.badge.plus", "airplane": "airplane", "alarm": "alarm",
        "app-window": "macwindow", "app-window-list": "macwindow.badge.plus",
        "arrow-clockwise": "arrow.clockwise", "arrow-counter-clockwise": "arrow.counterclockwise",
        "arrow-down": "arrow.down", "arrow-left": "arrow.left", "arrow-right": "arrow.right",
        "arrow-up": "arrow.up", "arrow-ne": "arrow.up.right",
        "arrows-expand": "arrow.up.left.and.arrow.down.right",
        "at-symbol": "at", "bell": "bell", "bell-disabled": "bell.slash", "bookmark": "bookmark",
        "bug": "ant", "calculator": "plusminus", "calendar": "calendar", "camera": "camera",
        "check": "checkmark", "check-circle": "checkmark.circle", "check-rosette": "checkmark.seal",
        "chevron-down": "chevron.down", "chevron-up": "chevron.up", "chevron-left": "chevron.left",
        "chevron-right": "chevron.right", "circle": "circle", "circle-filled": "circle.fill",
        "circle-progress-100": "circle.fill", "clipboard": "doc.on.clipboard", "clock": "clock",
        "cloud": "cloud", "code": "chevron.left.forwardslash.chevron.right",
        "code-block": "curlybraces", "cog": "gearshape", "coin": "dollarsign.circle",
        "copy-clipboard": "doc.on.doc", "cd": "opticaldiscdrive", "check-list": "checklist",
        "desktop": "desktopcomputer", "document": "doc", "dot": "circle.fill",
        "download": "arrow.down.circle", "duplicate": "plus.square.on.square",
        "envelope": "envelope", "eraser": "eraser", "exclamationmark": "exclamationmark",
        "exclamationmark-2": "exclamationmark.2", "exclamationmark-3": "exclamationmark.3",
        "eye": "eye", "eye-disabled": "eye.slash", "eye-dropper": "eyedropper",
        "finder": "folder", "folder": "folder", "forward": "goforward", "gauge": "speedometer",
        "gear": "gearshape", "globe": "globe", "hammer": "hammer", "hard-drive": "internaldrive",
        "hashtag": "number", "heart": "heart", "heart-disabled": "heart.slash", "house": "house",
        "image": "photo", "info": "info.circle", "key": "key", "keyboard": "keyboard",
        "layers": "square.3.layers.3d", "light-bulb": "lightbulb", "link": "link",
        "list": "list.bullet", "lock": "lock", "lock-disabled": "lock.open", "lock-unlocked": "lock.open",
        "magnifying-glass": "magnifyingglass", "map": "map", "maximize": "arrow.up.left.and.arrow.down.right",
        "megaphone": "megaphone", "memory-chip": "memorychip", "message": "message",
        "microphone": "mic", "minimize": "arrow.down.right.and.arrow.up.left", "minus": "minus",
        "minus-circle": "minus.circle", "mobile": "iphone", "moon": "moon", "mug-steam": "cup.and.saucer",
        "music": "music.note", "network": "network", "paperclip": "paperclip",
        "pie-chart": "chart.pie", "bar-chart": "chart.bar", "line-chart": "chart.xyaxis.line",
        "box": "shippingbox", "brush": "paintbrush", "power": "power", "pulse": "waveform.path.ecg",
        "pause": "pause", "pencil": "pencil",
        "person": "person", "person-circle": "person.circle", "person-lines": "person.text.rectangle",
        "phone": "phone", "pin": "pin", "pin-disabled": "pin.slash", "play": "play",
        "play-filled": "play.fill", "plug": "powerplug", "plus": "plus", "plus-circle": "plus.circle",
        "plus-square": "plus.square", "printer": "printer", "question-mark": "questionmark",
        "question-mark-circle": "questionmark.circle", "quotation-marks": "quote.opening",
        "raindrop": "drop", "redo": "arrow.uturn.forward", "reply": "arrowshape.turn.up.left",
        "repeat": "repeat", "rewind": "gobackward", "rocket": "airplane.departure",
        "rotate-anti-clockwise": "rotate.left", "rotate-clockwise": "rotate.right",
        "ruler": "ruler", "save-document": "square.and.arrow.down", "shield": "shield",
        "sidebar-left": "sidebar.left", "sidebar-right": "sidebar.right", "snippets": "text.badge.plus",
        "speaker-high": "speaker.wave.3", "speaker-off": "speaker.slash", "star": "star",
        "star-circle": "star.circle", "star-disabled": "star.slash", "stars": "sparkles",
        "stop": "stop", "stopwatch": "stopwatch", "sun": "sun.max", "switch": "switch.2",
        "tag": "tag", "terminal": "terminal", "text": "textformat", "text-cursor": "character.cursor.ibeam",
        "text-input": "character.cursor.ibeam", "three-dots": "ellipsis", "thumbs-down": "hand.thumbsdown",
        "thumbs-up": "hand.thumbsup", "trash": "trash", "tray": "tray", "twitter": "bird",
        "undo": "arrow.uturn.backward", "upload": "arrow.up.circle", "video": "video",
        "wallet": "creditcard", "wand": "wand.and.stars", "warning": "exclamationmark.triangle",
        "waveform": "waveform", "weights": "scalemass", "wifi": "wifi", "wifi-disabled": "wifi.slash",
        "window": "macwindow", "wrench-screwdriver": "wrench.and.screwdriver", "xmark": "xmark",
        "xmark-circle": "xmark.circle", "xmark-circle-filled": "xmark.circle.fill",
        "xmark-top-right-square": "xmark.square",
        // 每个值都已核对：未知名称会绘制占位图。
        "airplane-filled": "airplane", "airplane-landing": "airplane.arrival",
        "airplane-takeoff": "airplane.departure",
        "alarm-ringing": "bell.and.waves.left.and.right.fill", "align-centre": "text.aligncenter",
        "align-left": "text.alignleft", "align-right": "text.alignright", "anchor": "water.waves",
        "app-window-grid-2x2": "square.grid.2x2", "app-window-grid-3x3": "square.grid.3x3",
        "app-window-sidebar-left": "sidebar.left", "app-window-sidebar-right": "sidebar.right",
        "arrow-down-circle-filled": "arrow.down.circle.fill",
        "arrow-left-circle-filled": "arrow.left.circle.fill",
        "arrow-right-circle-filled": "arrow.right.circle.fill",
        "arrow-up-circle-filled": "arrow.up.circle.fill",
        "arrows-contract": "arrow.down.right.and.arrow.up.left", "band-aid": "bandage.fill",
        "bank-note": "banknote.fill", "bar-code": "barcode", "bath-tub": "bathtub.fill",
        "battery": "battery.100percent", "battery-charging": "battery.100percent.bolt",
        "battery-disabled": "battery.0percent", "bike": "bicycle", "blank-document": "doc",
        "bluetooth": "dot.radiowaves.right", "boat": "sailboat.fill",
        "bolt-disabled": "bolt.slash", "bullet-points": "list.bullet", "bulls-eye": "target",
        "bulls-eye-missed": "scope", "buoy": "lifepreserver",
        "center": "rectangle.center.inset.filled", "chess-piece": "crown.fill",
        "chevron-down-small": "chevron.down", "chevron-left-small": "chevron.left",
        "chevron-right-small": "chevron.right", "chevron-up-down": "chevron.up.chevron.down",
        "chevron-up-small": "chevron.up", "circle-disabled": "circle.slash",
        "circle-ellipsis": "ellipsis.circle", "circle-progress": "circle.dotted",
        "circle-progress-25": "progress.indicator", "circle-progress-50": "progress.indicator",
        "circle-progress-75": "progress.indicator",
        "clear-formatting": "textformat.abc.dottedunderline", "cloud-lightning": "cloud.bolt.fill",
        "coins": "dollarsign.circle.fill", "command-symbol": "command",
        "compass": "location.north.circle", "computer-chip": "cpu",
        "contrast": "circle.lefthalf.filled", "credit-card": "creditcard",
        "crypto": "bitcoinsign.circle", "delete-document": "trash",
        "devices": "laptopcomputer.and.iphone", "dna": "atom", "droplets": "drop.fill",
        "edit-shape": "pencil.and.outline", "ellipsis-vertical": "ellipsis",
        "emoji": "face.smiling", "emoji-sad": "face.dashed", "female": "figure.stand.dress",
        "film-strip": "film", "filter": "line.3.horizontal.decrease.circle",
        "fingerprint": "touchid", "footprints": "shoeprints.fill",
        "forward-filled": "forward.fill", "fountain-tip": "pencil.tip",
        "full-signal": "cellularbars", "game-controller": "gamecontroller",
        "geopin": "mappin.and.ellipse", "germ": "microbe.fill", "glasses": "eyeglasses",
        "globe-01": "globe", "goal": "target", "heading": "textformat.size",
        "heartbeat": "waveform.path.ecg", "highlight": "highlighter",
        "important-01": "exclamationmark.circle", "info-01": "info.circle", "italics": "italic",
        "leaderboard": "list.number", "light-bulb-off": "lightbulb.slash",
        "livestream-01": "dot.radiowaves.left.and.right",
        "livestream-disabled-01": "antenna.radiowaves.left.and.right.slash",
        "logout": "rectangle.portrait.and.arrow.right", "lorry": "truck.box.fill",
        "lowercase": "textformat.abc", "male": "figure.stand", "mask": "theatermasks.fill",
        "medical-support": "cross.case.fill", "memory-stick": "memorychip",
        "microphone-disabled": "mic.slash", "minus-circle-filled": "minus.circle.fill",
        "monitor": "display", "moon-down": "moonset.fill", "moon-up": "moonrise.fill",
        "mountain": "mountain.2.fill", "mouse": "computermouse.fill",
        "move": "arrow.up.and.down.and.arrow.left.and.right", "new-document": "doc.badge.plus",
        "new-folder": "folder.badge.plus", "patch": "bandage.fill", "pause-filled": "pause.fill",
        "phone-ringing": "phone.badge.waveform.fill", "plus-circle-filled": "plus.circle.fill",
        "plus-minus-divide-multiply": "plusminus",
        "plus-top-right-square": "plus.square.on.square", "print": "printer",
        "quicklink": "arrow.up.right.square", "quote-block": "text.quote",
        "racket": "figure.tennis", "raycast-logo-neg": "macwindow.on.rectangle",
        "raycast-logo-pos": "macwindow.on.rectangle", "remove-person": "person.badge.minus",
        "replace": "rectangle.2.swap", "replace-one": "arrow.triangle.2.circlepath",
        "rewind-filled": "backward.fill", "rss": "dot.radiowaves.up.forward",
        "shield-01": "shield", "short-paragraph": "text.alignleft", "signal-0": "cellularbars",
        "signal-1": "cellularbars", "signal-2": "cellularbars", "signal-3": "cellularbars",
        "soccer-ball": "soccerball", "speaker-down": "speaker.wave.1.fill",
        "speaker-low": "speaker.wave.1.fill", "speaker-on": "speaker.wave.2.fill",
        "speaker-up": "speaker.wave.3.fill", "speech-bubble": "bubble.left",
        "speech-bubble-active": "bubble.left.fill",
        "speech-bubble-important": "exclamationmark.bubble",
        "square-ellipsis": "ellipsis.rectangle", "stacked-bars-1": "chart.bar.fill",
        "stacked-bars-2": "chart.bar.fill", "stacked-bars-3": "chart.bar.fill",
        "stacked-bars-4": "chart.bar.fill", "stop-filled": "stop.fill", "store": "storefront.fill",
        "strike-through": "strikethrough", "swatch": "swatchpalette.fill", "tack": "pin.fill",
        "tack-disabled": "pin.slash", "temperature": "thermometer.medium",
        "tennis-ball": "tennisball.fill", "text-selection": "selection.pin.in.out",
        "thumbs-down-filled": "hand.thumbsdown.fill", "thumbs-up-filled": "hand.thumbsup.fill",
        "torch": "flashlight.on.fill", "train": "train.side.front.car", "two-people": "person.2",
        "uppercase": "textformat", "video-disabled": "video.slash", "windsock": "wind",
        "wrist-watch": "applewatch", "x-mark-circle": "xmark.circle",
        "x-mark-circle-filled": "xmark.circle.fill", "x-mark-circle-half-dash": "xmark.circle",
        "x-mark-top-right-square": "xmark.square"
    ]
}

extension ExtensionImage {
    /// 动画图块直接使用原图；走适配路径只会返回其中一帧。
    static func load(_ resolved: Resolved?, isDark: Bool, animates: Bool) async -> NSImage? {
        switch resolved?.source {
        case .file(let path):
            return animates
                ? await ExtensionIconCache.loadOriginalAsync(atPath: path)
                : await ExtensionIconCache.loadAsync(atPath: path)
        case .fileIcon(let path):
            // 走适配而非原图：只有规范化绘制才能让 bundle 与文档尺寸统一。
            return await IconCache.loadFittedAsync(forFile: path)
        case .remote(let url):
            return await ExtensionIconCache.loadRemoteAsync(url, asIcon: !animates)
        case .inline(let url):
            return await ExtensionIconCache.loadInlineAsync(
                url, palette: svgPalette(isDark: isDark))
        default:
            return nil
        }
    }
}

/// 按行尺寸绘制的已解析图标；无法解析时绘制淡色图块，使行高不会跳动。
struct ExtensionIconView: View {
    private enum MenuSymbolStyle {
        static let size: CGFloat = 14
        static let color = Theme.Colors.ramp(dark: 0.70, light: 0.70)
    }

    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let resolved: ExtensionImage.Resolved?
    var size: CGFloat?
    /// 需显式开启，行内图标默认关闭：24pt 处播放的 GIF 在长列表里只会造成干扰。
    var animates = false
    var usesMenuSymbolStyle = false
    @State private var loaded: NSImage?

    /// 默认采用行尺寸，除非调用方指定；目前只有 ⌘K 面板的 20pt 位置会指定。
    private var side: CGFloat { size ?? metrics.size.rowIcon }

    var body: some View {
        content
            .frame(width: side, height: side)
            .clipShape(shape)
            // 也以外观作为键：内联 SVG 的调色板在解码时解析。
            .task(id: ExtensionImage.LoadKey(source: resolved?.source, isDark: isDark)) {
                loaded = await ExtensionImage.load(resolved, isDark: isDark, animates: animates)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch resolved?.source {
        case .symbol(let name):
            Image(systemName: name)
                .font(
                    .system(
                        size: usesMenuSymbolStyle
                            ? metrics.scaled(MenuSymbolStyle.size)
                            : side * 0.62,
                        weight: usesMenuSymbolStyle ? .medium : .regular)
                )
                .symbolRenderingMode(
                    usesMenuSymbolStyle
                        ? .monochrome
                        : (resolved?.tint == nil ? .hierarchical : .monochrome)
                )
                .foregroundStyle(
                    resolved?.tint
                        ?? (usesMenuSymbolStyle
                            ? MenuSymbolStyle.color
                            : Theme.Colors.textSecondary)
                )
                .frame(width: side, height: side)
        case .glyph(let text):
            Text(text)
                .font(.system(size: side * 0.72))
                .frame(width: side, height: side)
        case .file, .fileIcon, .remote, .inline:
            if let loaded {
                // 只有多帧图片才走 `NSImageView`；静态图仍留在 SwiftUI 的绘制路径上。
                if animates, loaded.isAnimated {
                    AnimatedImageView(image: loaded)
                } else {
                    // `tintColor` 会遮蔽图稿，这正是为 `currentColor` 的 SVG 着色的方式。
                    Image(nsImage: loaded)
                        .resizable()
                        .renderingMode(resolved?.tint == nil ? .original : .template)
                        .scaledToFit()
                        .foregroundStyle(resolved?.tint ?? .primary)
                }
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
            .fill(Theme.Colors.iconPlaceholder)
    }

    private var shape: AnyShape {
        resolved?.isCircular == true
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
    }

}
