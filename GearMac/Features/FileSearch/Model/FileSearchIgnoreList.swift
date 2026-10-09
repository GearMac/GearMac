// 文件职责：实现 gitignore 风格的忽略列表，把用户与内置模式编译为字面名集合、名称 glob、路径 glob，用于排除搜索结果。
// 分层：Model；纯计算，依赖 Darwin 的 fnmatch，不引入副作用。
import Darwin
import Foundation

/// gitignore 风格：不含 `/` 的模式匹配任意路径分段，含 `/` 的模式匹配整条路径。
struct FileSearchIgnoreList: Sendable, Equatable {
    /// 在代码中内置而非存储，因此调整内置规则即可对已安装的版本生效。
    static let defaults = ["node_modules", "DerivedData", "build", "dist", "target", "Pods"]

    private let literalNames: Set<String>
    private let nameGlobs: [Glob]
    private let pathGlobs: [Glob]

    /// 把每条模式分类编译为字面名、名称 glob 或路径 glob。
    init(patterns: [String]) {
        var literalNames: Set<String> = []
        var nameGlobs: [Glob] = []
        var pathGlobs: [Glob] = []
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            // 模式中间的 NUL 会在传给 `fnmatch` 时被静默截断，因此直接丢弃。
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { continue }
            if trimmed.contains("/") {
                pathGlobs.append(Glob(trimmed))
            } else if trimmed.contains(where: Glob.isMetacharacter) {
                nameGlobs.append(Glob(trimmed))
            } else {
                literalNames.insert(trimmed.lowercased())
            }
        }
        self.literalNames = literalNames
        self.nameGlobs = nameGlobs
        self.pathGlobs = pathGlobs
    }

    /// 判断某条路径是否命中任意忽略规则（逐段匹配名称，最后整条匹配路径）。
    func excludes(path: String) -> Bool {
        for component in path.split(separator: "/") {
            let name = String(component)
            if literalNames.contains(name.lowercased()) { return true }
            if nameGlobs.contains(where: { $0.matches(name) }) { return true }
        }
        return pathGlobs.contains { $0.matches(path) }
    }

    /// 可由 Spotlight 自行求值的名称 glob，使被忽略的文件不会占用候选数量上限。
    var spotlightNameExclusions: [String] {
        nameGlobs.filter(\.isSpotlightExpressible).map(\.pattern)
    }
}

/// 一个已编译的模式；`fnmatch` 未启用 `FNM_PATHNAME`，因此 `*` 可以跨越 `/`。
private struct Glob: Sendable, Equatable {
    let pattern: String
    private let terminated: ContiguousArray<CChar>

    init(_ pattern: String) {
        self.pattern = pattern
        terminated = pattern.utf8CString
    }

    static func isMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    /// Spotlight 把 `?` 与 `[` 当作字面字符、只认识 `*`，因此含其他元字符的模式只能在本地匹配。
    var isSpotlightExpressible: Bool {
        !pattern.contains(where: { $0 == "?" || $0 == "[" || $0 == "\"" || $0 == "\\" })
    }

    /// 用 `fnmatch`（忽略大小写）判断候选字符串是否命中模式。
    func matches(_ candidate: String) -> Bool {
        terminated.withUnsafeBufferPointer { pattern in
            candidate.withCString { fnmatch(pattern.baseAddress!, $0, FNM_CASEFOLD) == 0 }
        }
    }
}
