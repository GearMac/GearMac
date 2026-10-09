// 文件职责：在一次召唤面板期间把键盘输入源保持为偏好输入源，并在结束时恢复用户原来的输入源。
// 分层：Service；@MainActor，仅在会话期间修改输入源，不持有跨会话状态。
import AppKit
import Carbon.HIToolbox

/// 在一次召唤的生命周期内，把键盘输入源保持在面板偏好的那个。
@MainActor
final class InputSourceSwitcher {
    /// 供设置页下拉选择的一个输入源选项。
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    /// 由 TIS 在系统设置中添加或移除键盘输入源时发布。
    static let sourcesDidChange = Notification.Name(
        kTISNotifyEnabledKeyboardInputSourcesChanged as String)

    /// 待恢复的输入源保留为 TIS 返回的对象，隐藏时无需重新读取列表。
    private struct Session {
        let previousSource: TISInputSource
        let preferredInputSourceID: String
        var applied = false
    }

    private var session: Session?

    /// 已被移除的 `selected` 输入源仍会列出，使设置页能继续显示它。
    func options(selecting selected: String?) -> [Option] {
        var options = Self.enabledKeyboardSources().compactMap(Self.option(for:))
        if let selected, !options.contains(where: { $0.id == selected }) {
            options.append(Option(id: selected, title: selected))
        }
        return options
    }

    /// 记录需要恢复的目标；偏好输入源已是当前输入源时跳过。
    func beginSession(preferredInputSourceID: String?) {
        guard session == nil, let preferredInputSourceID,
            let current = Self.currentSource(),
            Self.identifier(of: current) != preferredInputSourceID
        else { return }
        session = Session(previousSource: current, preferredInputSourceID: preferredInputSourceID)
    }

    /// 通过输入框自身的输入上下文切换，使切换跟随面板的焦点。
    func applySession(to inputContext: NSTextInputContext) {
        guard let session, !session.applied else { return }
        inputContext.selectedKeyboardInputSource = session.preferredInputSourceID
        self.session?.applied = true
    }

    /// 只撤销我们自己做的切换：此后由用户或其他应用选中的输入源保持不变。
    func endSession() {
        guard let session else { return }
        self.session = nil
        guard session.applied, let current = Self.currentSource(),
            Self.identifier(of: current) == session.preferredInputSourceID
        else { return }
        TISSelectInputSource(session.previousSource)
    }

    /// 返回当前键盘输入源。
    private static func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    /// 把 TIS 输入源转换为设置页选项。
    private static func option(for source: TISInputSource) -> Option? {
        guard let id = identifier(of: source),
            let title: String = property(kTISPropertyLocalizedName, of: source)
        else { return nil }
        return Option(id: id, title: title)
    }

    /// 读取输入源的标识符。
    private static func identifier(of source: TISInputSource) -> String? {
        property(kTISPropertyInputSourceID, of: source)
    }

    /// 列出所有可选的键盘输入源。
    private static func enabledKeyboardSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        var sources: [TISInputSource] = []
        for case let source as TISInputSource in list as NSArray where isSelectableKeyboard(source) {
            sources.append(source)
        }
        return sources
    }

    /// 判断输入源是否为可选择的键盘源。
    private static func isSelectableKeyboard(_ source: TISInputSource) -> Bool {
        let category: String? = property(kTISPropertyInputSourceCategory, of: source)
        return category == kTISCategoryKeyboardInputSource as String
            && property(kTISPropertyInputSourceIsSelectCapable, of: source) == true
    }

    /// TIS 返回的是无类型指针，类型不符时视为不存在，而不是触发陷阱。
    private static func property<Value>(_ key: CFString, of source: TISInputSource) -> Value? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? Value
    }
}
