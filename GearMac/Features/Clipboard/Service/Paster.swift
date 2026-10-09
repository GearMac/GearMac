// 文件职责：把剪贴板条目写入系统粘贴板并合成 ⌘V/⌘C 完成粘贴或复制，支持激活目标应用或在原位粘贴。
// 分层：Service；@MainActor，所有方法操作 NSPasteboard 与合成按键事件。
import AppKit
import Carbon.HIToolbox

/// 粘贴服务：负责把条目写入粘贴板并合成复制/粘贴按键。
enum Paster {
    /// 打在 GearMac 自身合成的按键事件上，使片段关键词监听可以跳过它们。
    static let gearmacEventTag: Int64 = 0x54494E59

    /// 覆盖 `activate()` 返回到目标应用接受按键之间的间隔。
    private static let activationDelay: TimeInterval = 0.08

    /// 更短：无需等待激活，只需等待粘贴板写入到达目标进程。
    private static let directPostDelay: TimeInterval = 0.05

    /// 写入条目并粘贴到 `previousApp`，先激活它以确保 ⌘V 落到该应用。
    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
        return true
    }

    /// 只粘贴条目的文本，使文件以其路径形式到达，并采用接收方的样式。
    @MainActor @discardableResult
    static func pastePlainText(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard let text = item.plainText else { return false }
        pasteString(text, previousApp: previousApp)
        store.promote(item)
        return true
    }

    /// 只把条目放入粘贴板而不粘贴；标记会阻止再次捕获。
    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        return true
    }

    /// 不加标记地把字符串放入粘贴板，使其像普通复制一样进入历史。
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// `paste` 的字符串版本，带标记以免文本再次进入历史。
    @MainActor
    static func pasteString(_ text: String, previousApp: NSRunningApplication?) {
        writeString(text)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
    }

    /// 把文件粘贴到 `previousApp`；接收方按自身能力接收文件或其路径。
    @MainActor
    static func pasteFile(_ url: URL, previousApp: NSRunningApplication?) {
        PasteboardFiles.write(url, to: .general)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
    }

    /// `copy(_:store:)` 的字符串版本。
    @MainActor
    static func copyString(_ text: String) {
        writeString(text)
    }

    /// `pasteInPlace` 的字符串版本；面板保持在前台。
    @MainActor
    static func pasteStringInPlace(_ text: String, into app: NSRunningApplication?) {
        writeString(text)
        guard let pid = app?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
            postCommandV(toPid: pid)
        }
    }

    /// 把字符串写入粘贴板并附上内部标记。
    @MainActor
    private static func writeString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    /// 粘贴到 `app` 但不激活、不提升，使面板及其行保持不动。
    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
                postCommandV(toPid: pid)
            }
        }
        return true
    }

    /// 返回是否写入了内容；条目已消失时不动粘贴板。
    @MainActor @discardableResult
    static func write(
        _ item: ClipboardItem, store: ClipboardStore, to pb: NSPasteboard = .general
    ) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pb.clearContents()
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else {
                return false
            }
            pb.clearContents()
            pb.declareTypes([.png, ClipboardManager.internalType], owner: nil)
            pb.setData(data, forType: .png)
        case .file:
            guard let url = store.fileURL(for: item),
                FileManager.default.fileExists(atPath: url.path)
            else { return false }
            pb.clearContents()
            pb.declareTypes([.fileURL, .string, ClipboardManager.internalType], owner: nil)
            pb.setData(url.dataRepresentation, forType: .fileURL)
            // 同时写入两种类型：接收文件的应用拿到文件，文本框拿到路径。
            pb.setString(url.path, forType: .string)
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        return true
    }

    /// 合成 ⌘V：给定 `pid` 时只发给该进程，否则通过系统事件 tap 发送。
    @MainActor
    static func postCommandV(toPid pid: pid_t? = nil) {
        postCommand(key: CGKeyCode(kVK_ANSI_V), toPid: pid)
    }

    /// 合成 ⌘C，用于读取应用无法通过辅助功能暴露的选中内容。
    @MainActor
    static func postCommandC(toPid pid: pid_t? = nil) {
        postCommand(key: CGKeyCode(kVK_ANSI_C), toPid: pid)
    }

    /// 以 ⌘ 修饰合成指定按键，发送给指定 pid 或通过系统事件 tap 发送。
    @MainActor
    private static func postCommand(key: CGKeyCode, toPid pid: pid_t?) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: gearmacEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: gearmacEventTag)

        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
