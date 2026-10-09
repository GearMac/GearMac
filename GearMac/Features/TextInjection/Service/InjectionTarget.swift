// 文件职责：描述注入文本的落点——通过事件写入其他 App，或在同进程内写入 GearMac 自己的编辑器。
// 分层：Service（TextInjection）；依赖 AppKit 与 NSRunningApplication，Model 层不得引用。
import AppKit

/// 注入文本的目标——另一个 App（走事件），或自家编辑器（走进程内写入）。
enum InjectionTarget {
    case external(NSRunningApplication)
    case ownEditor(any InjectableTextView)

    /// 按键真正的落点：GearMac 的面板从不激活，因此最前台 App 并不等于落点。
    @MainActor
    static func current() -> InjectionTarget? {
        guard let keyWindow = NSApp.keyWindow else {
            return NSWorkspace.shared.frontmostApplication.map(InjectionTarget.external)
        }
        return (keyWindow.firstResponder as? any InjectableTextView).map(InjectionTarget.ownEditor)
    }

    /// 面板被唤起时所覆盖的内容：自家编辑器，或它背后的那个 App。
    @MainActor
    static func behindPalette(
        ownWindow: NSWindow?, app: NSRunningApplication?
    ) -> InjectionTarget? {
        if let editor = ownWindow?.firstResponder as? any InjectableTextView {
            return .ownEditor(editor)
        }
        return app.map(InjectionTarget.external)
    }

    /// 把光标交还回去——用于模态参数提示之后，或某次未能落地的展开之后。
    @MainActor
    func restoreFocus() {
        switch self {
        case .external(let app):
            guard !app.isTerminated else { return }
            app.activate()
        case .ownEditor(let editor):
            editor.window?.makeFirstResponder(editor)
        }
    }

    /// 落点为外部 App 时返回该 App，否则为 nil。
    var externalApp: NSRunningApplication? {
        guard case .external(let app) = self else { return nil }
        return app
    }

    /// 落点为自家编辑器时返回该视图，否则为 nil。
    var ownEditor: (any InjectableTextView)? {
        guard case .ownEditor(let editor) = self else { return nil }
        return editor
    }
}
