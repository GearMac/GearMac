// 文件职责：卸载目标及其匹配身份的定义——目标元数据、归属证据与身份构造的安全门槛。
// 分层：Model（Uninstall）；纯模型，供 `Tests/uninstall-test.swift` 直接驱动。
import Foundation

/// 卸载的目标。保持纯净，供 `Tests/uninstall-test.swift` 使用。
struct UninstallTarget: Hashable, Sendable {
    let bundleURL: URL
    let bundleID: String?
    let displayName: String
    /// 部分 App 的支持目录以 `CFBundleName` 命名，而非显示名称。
    let bundleName: String?
}

/// 候选条目归属于目标的方式。
enum UninstallEvidence: String, Hashable, Sendable, CaseIterable {
    case bundle
    case bundleID
    case groupContainer
    case displayName
    case binSymlink

    /// 弱证据会在列表行上自行标注；证据充分的匹配不显示说明。
    func localizedLabel(_ language: AppLanguage) -> String? {
        switch self {
        case .displayName:
            return L10n.string(UninstallKey.evidenceMatchedByName, language: language)
        case .binSymlink:
            return L10n.string(UninstallKey.evidenceCommandLineTool, language: language)
        case .bundle, .bundleID, .groupContainer: return nil
        }
    }
}

/// 可用于匹配的目标形态；`make` 会事先施加全部安全约束。
struct UninstallIdentity: Hashable, Sendable {
    /// 大小写折叠后的 bundle ID；目标没有则为 nil。
    let bundleID: String?
    /// 两段式 ID 为 false：前缀匹配 `com.adobe` 会横扫整个厂商的产物。
    let allowsBundleIDPrefixMatch: Bool
    /// 其他已安装 App 折叠后的 ID，避免某个渠道认领另一个渠道的产物。
    let otherBundleIDs: Set<String>
    /// 折叠后足够安全、可以用来认领整个目录的名称。
    let names: [String]
    let bundleURL: URL

    /// 取 3 而非 4：Zed、IINA 等会以自身名称命名目录；真正的安全性由其他约束保证。
    static let minimumNameLength = 3

    /// 标准资源库子目录名，避免同名 App 认领它们。
    static let reservedNames: Set<String> = [
        "apple", "application support", "application scripts", "autosave information", "caches",
        "containers", "cookies", "crashreporter", "fonts", "frameworks", "group containers",
        "httpstorages", "keychains", "launchagents", "launchdaemons", "logs", "metadata",
        "mobilesync", "preferences", "privilegedhelpertools", "scripts", "services", "sync",
        "syncservices", "webkit"
    ]

    /// 返回 nil 即拒绝卸载；`ownBundleID` 是当前运行的身份，因此开发版会拒绝卸载自己。
    static func make(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String] = [],
        ownBundleID: String?, ownBundleURL: URL
    ) -> UninstallIdentity? {
        if let ownBundleID, let bundleID = target.bundleID,
            folded(bundleID) == folded(ownBundleID)
        {
            return nil
        }
        if target.bundleURL.standardizedFileURL == ownBundleURL.standardizedFileURL { return nil }

        let bundleID = target.bundleID.map(folded).flatMap { $0.isEmpty ? nil : $0 }
        let names = safeNames(
            displayName: target.displayName, bundleName: target.bundleName,
            otherAppNames: otherAppNames)
        guard bundleID != nil || !names.isEmpty else { return nil }

        return UninstallIdentity(
            bundleID: bundleID,
            allowsBundleIDPrefixMatch: (bundleID?.split(separator: ".").count ?? 0) >= 3,
            otherBundleIDs: Set(otherBundleIDs.map(folded)).subtracting([bundleID].compactMap { $0 }),
            names: names,
            bundleURL: target.bundleURL.standardizedFileURL)
    }

    /// 名称必须通过的关卡：长度足够、不是 macOS 目录名、且未被其他 App 占用。
    static func safeNames(
        displayName: String, bundleName: String?, otherAppNames: [String]
    ) -> [String] {
        let taken = Set(otherAppNames.map(folded))
        var result: [String] = []
        for candidate in [displayName, bundleName].compactMap({ $0 }) {
            let name = folded(candidate)
            guard name.count >= minimumNameLength, !reservedNames.contains(name),
                !taken.contains(name), !result.contains(name)
            else { continue }
            result.append(name)
        }
        return result
    }

    /// 去掉首尾空白，并做大小写与变音符号不敏感的折叠。
    static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
