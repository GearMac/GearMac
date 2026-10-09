// 文件职责：Launcher 类别与回退项在界面上的本地化标签（键表见 Localization/LauncherKeys.swift）。
// 分层：Model；扩展 AppEntry 与 Fallback，使其显示名按当前语言解析。
import Foundation

extension AppEntry.Kind {
    /// 该类别在分组标题中使用的键。
    var sectionTitleKey: LauncherKey {
        switch self {
        case .application: return .kindApplicationSection
        case .systemSettings: return .kindSystemSettingsSection
        case .command: return .kindCommandSection
        case .quickAction: return .kindQuickActionSection
        case .customCommand: return .kindCustomCommandSection
        case .snippet: return .kindSnippetSection
        case .systemAction: return .kindSystemActionSection
        case .windowCommand: return .kindWindowCommandSection
        case .windowLayout: return .kindWindowLayoutSection
        case .windowRoom: return .kindRoomSection
        case .quicklink: return .kindQuicklinkSection
        case .appleShortcut: return .kindAppleShortcutSection
        case .extensionCommand: return .kindExtensionSection
        case .meeting: return .kindMeetingSection
        }
    }

    /// 该类别主操作（↵）使用的键。
    var openVerbKey: LauncherKey {
        switch self {
        case .application: return .kindApplicationVerb
        case .systemSettings: return .kindSystemSettingsVerb
        case .command: return .kindCommandVerb
        case .quickAction: return .kindQuickActionVerb
        case .customCommand: return .kindCustomCommandVerb
        case .snippet: return .kindSnippetVerb
        case .systemAction: return .kindSystemActionVerb
        case .windowCommand: return .kindWindowCommandVerb
        case .windowLayout: return .kindWindowLayoutVerb
        case .windowRoom: return .kindRoomVerb
        case .quicklink: return .kindQuicklinkVerb
        case .appleShortcut: return .kindAppleShortcutVerb
        case .extensionCommand: return .kindExtensionVerb
        case .meeting: return .kindMeetingVerb
        }
    }

    /// 该类别单数标签使用的键。
    var labelKey: LauncherKey {
        switch self {
        case .application: return .kindApplicationLabel
        case .systemSettings: return .kindSystemSettingsLabel
        case .command: return .kindCommandLabel
        case .quickAction: return .kindQuickActionLabel
        case .customCommand: return .kindCustomCommandLabel
        case .snippet: return .kindSnippetLabel
        case .systemAction: return .kindSystemActionLabel
        case .windowCommand: return .kindWindowCommandLabel
        case .windowLayout: return .kindWindowLayoutLabel
        case .windowRoom: return .kindRoomLabel
        case .quicklink: return .kindQuicklinkLabel
        case .appleShortcut: return .kindAppleShortcutLabel
        case .extensionCommand: return .kindExtensionLabel
        case .meeting: return .kindMeetingLabel
        }
    }
}

extension AppEntry {
    /// 行尾与副标题使用的类别标签；扩展命令等使用其来源名称。
    func kindLabel(_ language: AppLanguage) -> String {
        ownerName ?? L10n.string(kind.labelKey, language: language)
    }
}

extension Fallback {
    /// 底部胶囊与兜底菜单中描述 ↵ 动作的动词。
    func openVerb(_ language: AppLanguage) -> String {
        L10n.string(openVerbKey, language: language)
    }

    /// 该兜底项动词对应的本地化键。
    private var openVerbKey: LauncherKey {
        switch self {
        case .builtin(.quickAI): return .fallbackVerbQuickAI
        case .builtin(.searchFiles): return .fallbackVerbSearchFiles
        case .builtin(.runShellCommand): return .fallbackVerbRunShellCommand
        case .builtin(.define): return .fallbackVerbDefine
        case .quicklink: return .fallbackVerbQuicklink
        }
    }

    /// 兜底区块标题；过长查询沿用原有中间省略策略，仅有语言差异。
    static func sectionTitle(query: String, language: AppLanguage, limit: Int = 72) -> String {
        let format = L10n.string(LauncherKey.fallbackSectionTitleFormat, language: language)
        let shown =
            query.count > limit
            ? "\(query.prefix(limit / 2))…\(query.suffix(limit - limit / 2 - 1))" : query
        return String(format: format, shown)
    }
}
