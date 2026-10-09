// 文件职责：提供不受固定结构约束的 JSON 值树（JSONValue），可在任意字典/数组间转换与保真传递。
// 分层：Model；纯值类型，仅做 JSON 与原生类型的互转。
import Foundation

/// 解码后的 JSON 树，用于结构由发送方而非我们决定的数据。
enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// 由任意 JSONSerialization 结果构建。
    init(_ value: Any) {
        switch value {
        case is NSNull: self = .null
        // `0`/`1` 也会桥接为 Bool，因此只有 CFBoolean 装箱的值才算布尔。
        case let value as NSNumber:
            self =
                CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue) : .number(value.doubleValue)
        case let value as String: self = .string(value)
        case let value as [Any]: self = .array(value.map(JSONValue.init))
        case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
        default: self = .null
        }
    }

    /// 从字节解析，使 schema 或参数块可以在无需理解其含义的情况下传递。
    init?(data: Data) {
        guard
            let parsed = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed])
        else { return nil }
        self.init(parsed)
    }

    /// 还原为 `JSONSerialization` 的形状，便于把值重新编码进另一个请求。
    var jsonObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.jsonObject)
        case .object(let value): return value.mapValues(\.jsonObject)
        }
    }

    /// 当前值为对象时返回其字典。
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// 当前值为数组时返回其元素。
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// 当前值为字符串时返回它。
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// 当前值为布尔时返回它。
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// 当前值为数值时返回其整数形式。
    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }
}
