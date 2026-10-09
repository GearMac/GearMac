// 文件职责：根据当前活动状态判断此刻是否可以安全地打断用户并替换应用。
// 分层：Model（纯逻辑，Sendable）；所有状态由外部注入，不做任何 I/O。
import Foundation

/// 应用当前正在进行的活动。所有标志位均由外部注入，使判断保持纯粹。
struct UpdateActivity: Sendable {
    var isExpandingSnippet = false
    var isRunningExtension = false
    var isUninstalling = false
    var isRecordingHotKey = false
    var isShowingDialog = false
    var isPaletteVisible = false
}

/// 判断此刻是否可以安全地打断用户并在其使用中替换应用。
enum UpdateReadiness {
    /// 阻止更新的具体原因。
    enum Blocker: Equatable, Sendable {
        case expandingSnippet
        case runningExtension
        case uninstalling
        case recordingHotKey
        case dialogOpen
        case paletteOpen

        /// 面向用户的阻塞原因说明。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .expandingSnippet: return L10n.string(UpdatesKey.blockerExpandingSnippet, language: language)
            case .runningExtension: return L10n.string(UpdatesKey.blockerRunningExtension, language: language)
            case .uninstalling: return L10n.string(UpdatesKey.blockerUninstalling, language: language)
            case .recordingHotKey: return L10n.string(UpdatesKey.blockerRecordingHotKey, language: language)
            case .dialogOpen: return L10n.string(UpdatesKey.blockerDialogOpen, language: language)
            case .paletteOpen: return L10n.string(UpdatesKey.blockerPaletteOpen, language: language)
            }
        }
    }

    /// 按后果轻重排序：打断安装会丢工作，而开着的面板不会。
    static func evaluate(_ activity: UpdateActivity) -> Blocker? {
        if activity.isExpandingSnippet { return .expandingSnippet }
        if activity.isRunningExtension { return .runningExtension }
        if activity.isUninstalling { return .uninstalling }
        if activity.isRecordingHotKey { return .recordingHotKey }
        if activity.isShowingDialog { return .dialogOpen }
        if activity.isPaletteVisible { return .paletteOpen }
        return nil
    }
}
