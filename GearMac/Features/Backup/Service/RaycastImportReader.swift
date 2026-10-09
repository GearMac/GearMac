// 文件职责：解密后的 Raycast 导出 JSON 映射为 GearMac 的设置、快捷键、收藏、别名、剪贴板、片段与快速链接数据。
// 分层：Service；只做数据映射与解析，不写 store；映射规则见 docs/features/raycast-import.md。
import AppKit
import Foundation

/// 把解密后的 Raycast payload 映射到 GearMac 的各个字段。参见 docs/features/raycast-import.md。
enum RaycastImportReader {
    /// 读取并解密 `.rayconfig` 文件，再交给映射逻辑转换为导入结果。
    static func read(file: URL, passphrase: String) throws -> RaycastImport.Result {
        try map(RaycastDecoder.decrypt(try Data(contentsOf: file), passphrase: passphrase))
    }

    /// 把一个解密后的 JSON 根对象映射为完整的导入结果。
    private static func map(_ decrypted: Data) throws -> RaycastImport.Result {
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }
        var backup = SettingsBackup()
        backup.settings = mapSettings(json)
        backup.hotkeys = mapHotkeys(json)
        backup.favoriteApps = mapFavorites(json)
        backup.launcherAliases = mapAliases(json)
        let (clipboard, missing) = RaycastClipboardImport.parse(
            json["clipboardHistory"], now: Date.init,
            fileExists: { FileManager.default.fileExists(atPath: $0) })
        let snippets = RaycastSnippetImport.parse(
            (json["snippets"] as? [String: Any])?["snippets"])
        let quicklinks = RaycastQuicklinkImport.parse(json["quicklinks"])
        return RaycastImport.Result(
            backup: backup,
            clipboard: clipboard,
            snippets: snippets,
            quicklinks: quicklinks,
            missingImages: missing)
    }

    /// Raycast 的 hyper 键代码 → 我们的取值；没有映射到 `.none`，因此不涉及清除。
    private static let hyperKeyCodes: [String: HyperKeyPhysicalKey] = [
        "caps_lock": .capsLock,
        "right_control": .rightControl,
        "right_shift": .rightShift,
        "right_option": .rightOption,
        "right_command": .rightCommand
    ]

    /// 把 Raycast 的 general 设置映射到设置备份；没有任何字段命中时返回 nil。
    private static func mapSettings(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
        let general = (json["settings"] as? [String: Any])?["general"] as? [String: Any]
        var data = SettingsBackup.SettingsData()
        var mapped = false
        if let openAtLogin = general?["openAtLogin"] as? Bool {
            data.launchAtLogin = openAtLogin
            mapped = true
        }
        if let includeShift = general?["hyperKeyIncludeShift"] as? Bool {
            data.hyperKeyIncludesShift = includeShift
            mapped = true
        }
        // 缺少物理键时，导入的组合快捷键无法触发。
        if let code = general?["hyperKeyCode"] as? String, let key = hyperKeyCodes[code] {
            data.hyperKey = key.rawValue
            mapped = true
        }
        if let showInMenuBar = general?["showInMenuBar"] as? Bool {
            data.showInMenuBar = showInMenuBar
            mapped = true
        }
        if let tone = mapSkinTone(json) {
            data.emojiSkinTone = tone
            mapped = true
        }
        // 仅做精确匹配：不在我们选项集合内的超时值直接跳过，而不做截断。
        if let secs = general?["popToRootTimeout"] as? Int,
            let timeout = PopToRootTimeout(rawValue: secs)
        {
            data.popToRootSeconds = timeout.rawValue
            mapped = true
        }
        // Raycast 的窗口模式是字符串；我们只有紧凑模式这一个开关。
        if let mode = general?["windowMode"] as? String {
            data.compactMode = (mode == "compact")
            mapped = true
        }
        if let showFavorites = general?["showFavoritesInCompactMode"] as? Bool {
            data.showFavoritesInCompactMode = showFavorites
            mapped = true
        }
        return mapped ? data : nil
    }

    /// 将 Raycast 的所有快捷键统一映射为同一种形式。参见 docs/features/raycast-import.md。
    private static func mapHotkeys(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        let settings = json["settings"] as? [String: Any]
        var hotkeys = SettingsBackup.HotkeyBackup()
        var apps: [String: HotKeyBinding] = [:]
        var commands: [String: HotKeyBinding] = [:]
        var mapped = false

        if let general = settings?["general"] as? [String: Any],
            let binding = binding(from: general["globalHotkey"])
        {
            hotkeys.togglePalette = binding
            mapped = true
        }

        for command in settings?["commands"] as? [[String: Any]] ?? [] {
            guard let binding = binding(from: command["macosHotkey"]) else { continue }
            switch command["extensionId"] as? String {
            case "e:r:clipboard-history":
                commands[CommandID.clipboardHistory.rawValue] = binding
                mapped = true
            case "e:r:emoji-picker":
                commands[CommandID.searchEmoji.rawValue] = binding
                mapped = true
            case "e:r:applications":
                if let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                {
                    apps[bundleID] = binding
                    mapped = true
                }
            default:
                break
            }
        }
        if !apps.isEmpty { hotkeys.apps = apps }
        if !commands.isEmpty { hotkeys.commands = commands }
        return mapped ? hotkeys : nil
    }

    /// 从 Raycast 快捷键构造绑定；始终为 `.combo`，因为 Raycast 没有双击类型。
    private static func binding(from hotkey: Any?) -> HotKeyBinding? {
        guard let dict = hotkey as? [String: Any],
            let shortcut = (dict["kind"] as? [String: Any])?["shortcut"] as? [String: Any],
            let key = shortcut["key"] as? [String: Any],
            (key["type"] as? String) == "LayoutIndependent",
            let code = key["code"] as? Int
        else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for entry in (shortcut["modifiers"] as? [[String: Any]]) ?? [] {
            switch entry["modifier"] as? String {
            case "Meta": flags.insert(.command)
            case "Ctrl": flags.insert(.control)
            case "Alt": flags.insert(.option)
            case "Shift": flags.insert(.shift)
            default: break
            }
        }
        return .combo(
            KeyShortcut(
                carbonKeyCode: code, carbonModifiers: KeyShortcut.carbonModifiers(from: flags)))
    }

    /// 仅应用类收藏会被映射，以 bundle ID 为键，并保留 Raycast 的顺序。
    private static func mapFavorites(_ json: [String: Any]) -> [String]? {
        guard let commands = (json["settings"] as? [String: Any])?["commands"] as? [[String: Any]]
        else { return nil }
        let favorites =
            commands
            .compactMap { command -> (order: Int, bundleID: String)? in
                guard let order = command["favoriteOrder"] as? Int,
                    command["extensionId"] as? String == "e:r:applications",
                    let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                else { return nil }
                return (order, bundleID)
            }
            .sorted { $0.order < $1.order }
            .map(\.bundleID)
        return favorites.isEmpty ? nil : favorites
    }

    /// 仅应用别名会被映射，与上面的快捷键一样以 bundle ID 为键。
    private static func mapAliases(_ json: [String: Any]) -> [String: String]? {
        guard let commands = (json["settings"] as? [String: Any])?["commands"] as? [[String: Any]]
        else { return nil }
        var aliases: [String: String] = [:]
        for command in commands {
            guard command["extensionId"] as? String == "e:r:applications",
                let alias = (command["alias"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !alias.isEmpty,
                let path = appPath(fromCommandID: command["id"] as? String),
                let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
            else { continue }
            aliases[bundleID] = alias
        }
        return aliases.isEmpty ? nil : aliases
    }

    /// 被启动 App 的路径位于 applications 命令 id 的尾部。
    private static func appPath(fromCommandID id: String?) -> String? {
        guard let id, let range = id.range(of: "::=::") else { return nil }
        let path = String(id[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// 递归查找取值，避免依赖易变的路径；原始值本身已经对得上。
    private static func mapSkinTone(_ json: [String: Any]) -> String? {
        guard let raw = firstValue(forKey: "skinTone", in: json) as? String else { return nil }
        if raw == "default" { return EmojiSkinTone.none.rawValue }
        return EmojiSkinTone(rawValue: raw)?.rawValue
    }

    // MARK: - Helpers

    /// 在嵌套 JSON 对象/数组树中首次出现 `key` 处的取值。
    private static func firstValue(forKey key: String, in object: Any) -> Any? {
        if let dict = object as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        }
        return nil
    }
}
