// 文件职责：定义自定义命令（CustomCommand）及其位置参数（CustomCommandArgument）的数据模型与校验规则，并提供基于 UserDefaults 的持久化存储 CustomCommandStore。
// 分层：Model；只依赖 Foundation，不 import AppKit/SwiftUI，通过 onChange 回调向上层通知变更。
import Foundation

/// 自定义命令的一个位置参数；取值按位置传入，因此用户输入的内容不会被 zsh 重新解析。
struct CustomCommandArgument: Codable, Hashable, Sendable {
    var name: String
    /// 可选参数允许留空提交；必填参数在填值之前会一直保持 ↵ 提示。
    var isOptional: Bool

    /// 创建位置参数；`isOptional` 默认为 false，即必填。
    init(name: String, isOptional: Bool = false) {
        self.name = name
        self.isOptional = isOptional
    }

    /// 参数数量上限，沿用 Raycast 的限制，也保证搜索框旁的 inline 输入框能排得下。
    static let limit = 3

    /// 承载 `$n` 的 inline 输入框标识；按位置生成，因为两个参数可能同名。
    static func fieldID(at index: Int) -> String { "$\(index + 1)" }

    /// 名称为空的参数直接丢弃而不是报错，避免一次导入因个别条目而整批失败。
    static func sanitized(_ arguments: [CustomCommandArgument]) -> [CustomCommandArgument] {
        let cleaned = arguments.compactMap { argument -> CustomCommandArgument? in
            var cleaned = argument
            cleaned.name = argument.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0") else { return nil }
            return cleaned
        }
        return Array(cleaned.prefix(limit))
    }
}

/// 一条用户自定义的 shell 命令，包含展示信息、运行选项与位置参数定义。
struct CustomCommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "custom-command:"
    /// 所有自定义命令共用的默认图标，让各处的呈现保持一致。
    static let sfSymbol = "terminal"

    let id: UUID
    var name: String
    var command: String
    /// 关闭后命令及其所有关联配置都保留，但任何入口都不会展示或运行它。
    var isEnabled: Bool
    /// 是否加载 shell 配置以解析别名；默认关闭，配置较重时启动会更慢。
    var loadsShellEnvironment: Bool
    var requiresConfirmation: Bool
    var showsConfirmation: Bool
    /// 在启动器行的 inline 输入框中填写；不接受输入的命令为空数组。
    var arguments: [CustomCommandArgument]
    /// 是否捕获命令输出，并在其结束后打开输出窗口。
    var showsOutput: Bool
    /// 保持缩写形式（如 `~`），这样用户目录迁移后路径依然有效。
    var workingDirectory: String?
    /// 启动器图标；为 nil 时回退到共用的默认终端图标。
    var iconSymbol: String?

    /// 创建一条自定义命令；除名称与命令内容外的选项都带默认值。
    init(
        id: UUID = UUID(), name: String, command: String, isEnabled: Bool = true,
        loadsShellEnvironment: Bool = false, requiresConfirmation: Bool = false,
        showsConfirmation: Bool = false, arguments: [CustomCommandArgument] = [],
        showsOutput: Bool = false, workingDirectory: String? = nil, iconSymbol: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.loadsShellEnvironment = loadsShellEnvironment
        self.requiresConfirmation = requiresConfirmation
        self.showsConfirmation = showsConfirmation
        self.arguments = arguments
        self.showsOutput = showsOutput
        self.workingDirectory = workingDirectory
        self.iconSymbol = iconSymbol
    }

    /// 各处为该命令绘制的图标。
    var symbol: String { iconSymbol ?? Self.sfSymbol }

    /// 该命令在启动器中的条目 ID，由固定前缀加小写 UUID 组成。
    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// 按 `$n` 顺序返回参数取值（以 `fieldID(at:)` 为键）；任一必填参数为空时返回 nil。
    func positionalValues(from values: [String: String]) -> [String]? {
        let positional = arguments.indices.map {
            values[CustomCommandArgument.fieldID(at: $0)] ?? ""
        }
        let complete = zip(arguments, positional).allSatisfy { $0.isOptional || !$1.isEmpty }
        return complete ? positional : nil
    }

    /// 从条目 ID 反解出命令 UUID；前缀不匹配时返回 nil。
    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    // 手写 CodingKeys 并配合 decodeIfPresent，保证新增字段后已存储的命令与旧备份仍可解码。
    private enum CodingKeys: String, CodingKey {
        case id, name, command, isEnabled, loadsShellEnvironment, requiresConfirmation
        case showsConfirmation, arguments, showsOutput, workingDirectory, iconSymbol
    }

    /// 解码时对缺失字段使用默认值，以兼容旧版本存储或备份。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        loadsShellEnvironment =
            try container.decodeIfPresent(Bool.self, forKey: .loadsShellEnvironment) ?? false
        requiresConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        showsConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .showsConfirmation) ?? false
        arguments =
            try container.decodeIfPresent([CustomCommandArgument].self, forKey: .arguments) ?? []
        showsOutput = try container.decodeIfPresent(Bool.self, forKey: .showsOutput) ?? false
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
    }
}

extension String {
    /// 去除首尾空白；去完为空则返回 nil——可选字段留空表示「未设置」而非空字符串。
    fileprivate var cleanedPathComponent: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("\0") ? nil : trimmed
    }
}

