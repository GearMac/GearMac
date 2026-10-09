// 文件职责：定义用户自定义窗口尺寸模型（宽高单位、锚点、偏移），并提供其几何解析与清洗。
// 分层：Model；保持纯净，仅依赖 CoreGraphics/Foundation，手写解码以兼容旧备份。
import CoreGraphics
import Foundation

/// 用户自定义的窗口命令：一个尺寸配一个位置，施加到当前聚焦窗口。
/// 见 docs/features/window-management.md#custom-sizes。
struct CustomWindowSize: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-size:"
    static let sfSymbol = "macwindow.and.cursorarrow"

    /// 单轴的长度，用它被输入时所用的单位。
    struct Dimension: Codable, Hashable, Sendable {
        enum Unit: String, Codable, CaseIterable, Sendable {
            case points
            case percent

            /// points 时范围宽于任何显示器，使真实尺寸在编写时绝不会被裁掉。
            var range: ClosedRange<Int> {
                switch self {
                case .points: return 1...16_000
                case .percent: return 1...100
                }
            }

            var suffix: String {
                switch self {
                case .points: return "pt"
                case .percent: return "%"
                }
            }
        }

        var value: Int
        var unit: Unit

        init(_ value: Int, _ unit: Unit) {
            self.value = value.clamped(to: unit.range)
            self.unit = unit
        }

        var label: String {
            unit == .points ? "\(value) pt" : "\(value)%"
        }

        /// 它在 `available` 内请求的长度，绝不为零也不会超出。
        func length(in available: CGFloat) -> CGFloat {
            let requested =
                unit == .points ? CGFloat(value) : available * CGFloat(value) / 100
            return min(available, max(WindowLayoutGeometry.minimumLength, requested))
        }

        /// 同一长度换算成 `unit` 的表述，以 `available` 为基准。
        func converted(to unit: Unit, in available: CGFloat) -> Dimension {
            guard unit != self.unit, available > 0 else { return Dimension(value, unit) }
            let points = unit == .percent ? CGFloat(value) : CGFloat(value) * available / 100
            let converted = unit == .percent ? points / available * 100 : points
            return Dimension(Int(converted.rounded()), unit)
        }
    }

    /// 点数，叠加在锦点之上；与 AX 空间各处一样 +Y 向下。
    struct Offset: Codable, Hashable, Sendable {
        static let range: ClosedRange<Int> = -4000...4000
        static let zero = Offset(x: 0, y: 0)

        var x: Int
        var y: Int

        init(x: Int, y: Int) {
            self.x = x.clamped(to: Self.range)
            self.y = y.clamped(to: Self.range)
        }
    }

    let id: UUID
    var name: String
    var width: Dimension
    var height: Dimension
    var anchor: WindowLayoutAnchor
    var offset: Offset

    init(
        id: UUID = UUID(), name: String, width: Dimension = Dimension(60, .percent),
        height: Dimension = Dimension(60, .percent), anchor: WindowLayoutAnchor = .center,
        offset: Offset = .zero
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
        self.offset = offset
    }

    // 手写实现，使新增字段不会破坏已存尺寸与旧备份的可读性。
    private enum CodingKeys: String, CodingKey {
        case id, name, width, height, anchor, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Dimension.self, forKey: .width)
        height = try container.decode(Dimension.self, forKey: .height)
        anchor = try container.decode(WindowLayoutAnchor.self, forKey: .anchor)
        offset = try container.decodeIfPresent(Offset.self, forKey: .offset) ?? .zero
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// 设置行的副标题：用一行说明这个尺寸做什么。
    var summary: String {
        let base = "\(width.label) × \(height.label) · \(anchor.title)"
        return offset == .zero ? base : "\(base) · Offset \(offset.x), \(offset.y) pt"
    }

    /// 按语言取副标题：尺寸、单位与锚点，有偏移时附加偏移。
    func localizedSummary(_ language: AppLanguage) -> String {
        let base = "\(width.label) × \(height.label) · \(anchor.localizedTitle(language))"
        return offset == .zero
            ? base
            : base
                + String(
                    format: L10n.string(WindowKey.sizeSummaryOffset, language: language),
                    offset.x, offset.y)
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// 修剪并夹取而非拒绝，使坏导入也能保留该记录。
    var sanitized: CustomWindowSize {
        var cleaned = self
        cleaned.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.width = Dimension(width.value, width.unit)
        cleaned.height = Dimension(height.value, height.unit)
        cleaned.offset = Offset(x: offset.x, y: offset.y)
        return cleaned
    }

    // MARK: - Geometry

    /// 这个尺寸在某显示器上请求的 frame（AX 空间）；显示器没空间时为 nil。
    func frame(in visibleFrame: CGRect, gap: CGFloat) -> CGRect? {
        let canvas = WindowPlacementEngine.canvas(
            visibleFrame, gap: WindowPlacementEngine.sanitizedGap(gap, in: visibleFrame))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let size = CGSize(
            width: width.length(in: canvas.width), height: height.length(in: canvas.height))
        // 先偏移再夹取：微调是用户的意图，夹取只是安全网。
        let placed = anchor.placement.place(size, in: canvas)
            .offsetBy(dx: CGFloat(offset.x), dy: CGFloat(offset.y))
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: canvas))
    }

    /// 在窗口当前所在的显示器上，这个尺寸把窗口放到哪里。
    func placement(
        for windowFrame: CGRect, screens: [WindowPlacementEngine.Screen], gap: CGFloat
    ) -> WindowPlacementEngine.Placement? {
        guard let host = WindowPlacementEngine.screen(containing: windowFrame, in: screens),
            let frame = frame(in: host.visibleFrame, gap: gap)
        else { return nil }
        return WindowPlacementEngine.Placement(
            frame: frame, screenID: host.id, anchor: anchor.placement, resizes: true)
    }
}

/// 自定义尺寸校验失败的原因，附带面向用户的错误描述。
enum CustomWindowSizeValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidCharacter

    var errorDescription: String? { localizedMessage(.system) }

    /// 按语言取面向用户的错误描述。
    func localizedMessage(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName: return L10n.string(WindowKey.errorSizeEmptyName, language: language)
        case .duplicateName:
            return L10n.string(WindowKey.errorSizeDuplicateName, language: language)
        case .invalidCharacter:
            return L10n.string(WindowKey.errorNameNullCharacter, language: language)
        }
    }
}

extension Int {
    /// 饱和式夹取，使输入或导入的数字被修正而不是拒绝。
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
