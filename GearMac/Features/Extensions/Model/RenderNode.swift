// 文件职责：建模运行时推送的渲染树（RenderNode / RenderTree / RenderValue），并提供属性读取与查找。
// 分层：Model；承载 JS 侧 React 渲染结果的纯数据树，不 import AppKit/SwiftUI。
import Foundation

/// 来自运行时的属性值；`node` 是从 `__slot` 提升出来的元素值属性。
enum RenderValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case handler(String)
    case array([RenderValue])
    case object([String: RenderValue])
    case node(RenderNode)
    case null

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            // 整数会以 Double 形式传入；附件若读成 "3.0" 就是错的。
            return value == value.rounded() && value.magnitude < 1e15
                ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var dateValue: Date? {
        if case .date(let date) = self { return date }
        return nil
    }

    var handlerID: String? {
        if case .handler(let id) = self { return id }
        return nil
    }

    var arrayValue: [RenderValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var objectValue: [String: RenderValue]? {
        if case .object(let values) = self { return values }
        return nil
    }

    var nodeValue: RenderNode? {
        if case .node(let node) = self { return node }
        return nil
    }

    /// 持有多个节点的 slot 属性（从子菜单提升上来的 `ActionPanel` 子项）或单个节点。
    var nodesValue: [RenderNode] {
        switch self {
        case .node(let node): return [node]
        case .array(let values): return values.compactMap(\.nodeValue)
        default: return []
        }
    }

    /// 纯 JSON 形式，用于将值不改动地交回给 JS（如表单字段的当前值）。
    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .date(let value): return ["$date": ISO8601DateFormatter().string(from: value)]
        case .handler(let id): return ["$fn": id]
        case .array(let values): return values.map(\.jsonValue)
        case .object(let values): return values.mapValues(\.jsonValue)
        case .node: return NSNull()
        case .null: return NSNull()
        }
    }

    /// 宿主调用参数从 JS 队列以 `Sendable` 形式跨到主 actor 的途径。
    static func arguments(from json: String) -> [RenderValue] {
        ExtensionRuntime.jsonArray(from: json).map(RenderValue.init(json:))
    }

    /// 从任意 JSON 值构造：根据类型分派到字符串、数字、布尔、数组、对象或节点。
    init(json: Any) {
        switch json {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            // NSNumber 会抹去 Bool；CFBoolean 身份是唯一可靠的判别方式。
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.map(RenderValue.init(json:)))
        case let value as [String: Any]:
            if let handler = value["$fn"] as? String {
                self = .handler(handler)
            } else if let iso = value["$date"] as? String {
                self = .date(RenderValue.parseDate(iso) ?? Date())
            } else if let node = RenderNode(json: value), node.isElement {
                self = .node(node)
            } else {
                self = .object(value.mapValues(RenderValue.init(json:)))
            }
        default:
            self = .null
        }
    }

    /// 格式风格是 `Sendable` 的，因此在严格并发下可作为共享常量。
    private static let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO = Date.ISO8601FormatStyle()

    /// 解析 ISO8601 日期字符串（依次尝试带毫秒与不带毫秒两种格式）。
    static func parseDate(_ text: String) -> Date? {
        (try? fractionalISO.parse(text)) ?? (try? plainISO.parse(text))
    }
}

/// 扩展 React 渲染产出的树中的一个节点。
struct RenderNode: Sendable, Hashable, Identifiable {
    let id: Int
    let type: String
    let props: [String: RenderValue]
    let children: [RenderNode]
    /// 仅文本节点（`type == "#text"`）会设置。
    let text: String?

    /// 是否为文本节点。
    var isText: Bool { type == "#text" }
    /// 用于区分普通属性对象与提升上来的 slot 节点的判别标志。
    var isElement: Bool { !isText && id > 0 }

    /// 用各字段直接构造一个节点。
    init(
        id: Int, type: String, props: [String: RenderValue] = [:], children: [RenderNode] = [],
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
        self.text = text
    }

    /// 从 JSON 字典解析一个节点；缺少必需字段时返回 nil。
    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        if type == "#text" {
            self.init(id: 0, type: type, text: json["text"] as? String ?? "")
            return
        }
        guard let id = json["id"] as? Int, let rawProps = json["props"] as? [String: Any],
            let rawChildren = json["children"] as? [Any]
        else { return nil }
        self.init(
            id: id, type: type,
            props: rawProps.mapValues(RenderValue.init(json:)),
            children: rawChildren.compactMap { ($0 as? [String: Any]).flatMap(RenderNode.init(json:)) })
    }

    // MARK: - Prop access

    /// 读取字符串属性；若为对象形式则回退到其 `value` 字段。
    func string(_ key: String) -> String? {
        props[key]?.stringValue ?? props[key]?.objectValue?["value"]?.stringValue
    }
    func bool(_ key: String) -> Bool? { props[key]?.boolValue }
    func double(_ key: String) -> Double? { props[key]?.doubleValue }
    func date(_ key: String) -> Date? { props[key]?.dateValue }
    func handler(_ key: String) -> String? { props[key]?.handlerID }
    func node(_ key: String) -> RenderNode? { props[key]?.nodeValue }
    func nodes(_ key: String) -> [RenderNode] { props[key]?.nodesValue ?? [] }
    func array(_ key: String) -> [RenderValue] { props[key]?.arrayValue ?? [] }
    func object(_ key: String) -> [String: RenderValue]? { props[key]?.objectValue }

    /// `Form.Description` 风格内容与游离 JSX 字符串的到达方式。
    var textContent: String {
        children.compactMap { $0.isText ? $0.text : nil }.joined()
    }

    /// 深度优先查找首个指定 `type` 的后代节点，同时也沿提升的 slot 属性向下查找。
    func firstDescendant(ofType type: String) -> RenderNode? {
        if self.type == type { return self }
        for child in children {
            if let hit = child.firstDescendant(ofType: type) { return hit }
        }
        for value in props.values {
            for node in value.nodesValue {
                if let hit = node.firstDescendant(ofType: type) { return hit }
            }
        }
        return nil
    }
}

/// 运行时在每次 commit 后推送的根：每个栈条目对应一个 `__screen`。
struct RenderTree: Sendable, Equatable {
    let screens: [RenderNode]

    /// 用已解析好的屏幕节点数组构造渲染树。
    init(screens: [RenderNode]) {
        self.screens = screens
    }

    /// 从运行时推送的 JSON 字符串解析渲染树；格式不符时返回 nil。
    init?(json: String) {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let children = root["children"] as? [Any]
        else { return nil }
        let nodes = children.compactMap { ($0 as? [String: Any]).flatMap(RenderNode.init(json:)) }
        // no-view 命令什么也不渲染；view 命令则把每个屏幕包在 `__screen` 中。
        screens = nodes.filter { $0.type == "__screen" }
    }

    /// 调色板当前展示的屏幕——导航栈的栈顶。
    var active: RenderNode? {
        screens.last { $0.bool("active") == true } ?? screens.last
    }

    /// 当前屏幕的单一根组件（`List`、`Detail`、`Form`、`Grid` 等）。
    var activeRoot: RenderNode? {
        active?.children.first { !$0.isText }
    }

    /// 导航栈深度（至少为 1）。
    var depth: Int { max(screens.count, 1) }
}
