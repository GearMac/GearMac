// 文件职责：把「系统设置」的面板（.appex）枚举为可启动的条目，并缓存扫描结果。
// 分层：Service；以 nonisolated 在非主 actor 上扫描磁盘，缓存仅在目录变化时失效。
import Foundation

/// 把系统设置面板枚举为可启动条目，扫描过程不在主 actor 上执行。
enum SettingsPaneScanner {
    private static let extensionsDir = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// bundle 携带的名称无效或缺失的面板；以 CFBundleIdentifier 为键。
    private static let nameOverrides: [String: String] = [
        "com.apple.Battery-Settings.extension": "Battery",
        "com.apple.HeadphoneSettings": "Headphones"
    ]

    /// bundle 图标是 ExtensionKit 占位图的面板；以 CFBundleIdentifier 为键。
    private static let iconOverrides: [String: EntryIcon] = [
        "com.apple.Battery-Settings.extension": .contentType("com.apple.graphic-icon.battery"),
        "com.apple.HeadphoneSettings": .symbol("headphones")
    ]

    /// 完全不应出现在启动器中的面板（上下文相关或一次性的面板）。
    private static let skippedBundleIDs: Set<String> = []

    /// 面板仅在系统更新时变化；列表或日期读取失败时一律不缓存。
    struct Cache: Sendable {
        fileprivate let modified: Date
        fileprivate let languages: [String]
        fileprivate let panes: [AppEntry]
    }

    /// 返回全部系统设置面板，按展示名排序。
    nonisolated static func scan(languages: [String], cache: Cache?) -> ([AppEntry], Cache?) {
        let fm = FileManager.default
        let modified = try? extensionsDir.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cache, cache.modified == modified, cache.languages == languages {
            return (cache.panes, cache)
        }
        guard
            let items = try? fm.contentsOfDirectory(
                at: extensionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return ([], nil) }

        var result: [AppEntry] = []
        for url in items where url.pathExtension == "appex" {
            guard
                let info = plist(at: url.appendingPathComponent("Contents/Info.plist")),
                isSettingsPane(info: info),
                let bundleID = info["CFBundleIdentifier"] as? String,
                !skippedBundleIDs.contains(bundleID),
                let base = AppDisplayName.inInfo(info)
            else { continue }
            let names =
                nameOverrides[bundleID].map { [$0] }
                ?? BundleLocalization.names(
                    for: url, base: base,
                    developmentRegion: info["CFBundleDevelopmentRegion"] as? String,
                    languages: languages)
            result.append(
                AppEntry(
                    id: url.path, name: names.first ?? base, url: url,
                    bundleID: bundleID, kind: .systemSettings,
                    // `EntryNaming` 会丢弃与名称重复的项，因此整个名称列表都可传入。
                    alternateTitles: names, iconOverride: iconOverrides[bundleID]))
        }
        let panes = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (panes, modified.map { Cache(modified: $0, languages: languages, panes: panes) })
    }

    /// 判断该 Info.plist 是否声明为系统设置扩展点。
    private static func isSettingsPane(info: [String: Any]) -> Bool {
        let ex = (info["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"]
        if ex as? String == settingsExtensionPoint { return true }
        let ns = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"]
        return ns as? String == settingsExtensionPoint
    }

    /// 读取并解析指定位置的 plist，失败时返回 nil。
    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
