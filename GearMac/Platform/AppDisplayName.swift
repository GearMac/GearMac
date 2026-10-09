// 文件职责：从 Info.plist 字典或 Bundle 中解析应用显示名（含渠道变体与本地化），并做空值规整。
// 分层：Service；纯读值，不依赖 AppKit/SwiftUI。
import Foundation

/// 空白的 `CFBundleDisplayName` 必须视作不存在：它既画不出内容，也匹配不到任何东西。
enum AppDisplayName {
    /// 把 Info.plist 取值当作名称返回；缺失、非字符串或全为空白时返回 nil。
    static func named(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 返回原始 Info.plist 字典中的名称，供没有可打开 `Bundle` 的调用方使用。
    static func inInfo(_ info: [String: Any]) -> String? {
        // `CFBundle` 优先读取 `-macos` 变体；Image Playground 的 loctable 同时带有两者。
        named(info["CFBundleDisplayName-macos"]) ?? named(info["CFBundleDisplayName"])
            ?? named(info["CFBundleName-macos"]) ?? named(info["CFBundleName"])
    }
}

extension Bundle {
    /// 渠道感知的显示名，取自生成的 Info.plist。
    var appDisplayName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName") ?? "GearMac"
    }

    /// bundle 为自身声明的名称。这并非 Finder 显示的名字——LaunchServices 会忽略与文件名不一致的
    /// `CFBundleDisplayName`，所以启动器按该名称标注行。
    var installedAppName: String {
        infoName("CFBundleDisplayName") ?? infoName("CFBundleName")
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }

    /// 本地化读取：`object(forInfoDictionaryKey:)` 会查询 `InfoPlist.strings`。
    private func infoName(_ key: String) -> String? {
        AppDisplayName.named(object(forInfoDictionaryKey: key))
    }
}
