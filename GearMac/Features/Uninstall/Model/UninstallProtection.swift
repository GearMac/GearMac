// 文件职责：判定某个路径能否被移入废纸篓的保护规则，以及判定所需的事实结构。
// 分层：Model（Uninstall）；纯判定逻辑，不做文件系统探测，事实由调用方注入。
import Foundation

/// 分类器可以知道的关于某路径的全部事实；由调用方注入以保持纯函数。
struct PathFacts: Hashable, Sendable {
    let path: String
    var exists = true
    /// 绝不跟随：穿过符号链接计算体积可能遍历整个磁盘。
    var isSymbolicLink = false
    var volumeIsReadOnly = false
    /// `SF_RESTRICTED` / `SF_IMMUTABLE`——SIP 系统保护。
    var isSystemRestricted = false
    /// `UF_IMMUTABLE`——Finder 的「已锁定」复选框，用户可自行解除。
    var isUserImmutable = false
    /// 仅在粘滞位父目录下才起作用——见 `classify`。
    var isOwnedByCurrentUser = true
    var parentIsWritable = true
    /// 父目录带 `S_ISVTX`（粘滞位）：即 `/tmp` 规则，只有属主才能删除其中的条目。
    var parentIsSticky = false
}

/// 进程级事实，每次扫描探测一次，而不是每个候选都探测。
struct UninstallEnvironment: Hashable, Sendable {
    let home: String
    let hasFullDiskAccess: Bool
}

/// 候选为何能被或不能被移入废纸篓。仅供参考：TCC 在系统调用时才会真正判定。
enum UninstallProtection: String, Hashable, Sendable, CaseIterable {
    case removable
    case systemProtected
    case userLocked
    case notOwned
    case needsFullDiskAccess
    case parentNotWritable
    case missing

    var isRemovable: Bool { self == .removable }

    /// 仅 `.removable` 时为 nil；列表行的锁图标据此显示。仅为无语言上下文的调用方保留。
    var lockReason: String? { localizedLockReason(.english) }

    /// 锁原因：仅 `.removable` 时为 nil；列表行的锁图标据此显示。
    func localizedLockReason(_ language: AppLanguage) -> String? {
        switch self {
        case .removable:
            return nil
        case .systemProtected:
            return L10n.string(UninstallKey.protectionSystemProtected, language: language)
        case .userLocked:
            return L10n.string(UninstallKey.protectionUserLocked, language: language)
        case .notOwned:
            return L10n.string(UninstallKey.protectionNotOwned, language: language)
        case .needsFullDiskAccess:
            return L10n.string(UninstallKey.protectionNeedsFullDiskAccess, language: language)
        case .parentNotWritable:
            return L10n.string(UninstallKey.protectionParentNotWritable, language: language)
        case .missing:
            return L10n.string(UninstallKey.protectionMissing, language: language)
        }
    }
}

/// 根据 `PathFacts` 与 `UninstallEnvironment` 判定候选保护级别的纯规则集。
enum UninstallProtectionRules {
    /// 判定顺序是刻意固定的：SIP 文件同时属 root 所有，而「属于 macOS 的一部分」对用户更易理解。
    static func classify(_ facts: PathFacts, environment: UninstallEnvironment) -> UninstallProtection {
        guard facts.exists else { return .missing }
        if facts.isSystemRestricted || facts.volumeIsReadOnly { return .systemProtected }
        if facts.isUserImmutable { return .userLocked }
        if !environment.hasFullDiskAccess,
            isTCCProtected(path: facts.path, home: environment.home)
        {
            return .needsFullDiskAccess
        }
        // 移入废纸篓本质上是从父目录中改名移出，因此取决于父目录的写权限，而非条目属主。
        if !facts.parentIsWritable { return .parentNotWritable }
        // 唯一由属主决定的场景：粘滞位父目录只允许属主移除其中的条目。
        if facts.parentIsSticky, !facts.isOwnedByCurrentUser { return .notOwned }
        return .removable
    }

    /// 范围比当前搜索根更宽，避免将来新增搜索根时无声地尝试一次会被拒绝的读取。
    static func isTCCProtected(path: String, home: String) -> Bool {
        let relative = tccRelativePrefixes.contains { path.hasPrefix(home + "/" + $0) }
        return relative || path.hasPrefix("/Library/Application Support/com.apple.TCC")
    }

    /// 实测而非假设：能否列目录并不是判定标准。详见 docs/features/uninstall.md。
    static let tccRelativePrefixes: [String] = [
        "Library/Containers/",
        "Library/Group Containers/",
        "Library/Cookies/",
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Calendars",
        "Library/Suggestions",
        "Library/HomeKit",
        "Library/IdentityServices",
        "Library/Sharing",
        "Library/Biome",
        "Library/Trial",
        "Library/Metadata/CoreSpotlight",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/MobileSync"
    ]
}
