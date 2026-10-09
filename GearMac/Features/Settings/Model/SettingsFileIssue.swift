// 文件职责：定义 settings.json 中 GearMac 无法使用的情况（SettingsFileIssue）及其面向用户的提示文案。
// 分层：Model；Error + Equatable + Sendable，message 为纯计算属性，不读文件。
import Foundation

/// settings.json 中 GearMac 无法使用的内容，用 HUD 的措辞来表达。
enum SettingsFileIssue: Error, Equatable, Sendable {
    /// `JSONSerialization` 自身的错误描述，其中包含行号与列号。
    case invalidJSON(String)
    /// 其值本应是对象的路径；nil 表示文件本身。
    case notAnObject(String?)
    case unknownSetting(String)
    case invalidValue(SettingsFileKey)
    /// 列表或映射中的某条记录/条目，用便于编写者理解的方式描述。
    case invalidEntry(SettingsFileKey, String)
    /// 文件无法读取。
    case unreadable
    /// 文件无法保存。
    case unwritable

    /// 该问题面向用户的提示文案。
    var message: String {
        switch self {
        case .invalidJSON(let detail): "not valid JSON — \(detail)"
        case .notAnObject(nil): "the file must hold one JSON object"
        case .notAnObject(let path?): "“\(path)” must be an object"
        case .unknownSetting(let path): "unknown setting “\(path)”"
        case .invalidValue(let key): "“\(key.rawValue)” has a value GearMac can't use"
        case .invalidEntry(let key, let detail): "“\(key.rawValue)”: \(detail)"
        case .unreadable: "couldn't be read"
        case .unwritable: "couldn't be saved"
        }
    }

    /// HUD 上显示的一行：第一条问题，以及还有多少条其他问题。
    static func summary(_ issues: [SettingsFileIssue]) -> String? {
        guard let first = issues.first else { return nil }
        let more = issues.count > 1 ? " (+\(issues.count - 1) more)" : ""
        return "settings.json: \(first.message)\(more)"
    }
}
