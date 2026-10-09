// 文件职责：定义布局条目（某个 app 在某显示器上的尺寸与位置）与布局（已保存的一套摆放）及其校验。
// 分层：Model；保持纯净，仅依赖 CoreGraphics/Foundation，手写解码以兼容旧备份。
import CoreGraphics
import Foundation

/// 一块显示器上的一个 app，尺寸用相对于该显示器的比例表示。见 docs/features/window-layouts.md。
struct WindowLayoutEntry: Codable, Hashable, Identifiable, Sendable {
    /// 存储的比例永远只是一个比例；1pt 下限由 `WindowLayoutGeometry` 负责。
    static let fractionRange: ClosedRange<CGFloat> = 0...1
    /// 宽于任何显示器，使真实微调绝不被裁掉，而荒诞的存储值会被裁掉。
    static let offsetLimit: CGFloat = 10_000

    let id: UUID
    var bundleID: String
    /// 用来打开该 app 的文件、文件夹、URL 或 deeplink；nil 表示普通启动。
    var argument: String?
    var display: WindowLayoutDisplay
    var widthFraction: CGFloat
    var heightFraction: CGFloat
    var anchor: WindowLayoutAnchor
    /// 点数，叠加在锦点之上。
    var offset: CGPoint

    init(
        id: UUID = UUID(), bundleID: String, argument: String? = nil,
        display: WindowLayoutDisplay, widthFraction: CGFloat = 1, heightFraction: CGFloat = 1,
        anchor: WindowLayoutAnchor = .center, offset: CGPoint = .zero
    ) {
        self.id = id
        self.bundleID = bundleID
        self.argument = argument
        self.display = display
        self.widthFraction = widthFraction
        self.heightFraction = heightFraction
        self.anchor = anchor
        self.offset = offset
    }

    // 手写实现，使新增字段不会破坏已存布局与旧备份的可读性。
    private enum CodingKeys: String, CodingKey {
        case id, bundleID, argument, display, widthFraction, heightFraction, anchor, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        argument = try container.decodeIfPresent(String.self, forKey: .argument)
        display = try container.decode(WindowLayoutDisplay.self, forKey: .display)
        widthFraction = try container.decodeIfPresent(CGFloat.self, forKey: .widthFraction) ?? 1
        heightFraction = try container.decodeIfPresent(CGFloat.self, forKey: .heightFraction) ?? 1
        anchor = try container.decodeIfPresent(WindowLayoutAnchor.self, forKey: .anchor) ?? .center
        offset = try container.decodeIfPresent(CGPoint.self, forKey: .offset) ?? .zero
    }

    /// 同一份条目在新身份下的副本，用于复制布局。
    var copy: WindowLayoutEntry {
        WindowLayoutEntry(
            bundleID: bundleID, argument: argument, display: display,
            widthFraction: widthFraction, heightFraction: heightFraction, anchor: anchor,
            offset: offset)
    }

    /// 夹取而非拒绝：坏导入只会丢掉一次微调，绝不会丢掉整个布局。
    static func sanitized(_ entries: [WindowLayoutEntry]) -> [WindowLayoutEntry] {
        entries.compactMap { entry in
            var cleaned = entry
            cleaned.bundleID = entry.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.argument = entry.argument?.cleanedLayoutField
            cleaned.display.uuid = entry.display.uuid.trimmingCharacters(
                in: .whitespacesAndNewlines)
            cleaned.widthFraction = clampFraction(entry.widthFraction)
            cleaned.heightFraction = clampFraction(entry.heightFraction)
            cleaned.offset = CGPoint(
                x: clampOffset(entry.offset.x), y: clampOffset(entry.offset.y))
            guard !cleaned.bundleID.isEmpty, !cleaned.display.uuid.isEmpty else { return nil }
            return cleaned
        }
    }

    private static func clampFraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, fractionRange.lowerBound), fractionRange.upperBound)
    }

    private static func clampOffset(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, -offsetLimit), offsetLimit)
    }
}