/// 自定义命令校验失败的原因，附带面向用户的错误文案。
enum CustomCommandValidationError: LocalizedError {
    case emptyName
    case emptyCommand
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the command."
        case .emptyCommand: return "Enter a command to run."
        case .duplicateName: return "A custom command with this name already exists."
        case .invalidCharacter: return "Names and commands cannot contain null characters."
        }
    }

    /// 按界面语言解析的面向用户错误描述。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .emptyName: return L10n.string(CustomCommandsKey.errorEmptyName, language: language)
        case .emptyCommand:
            return L10n.string(CustomCommandsKey.errorEmptyCommand, language: language)
        case .duplicateName:
            return L10n.string(CustomCommandsKey.errorDuplicateName, language: language)
        case .invalidCharacter:
            return L10n.string(CustomCommandsKey.errorInvalidCharacter, language: language)
        }
    }
}

/// 自定义命令库：负责加载、校验与持久化命令列表，并通过 `onChange` 通知外部变更。
@MainActor
@Observable
final class CustomCommandStore {
    private static let defaultsKey = "customCommands"

    private let defaults: UserDefaults
    /// 当前命令列表，对外只读。
    private(set) var commands: [CustomCommand]
    /// 列表变化后的回调，用于驱动外部（如启动器索引）刷新。
    @ObservationIgnored var onChange: (([CustomCommand]) -> Void)?

    /// 从 UserDefaults 读取并清洗已保存的命令；清洗结果不同时立即回写。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CustomCommand].self, from: $0) } ?? []
        commands = Self.sanitized(decoded)
        if commands != decoded { persist() }
    }

    /// 按 UUID 查找命令。
    func command(id: UUID) -> CustomCommand? {
        commands.first { $0.id == id }
    }

    /// 按启动器条目 ID 查找命令。
    func command(entryID: String) -> CustomCommand? {
        CustomCommand.id(fromEntryID: entryID).flatMap(command)
    }

    /// 校验后新增一条命令，返回实际写入的实例；接收完整草稿而非逐字段参数，新增选项时无需改动每个调用点。
    @discardableResult
    func add(_ draft: CustomCommand) throws -> CustomCommand {
        let value = try validated(draft, against: commands)
        commit(commands + [value])
        return value
    }

    /// 整批导入只提交一次，返回其中真正新增的条数。
    @discardableResult
    func add(contentsOf drafts: [CustomCommand]) -> Int {
        var updated = commands
        let existing = commands.count
        for draft in drafts {
            guard let value = try? validated(draft, against: updated) else { continue }
            updated.append(value)
        }
        commit(updated)
        return updated.count - existing
    }

    /// 校验后更新已存在的命令（按 id 匹配）；找不到对应命令时静默返回。
    func update(_ draft: CustomCommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft, against: commands)
        var updated = commands
        updated[index] = value
        commit(updated)
    }

    /// 设置命令的启用状态；状态未变化时不触发提交。
    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }),
            commands[index].isEnabled != enabled
        else { return }
        var updated = commands
        updated[index].isEnabled = enabled
        commit(updated)
    }

    /// 删除命令并返回被删除的实例；不存在时返回 nil。
    @discardableResult
    func remove(id: UUID) -> CustomCommand? {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = commands
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// 从备份导入时整体替换命令集，丢弃无效与重复的记录，返回保留的条数。
    @discardableResult
    func replace(with newCommands: [CustomCommand]) -> Int {
        let updated = Self.sanitized(newCommands)
        commit(updated)
        return updated.count
    }

    /// `existing` 是名称唯一性校验的比对集合：既可能是整个命令库，也可能是进行中的批次。
    private func validated(
        _ draft: CustomCommand, against existing: [CustomCommand]
    ) throws -> CustomCommand {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        value.arguments = CustomCommandArgument.sanitized(draft.arguments)
        value.workingDirectory = draft.workingDirectory?.cleanedPathComponent
        value.iconSymbol = draft.iconSymbol?.cleanedPathComponent
        guard !value.name.isEmpty else { throw CustomCommandValidationError.emptyName }
        guard !value.command.isEmpty else { throw CustomCommandValidationError.emptyCommand }
        guard !value.name.contains("\0"), !value.command.contains("\0") else {
            throw CustomCommandValidationError.invalidCharacter
        }
        guard
            !existing.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw CustomCommandValidationError.duplicateName }
        return value
    }

    /// 命令集确有变化时才更新内存状态、落盘并触发回调。
    private func commit(_ updated: [CustomCommand]) {
        guard updated != commands else { return }
        commands = updated
        persist()
        onChange?(updated)
    }

    /// 将当前命令列表编码后写入 UserDefaults。
    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [CustomCommand]) -> [CustomCommand] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [CustomCommand] = []
        for value in values {
            // 采用复制后清洗而非重新构造，保证新增的选项字段不会在导入时被丢弃。
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.command = value.command.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.arguments = CustomCommandArgument.sanitized(value.arguments)
            cleaned.workingDirectory = value.workingDirectory?.cleanedPathComponent
            cleaned.iconSymbol = value.iconSymbol?.cleanedPathComponent
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.command.isEmpty, !cleaned.name.contains("\0"),
                !cleaned.command.contains("\0"), ids.insert(cleaned.id).inserted,
                names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result
    }
}
