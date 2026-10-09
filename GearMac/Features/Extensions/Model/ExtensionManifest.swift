// 文件职责：解析并建模 Raycast 扩展的 `package.json`（manifest），包括命令、偏好项 schema、参数与偏好值。
// 分层：Model；仅做 JSON 解析与值建模，不 import AppKit/SwiftUI。
import Foundation

/// 扩展命令的运行模式（对应 manifest 中的 `mode` 字符串）。
enum ExtensionCommandMode: String, Sendable, Codable {
    case view
    case noView = "no-view"
    case menuBar = "menu-bar"
}

/// manifest `preferences` 数组中的单个条目。
struct ExtensionPreferenceSchema: Sendable, Hashable {
    /// 偏好项的输入控件类型。
    enum Kind: String, Sendable {
        case textfield
        case password
        case checkbox
        case dropdown
        case appPicker
        case file
        case directory

        /// 根据 manifest 中的类型字符串解析；缺失或未知时回退为 `textfield`。
        init(raw: String?) {
            self = Kind(rawValue: raw ?? "textfield") ?? .textfield
        }
    }

    /// 下拉选项：展示标题与对应取值。
    struct Option: Sendable, Hashable {
        let title: String
        let value: String
    }

    let name: String
    let title: String?
    let label: String?
    let description: String?
    let placeholder: String?
    let kind: Kind
    let required: Bool
    let options: [Option]
    /// 已针对 macOS 解析：manifest 的默认值可以是按平台分键的。
    let defaultValue: ExtensionPreferenceValue?

    /// 用户未设置时使用的值——回退到与类型相符的空值。
    var effectiveDefault: ExtensionPreferenceValue {
        defaultValue ?? (kind == .checkbox ? .bool(false) : .string(""))
    }

    /// app picker 向 JS 传递为 Application 对象，而未设置时则完全不出现该键。
    func runtimeValue(_ stored: ExtensionPreferenceValue?) -> ExtensionPreferenceValue? {
        let value = stored ?? effectiveDefault
        guard kind == .appPicker else { return value }
        let path = value.stringValue
        return path.isEmpty ? nil : .application(path)
    }

    /// 用于展示的标题，依次回退到 `title`、`label`、`name`。
    var displayTitle: String { title ?? label ?? name }

    /// 从 JSON 对象解析一个偏好项；缺少必需的 `name` 时返回 nil。
    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String else { return nil }
        self.name = name
        title = dict["title"] as? String
        label = dict["label"] as? String
        description = dict["description"] as? String
        placeholder = dict["placeholder"] as? String
        kind = Kind(raw: dict["type"] as? String)
        required = dict["required"] as? Bool ?? false
        options = (dict["data"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let value = entry["value"] as? String else { return nil }
            return Option(title: entry["title"] as? String ?? value, value: value)
        }
        defaultValue = ExtensionPreferenceValue(manifestDefault: dict["default"])
    }
}

/// 在 manifest、`UserDefaults` 与 JS 之间往返传递的偏好值。
enum ExtensionPreferenceValue: Sendable, Hashable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case application(String)

    /// 序列化为 JSON 可用的值；app picker 展开为包含名称、路径与 bundleId 的字典。
    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .number(let value): return value
        case .application(let path):
            let url = URL(filePath: path)
            let bundle = Bundle(url: url)
            return [
                "name": bundle?.installedAppName ?? url.deletingPathExtension().lastPathComponent,
                "path": path, "bundleId": bundle?.bundleIdentifier as Any? ?? NSNull()
            ]
        }
    }

    /// 统一转为字符串形式（供文本偏好项与日志等使用）。
    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
        case .application(let path): return path
        }
    }

    /// 统一转为布尔形式。
    var boolValue: Bool {
        switch self {
        case .string(let value): return value == "true"
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .application(let path): return !path.isEmpty
        }
    }

    /// 从 manifest 的默认值字段解析；无法识别时返回 nil。
    init?(manifestDefault raw: Any?) {
        switch raw {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self =
                CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue) : .number(value.doubleValue)
        case let value as [String: Any]:
            // 按平台分键的默认值；GearMac 仅支持 macOS。
            guard let macOS = value["macOS"] else { return nil }
            self.init(manifestDefault: macOS)
        default:
            return nil
        }
    }
}

/// 启动器在命令运行前向用户收集的一个参数。
struct ExtensionCommandArgument: Sendable, Hashable {
    let name: String
    let type: String
    let placeholder: String
    let required: Bool

    /// 从 JSON 对象解析一个命令参数；缺少必需的 `name` 时返回 nil。
    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String else { return nil }
        self.name = name
        type = dict["type"] as? String ?? "text"
        placeholder = dict["placeholder"] as? String ?? name
        required = dict["required"] as? Bool ?? false
    }
}

