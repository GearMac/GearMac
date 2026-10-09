// 文件职责：定义启动器条目在 settings.json 中的读写格式（快捷键、别名、启动器可见性），并负责与 `SettingsFileJSON` 的互相转换。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 启动器条目在 settings.json 中的行格式：快捷键、别名与启动器可见性。
enum LauncherFileFormat {
    /// 单个启动器条目的持久化字段。
    struct Record: Equatable, Sendable {
        var shortcut: String?
        var alias: String?
        var showInLauncher = true

        /// 未设置任何字段，不占存储空间。
        var isEmpty: Bool { shortcut == nil && alias == nil && showInLauncher }
    }

    /// 解码结果：条目表与碰到的格式问题列表。
    typealias Decoded = (records: [String: Record], problems: [String])

    /// 把条目表序列化为 settings.json 的 JSON 对象。
    static func json(_ records: [(name: String, record: Record)]) -> SettingsFileJSON {
        .object(
            records.map { item in
                SettingsFileJSON.Member(
                    key: item.name,
                    value: .object([
                        "shortcut": text(item.record.shortcut),
                        "alias": text(item.record.alias),
                        "showInLauncher": .bool(item.record.showInLauncher)
                    ]))
            })
    }

    /// 从 JSON 解码条目表，以 `current` 提供未声明字段的默认值；整体不是对象时返回 nil。
    static func records(from json: SettingsFileJSON, current: (String) -> Record) -> Decoded? {
        guard let members = json.members else { return nil }
        var decoded: Decoded = ([:], [])
        for member in members {
            let fields = member.value
            guard fields.members != nil else {
                decoded.records[member.key] = current(member.key)
                decoded.problems.append("“\(member.key)” needs an object")
                continue
            }
            var record = current(member.key)
            text(fields["shortcut"], field: "shortcut", of: member.key, into: &record.shortcut, &decoded)
            text(fields["alias"], field: "alias", of: member.key, into: &record.alias, &decoded)
            switch fields["showInLauncher"] {
            case nil: break
            case .bool(let shown)?: record.showInLauncher = shown
            default: decoded.problems.append("“\(member.key)”: “showInLauncher” needs true or false")
            }
            decoded.records[member.key] = record
        }
        return decoded
    }

    /// 把可选的字符串写成 JSON 字符串或 `null`。
    private static func text(_ value: String?) -> SettingsFileJSON {
        value.map(SettingsFileJSON.string) ?? .null
    }

    /// 解析单个字符串字段：缺失不动、`null` 置空、非字符串则记入问题列表。
    private static func text(
        _ json: SettingsFileJSON?, field: String, of name: String, into value: inout String?,
        _ decoded: inout Decoded
    ) {
        switch json {
        case nil: return
        case .null?: value = nil
        case .string(let text)?: value = text
        default: decoded.problems.append("“\(name)”: “\(field)” needs quotes, or null")
        }
    }
}