/// 一份已保存的摆放：这些 app，在这些尺寸、这些位置、这些显示器上。
struct WindowLayout: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-layout:"
    /// 所有布局共用同一个字形，且绝不用菜单栏自己的，那会读成 app 本身。
    static let sfSymbol = "rectangle.3.group"

    let id: UUID
    var name: String
    var iconSymbol: String?
    /// 让该布局采用全局 `windowGap`，与平铺命令使用它的方式一致。
    var usesPreferredGap: Bool
    var entries: [WindowLayoutEntry]
    /// 唯一一个其窗口在运行结束时位于最前的条目；用 ID 而非布尔标志，因此确实只有一个。
    var frontmostEntryID: UUID?

    init(
        id: UUID = UUID(), name: String, iconSymbol: String? = nil,
        usesPreferredGap: Bool = true, entries: [WindowLayoutEntry] = [],
        frontmostEntryID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.usesPreferredGap = usesPreferredGap
        self.entries = entries
        self.frontmostEntryID = frontmostEntryID
    }

    /// 每个界面为该布局绘制的字形。
    var symbol: String { iconSymbol ?? Self.sfSymbol }

    /// 设置行的副标题：用一行说明这个布局实际做什么。
    var summary: String {
        let displays = Set(entries.map(\.display.uuid)).count
        let windows = entries.count == 1 ? "1 window" : "\(entries.count) windows"
        return displays > 1 ? "\(windows) · \(displays) displays" : windows
    }

    /// 按语言取副标题：窗口数量，跨多显示器时附加显示器数量。
    func localizedSummary(_ language: AppLanguage) -> String {
        let displays = Set(entries.map(\.display.uuid)).count
        let windows =
            entries.count == 1
            ? L10n.string(WindowKey.summaryWindowOne, language: language)
            : String(format: L10n.string(WindowKey.summaryWindowMany, language: language), entries.count)
        return displays > 1
            ? String(format: L10n.string(WindowKey.summaryDisplays, language: language), windows, displays)
            : windows
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// 清洗每个条目，然后丢弃那些条目未能存活的最前标记。
    mutating func sanitizeEntries() {
        entries = WindowLayoutEntry.sanitized(entries)
        if !entries.contains(where: { $0.id == frontmostEntryID }) { frontmostEntryID = nil }
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// 唯一的显示器排序，store 与 `AppIndex` 切片都按它排序。
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // 手写实现，使新增字段不会破坏已存布局与旧备份的可读性。
    private enum CodingKeys: String, CodingKey {
        case id, name, iconSymbol, usesPreferredGap, entries, frontmostEntryID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        usesPreferredGap =
            try container.decodeIfPresent(Bool.self, forKey: .usesPreferredGap) ?? true
        entries = try container.decodeIfPresent([WindowLayoutEntry].self, forKey: .entries) ?? []
        frontmostEntryID = try container.decodeIfPresent(UUID.self, forKey: .frontmostEntryID)
    }
}

extension String {
    /// 修剪后为空则返回 nil——可选字段为空表示“未设置”，而不是空字符串。
    fileprivate var cleanedLayoutField: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("\0") ? nil : trimmed
    }
}

/// 布局校验失败的原因，附带面向用户的错误描述。
enum WindowLayoutValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noEntries
    case invalidCharacter

    var errorDescription: String? { localizedMessage(.system) }

    /// 按语言取面向用户的错误描述。
    func localizedMessage(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName: return L10n.string(WindowKey.errorLayoutEmptyName, language: language)
        case .duplicateName:
            return L10n.string(WindowKey.errorLayoutDuplicateName, language: language)
        case .noEntries: return L10n.string(WindowKey.errorLayoutNoEntries, language: language)
        case .invalidCharacter:
            return L10n.string(WindowKey.errorNameNullCharacter, language: language)
        }
    }
}