/// manifest 中声明的一个扩展命令。
struct ExtensionCommand: Sendable, Hashable, Identifiable {
    let name: String
    let title: String
    let subtitle: String?
    let description: String
    let mode: ExtensionCommandMode
    let intervalRaw: String?
    /// 解析后的 `interval`，已按刷新下限作限制；manifest 未设置调度时为 nil。
    let interval: TimeInterval?
    let keywords: [String]
    let icon: String?
    let disabledByDefault: Bool
    let preferences: [ExtensionPreferenceSchema]
    let arguments: [ExtensionCommandArgument]

    /// 在其扩展内唯一；`ExtensionCommandRef` 将其与所属扩展配对，形成全局 id。
    var id: String { name }

    /// Raycast 的约定：未填写的参数以空文本传入，因为 `undefined` 会是 `NaN`。
    func completeArguments(_ given: [String: String]) -> [String: String] {
        var complete = given
        for argument in arguments where complete[argument.name] == nil {
            complete[argument.name] = ""
        }
        return complete
    }

    /// 从 JSON 对象解析一个命令；缺少 `name` 或 `title` 时返回 nil。
    init?(json: Any) {
        guard let dict = json as? [String: Any], let name = dict["name"] as? String,
            let title = dict["title"] as? String
        else { return nil }
        self.name = name
        self.title = title
        subtitle = dict["subtitle"] as? String
        description = dict["description"] as? String ?? ""
        mode = ExtensionCommandMode(rawValue: dict["mode"] as? String ?? "view") ?? .view
        intervalRaw = dict["interval"] as? String
        interval = ExtensionRefreshPolicy.parse(
            intervalRaw,
            floor: mode == .menuBar
                ? ExtensionRefreshPolicy.menuBarMinimumInterval : ExtensionRefreshPolicy.minimumInterval)
        keywords = dict["keywords"] as? [String] ?? []
        icon = dict["icon"] as? String
        disabledByDefault = dict["disabledByDefault"] as? Bool ?? false
        preferences = (dict["preferences"] as? [Any] ?? []).compactMap(ExtensionPreferenceSchema.init(json:))
        arguments = (dict["arguments"] as? [Any] ?? []).compactMap(ExtensionCommandArgument.init(json:))
    }
}

/// Raycast 扩展的 `package.json`，精简为 GearMac 所使用的那部分。
struct ExtensionManifest: Sendable, Hashable {
    let name: String
    let title: String
    let description: String
    let author: String
    /// 扩展发布所属的组织，当其不等于作者本人时存在。
    let owner: String?
    let icon: String?
    let categories: [String]
    let platforms: [String]?
    let commands: [ExtensionCommand]
    let preferences: [ExtensionPreferenceSchema]

    /// 商店列它时使用的 handle：有组织时用组织名。
    var storeHandle: String { owner ?? author }

    /// 旧版 manifest 没有 `platforms` 字段，它们早于 Windows 支持，因而仅支持 macOS。
    var supportsMacOS: Bool {
        guard let platforms else { return true }
        return platforms.contains { $0.caseInsensitiveCompare("macOS") == .orderedSame }
    }

    /// manifest 加载与解析过程中可能出现的错误。
    enum ParseError: LocalizedError {
        /// 无法读取 manifest 文件。
        case unreadable(URL)
        /// 目标目录不包含合法的 Raycast 扩展 manifest。
        case notAnExtension(URL)

        /// 面向用户的本地化错误描述。
        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Couldn't read \(url.lastPathComponent)."
            case .notAnExtension(let url):
                return "\(url.lastPathComponent) doesn't contain a Raycast extension manifest."
            }
        }
    }

    /// 从指定目录的 `package.json` 加载并解析 manifest；失败时抛出 `ParseError`。
    static func load(directory: URL) throws -> ExtensionManifest {
        let manifestURL = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ParseError.unreadable(manifestURL)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let manifest = ExtensionManifest(json: json)
        else { throw ParseError.notAnExtension(directory) }
        return manifest
    }

    /// 从已解析的 JSON 字典构造 manifest；缺少 `name` 或没有任何命令时返回 nil。
    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        let commands = (json["commands"] as? [Any] ?? []).compactMap(ExtensionCommand.init(json:))
        guard !commands.isEmpty else { return nil }
        self.name = name
        title = json["title"] as? String ?? name
        description = json["description"] as? String ?? ""
        author = json["author"] as? String ?? ""
        owner = json["owner"] as? String
        icon = json["icon"] as? String
        categories = json["categories"] as? [String] ?? []
        platforms = json["platforms"] as? [String]
        self.commands = commands
        preferences = (json["preferences"] as? [Any] ?? []).compactMap(ExtensionPreferenceSchema.init(json:))
    }
}
