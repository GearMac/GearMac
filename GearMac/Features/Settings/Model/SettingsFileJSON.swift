// 文件职责：定义保留对象键顺序的 settings.json 内存树（SettingsFileJSON），并提供取值与字面量转换。
// 分层：Model；Equatable + Sendable，字典转来时按键排序以保证顺序稳定。
import Foundation

/// settings.json 的树形表示，对象保留键的顺序，使文件可以自上而下地阅读。
enum SettingsFileJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SettingsFileJSON])
    case object([Member])

    /// 对象中的一个键值对，保留书写顺序。
    struct Member: Equatable, Sendable {
        let key: String
        let value: SettingsFileJSON
    }

    /// 按书写顺序排列的成员，也就是文件列出它们的顺序。
    static func object(_ members: KeyValuePairs<String, SettingsFileJSON>) -> SettingsFileJSON {
        .object(members.map { Member(key: $0.key, value: $0.value) })
    }

    /// 由 `JSONSerialization` 结果构造；字典本身无序，因此对其键排序以保持稳定。
    init(jsonObject: Any) {
        switch jsonObject {
        case let number as NSNumber:
            // `0` 和 `1` 也会桥接为 Bool，因此只有 CFBoolean 装箱的才当作 Bool。
            self =
                CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(SettingsFileJSON.init(jsonObject:)))
        case let dictionary as [String: Any]:
            self = .object(
                dictionary.sorted { $0.key < $1.key }.map {
                    Member(key: $0.key, value: SettingsFileJSON(jsonObject: $0.value))
                })
        default:
            self = .null
        }
    }

    subscript(key: String) -> SettingsFileJSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    var members: [Member]? {
        guard case .object(let members) = self else { return nil }
        return members
    }

    var items: [SettingsFileJSON]? {
        guard case .array(let items) = self else { return nil }
        return items
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var number: Double? {
        guard case .number(let value) = self, value.isFinite else { return nil }
        return value
    }

    /// 仅接受整数：`1.5` 不是文件想要的 `Int`。
    var int: Int? {
        number.flatMap { Int(exactly: $0) }
    }
}

extension SettingsFileJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}
