// 文件职责：仅凭名称判断哪些目录条目属于某个 App 的匹配规则。
// 分层：Model（Uninstall）；纯字符串与路径匹配，不做文件系统访问。
import Foundation

/// 仅凭名称判断哪些目录条目属于某个 App。详见 docs/features/uninstall.md。
enum UninstallRules {
    /// 匹配前会去掉这些后缀，使 `com.foo.Bar.plist` 按 `com.foo.Bar` 比较。
    static let strippedExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "lockfile", "lock", "sfl", "sfl2", "sfl3",
        // 插件包装类型，按安装它们的产物命名。
        "qlgenerator", "saver", "prefpane", "service", "workflow", "mdimporter", "appex",
        "component", "wdgt", "dext", "driver"
    ]

    /// 返回名称及其各种去后缀形式；去后缀只会增加比较对象，不会减少。
    static func matchableForms(_ name: String) -> [String] {
        var forms = [name]
        var current = name
        for _ in 0..<3 {
            let ext = (current as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, strippedExtensions.contains(ext) else { break }
            let stripped = (current as NSString).deletingPathExtension
            guard !stripped.isEmpty else { break }
            forms.append(stripped)
            current = stripped
        }
        return forms
    }

    /// `-` 也算命名空间分隔符：厂商常这样命名变体，除非该变体本身也已安装。
    private static let namespaceSeparators: Set<Character> = [".", "-"]

    /// 匹配该 bundle ID 本身，或它的命名空间子项。
    static func matchesBundleID(_ component: String, identity: UninstallIdentity) -> Bool {
        guard let id = identity.bundleID else { return false }
        return matchableForms(component).contains { form in
            let folded = UninstallIdentity.folded(form)
            guard owns(folded, id: id, allowingPrefix: identity.allowsBundleIDPrefixMatch)
            else { return false }
            // 更长 ID 的同族会持有自己的产物，避免不同渠道互相认领。
            return !identity.otherBundleIDs.contains { other in
                other.count > id.count && owns(folded, id: other, allowingPrefix: true)
            }
        }
    }

    /// 判断折叠后的名称是否归属给定 bundle ID（可选允许命名空间前缀匹配）。
    private static func owns(_ folded: String, id: String, allowingPrefix: Bool) -> Bool {
        if folded == id { return true }
        guard allowingPrefix, folded.count > id.count, folded.hasPrefix(id) else { return false }
        // 要求分隔符可避免 `com.apple.SafariTechnologyPreview` 被当作 Safari 的子项。
        return namespaceSeparators.contains(folded[folded.index(folded.startIndex, offsetBy: id.count)])
    }

    /// 按链接目标判定归属，绝不按名称——名称只是厂商随手取的。
    static func isBundleSymlink(target: String, bundlePath: String) -> Bool {
        let target = (target as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        return target == bundlePath || isDescendant(target, of: bundlePath)
    }

    /// 去掉开头的 `group.` 和/或 Team ID；严格的 10 字符形状可避免误判。
    static func groupContainerBase(_ component: String) -> String {
        var base = component
        for _ in 0..<2 {
            if base.lowercased().hasPrefix("group.") {
                base = String(base.dropFirst("group.".count))
                continue
            }
            guard let dot = base.firstIndex(of: "."), isTeamID(String(base[base.startIndex..<dot]))
            else { break }
            base = String(base[base.index(after: dot)...])
        }
        return base
    }

    /// 判断是否为 Apple Team ID 的严格形状（10 位大写字母或数字）。
    static func isTeamID(_ value: String) -> Bool {
        value.count == 10
            && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) && !$0.isLowercase }
    }

    /// 先剥离 `group.` 前缀与 Team ID，再按 bundle ID 规则匹配。
    static func matchesGroupContainer(_ component: String, identity: UninstallIdentity) -> Bool {
        matchesBundleID(groupContainerBase(component), identity: identity)
    }

    /// 折叠后精确相等：不做前缀或子串匹配，避免 “Books” 认领 “Books Reader”。
    static func matchesDisplayName(_ component: String, identity: UninstallIdentity) -> Bool {
        guard !identity.names.isEmpty else { return false }
        return matchableForms(component).contains { form in
            identity.names.contains(UninstallIdentity.folded(form))
        }
    }

    /// 在给定搜索根下，按该根允许的匹配方式为条目名判定证据类型。
    static func evidence(
        for name: String, in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> UninstallEvidence? {
        if root.styles.contains(.bundleID), matchesBundleID(name, identity: identity) {
            return .bundleID
        }
        if root.styles.contains(.groupContainer), matchesGroupContainer(name, identity: identity) {
            return .groupContainer
        }
        if root.styles.contains(.displayName), matchesDisplayName(name, identity: identity) {
            return .displayName
        }
        return nil
    }

    /// 批量筛选出同根下可归属目标的子条目及其证据。
    static func matches(
        childNames: [String], in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> [(name: String, evidence: UninstallEvidence)] {
        childNames.compactMap { name in
            evidence(for: name, in: root, identity: identity).map { (name, $0) }
        }
    }

    /// 对每个产出的路径做双重校验，无论它由哪种方式匹配而来。
    static func isAcceptableCandidate(
        path: String, rootPath: String, home: String, bundlePath: String
    ) -> Bool {
        let path = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/", path != home, path != rootPath else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..")
        else { return false }
        guard (path as NSString).deletingLastPathComponent == rootPath else { return false }
        guard path != bundlePath, !isDescendant(path, of: bundlePath),
            !isDescendant(bundlePath, of: path)
        else { return false }
        return true
    }

    /// 判断 `path` 是否位于 `ancestor` 之下。
    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor + "/")
    }

    /// 由参数传入 `home` 而不是自行读取，以保持纯函数。
    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard isDescendant(path, of: home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
