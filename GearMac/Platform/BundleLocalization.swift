// 文件职责：枚举并汇总某个 bundle 在多种语言下声明的应用名称（含 loctable 与 InfoPlist.strings 本地化）。
// 分层：Service；纯读 plist 资源，不依赖 AppKit/SwiftUI。
import Foundation

/// 某个 bundle 在本机可读的多种语言下的名称；只看 `CFBundle` 会漏掉所有带 loctable 的应用。
enum BundleLocalization {
    /// 首选语言在前、英语在外：只懂泰语的用户仍然会输入 “Calendar”。
    nonisolated static func indexedLanguages(_ preferred: [String]) -> [String] {
        var codes: [String] = []
        var seen = Set<String>()
        for tag in preferred + ["en"] {
            let bare = tag.split(separator: "-").first.map(String.init) ?? tag
            let aliases = resourceAlias(for: bare).map { [$0] } ?? []
            for form in [tag] + scriptForms(tag) + [bare] + aliases {
                // loctable 键名与 .lproj 文件夹用下划线，而语言标签用 “-”。
                let underscored = form.replacingOccurrences(of: "-", with: "_")
                for code in [form, underscored]
                where !code.isEmpty && seen.insert(code).inserted {
                    codes.append(code)
                }
            }
        }
        return codes
    }

    /// 返回语言代码的资源别名（如 `nb` → `no`），无别名时返回 nil。
    private static func resourceAlias(for language: String) -> String? {
        language == "nb" ? "no" : nil
    }

    /// 多数应用用 `zh-Hans` 这类带书写系统的标签；Apple 只按地区索引，即 `zh_CN`。
    private static func scriptForms(_ tag: String) -> [String] {
        let subtags = tag.split(separator: "-")
        guard subtags.contains(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) })
        else { return [] }
        let language = Locale.Language(identifier: tag)
        guard let code = language.languageCode?.identifier else { return [] }
        let region =
            language.region ?? Locale.Language(identifier: language.maximalIdentifier).region
        return [language.script?.identifier, region?.identifier].compactMap { $0 }
            .map { "\(code)-\($0)" }
    }

    /// 返回 bundle 携带的所有名称，首选语言排在最前。`base`——应用的文件名、面板的 `Info.plist`——
    /// 与它所用语言同级别，除非该语言重命名了它。
    nonisolated static func names(
        for bundleURL: URL, base: String, developmentRegion: String?, languages: [String]
    ) -> [String] {
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let table = plist(at: resources.appendingPathComponent("InfoPlist.loctable"))
        let development = developmentRegion.flatMap { languageCode(of: $0) }
        let developmentAlias = development.flatMap { resourceAlias(for: $0) }
        let developmentFallback = languages.last { code in
            guard let development else { return false }
            return code.caseInsensitiveCompare(development) == .orderedSame
                || code == developmentAlias
        }
        var result: [String] = []
        var seen = Set<String>()
        var isBaseRenamed = false

        func append(_ name: String) {
            guard seen.insert(FuzzyMatch.normalized(name)).inserted else { return }
            result.append(name)
        }

        for code in languages {
            let strings = plist(
                at: resources.appendingPathComponent("\(code).lproj/InfoPlist.strings"))
            let translated = [table?[code] as? [String: Any], strings]
                .compactMap { $0.flatMap(AppDisplayName.inInfo) }
            translated.forEach(append)
            if let development,
                code.caseInsensitiveCompare(development) == .orderedSame || code == developmentAlias
            {
                if !translated.isEmpty { isBaseRenamed = true }
                if code == developmentFallback && !isBaseRenamed { append(base) }
            }
        }
        // 本机读不懂的开发地区语言，仍会让名称保持可搜索。
        if !isBaseRenamed { append(base) }
        return result
    }

    /// `CFBundleDevelopmentRegion` 仍沿用 BCP-47 之前的拼写：Safari 的值就是 “English”。
    private static func languageCode(of region: String) -> String? {
        Locale.Language(identifier: Locale.canonicalLanguageIdentifier(from: region))
            .languageCode?.identifier
    }

    /// 读取指定路径的 plist 文件，失败时返回 nil。
    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
