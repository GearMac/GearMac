// 文件职责：定义用户自建快捷动作的数据结构及其校验错误类型。
// 分层：Model；纯数据结构，不依赖 AppKit/SwiftUI。
import Foundation

/// 用户自建的快捷动作，持久化为 JSON。
struct CustomQuickAction: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "quick-action:"
    static let sfSymbol = "wand.and.stars"

    let id: UUID
    var name: String
    var iconSymbol: String?
    var instructions: String
    var previewsResult: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, iconSymbol: String? = nil, instructions: String,
        previewsResult: Bool = true, createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.instructions = instructions
        self.previewsResult = previewsResult
        self.createdAt = createdAt
    }

    /// 展示用图标：未自定义时回退到默认 SF Symbol。
    var symbol: String { iconSymbol ?? Self.sfSymbol }

    /// 启动器条目的稳定 ID，以 `entryIDPrefix` 前缀区分自建动作。
    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// 从启动器条目 ID 反解出动作 UUID；前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// 排序规则：先按创建时间，时间相同的按 UUID 字符串保证稳定序。
    static func precedes(_ lhs: CustomQuickAction, _ rhs: CustomQuickAction) -> Bool {
        lhs.createdAt != rhs.createdAt
            ? lhs.createdAt < rhs.createdAt
            : lhs.id.uuidString < rhs.id.uuidString
    }
}

/// 自建快捷动作在创建/编辑/持久化时可报出的错误。
enum CustomQuickActionError: Error, LocalizedError, Equatable {
    case emptyName
    case emptyInstructions
    case invalidCharacter
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the action a name."
        case .emptyInstructions: return "Tell the model what the action should do."
        case .invalidCharacter: return "The name contains a character GearMac can't store."
        case .storageUnavailable: return "GearMac couldn't save to its actions file."
        }
    }

    /// 按界面语言解析的面向用户错误描述。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName:
            return L10n.string(QuickActionsKey.errorEmptyName, language: language)
        case .emptyInstructions:
            return L10n.string(QuickActionsKey.errorEmptyInstructions, language: language)
        case .invalidCharacter:
            return L10n.string(QuickActionsKey.errorInvalidCharacter, language: language)
        case .storageUnavailable:
            return L10n.string(QuickActionsKey.errorStorageUnavailable, language: language)
        }
    }
}
