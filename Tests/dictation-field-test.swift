// 文件职责：Dictation 文本输入栏的集成测试 harness，用假 fixture 驱动真实的 DictationCoordinator 与 Composer 视图。
// 分层：测试 harness；只替换录音捕获、模型、面板等外部依赖以断言输入栏行为，不改动生产代码。

import AppKit
import SwiftUI

/// Dictation 文本输入栏测试入口，串行跑投递、作用域取消、聊天切换、关窗与排队取消等场景。
@main
@MainActor
struct DictationFieldTest {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try await testDelivery()
        try await testScopedCancellation()
        try await testChatSwitch()
        try await testWindowClose()
        try await testQueuedCancellation(closing: false)
        try await testQueuedCancellation(closing: true)
        print("ALL PASSED")
    }

    /// 校验两种快捷键模式下，字段录音的转写都会被插入编辑器，且不受「仅复制」目的地设置影响。
    private static func testDelivery() async throws {
        for mode in [DictationMode.toggle, .pushToTalk] {
            let fixture = Fixture()
            fixture.settings.dictationMode = mode
            let editor = ComposerTextView()
            try await fixture.start(into: editor)
            fixture.coordinator.toggle(into: editor)
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Spoken words")
            try await wait { fixture.coordinator.field == nil }
            expect(editor.string == "Spoken words", "Both shortcut modes insert the field's transcript")
            expect(Paster.copies.isEmpty, "A field mic ignores the copy-only destination setting")
        }
    }

    /// 校验取消只作用于所属编辑器：启动中的录音可被取消，无关编辑器无法取消当前会话。
    private static func testScopedCancellation() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        fixture.coordinator.toggle(into: editor)
        fixture.coordinator.cancel(in: editor)
        try await wait { fixture.capture.stopCount > 0 }
        expect(fixture.coordinator.field == nil, "Cancellation covers a recording still starting")
        expect(!fixture.capture.isRecording, "A canceled start cannot leave recording active")

        try await fixture.start(into: editor)
        fixture.coordinator.cancel(in: ComposerTextView())
        expect(fixture.capture.isRecording, "Another editor cannot cancel this session")
        expect(fixture.coordinator.field != nil, "Unrelated teardown preserves the field owner")
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
    }

    /// 校验切换聊天会取消旧会话的转写，且迟到的结果不会写入旧草稿或新聊天。
    private static func testChatSwitch() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let second = Draft("Second draft")
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        state.chat = second
        try await wait { surface.editor?.string == second.text }
        expect(surface.editor === editor, "Chat switching exercises the same reused editor")
        expect(fixture.coordinator.field == nil, "Rebinding cancels the old chat's transcription")
        fixture.models.finish("Late speech for the first chat")
        try await wait { fixture.models.finished }
        await fixture.queue.drain()
        expect(first.text == "First draft", "Canceled transcription leaves the original draft intact")
        expect(second.text == "Second draft", "Canceled transcription cannot enter the new chat")
        expect(fixture.messages.isEmpty, "Destination cancellation does not report an insertion error")
    }

    /// 校验关闭窗口会释放旧编辑器绑定与回调，重新打开应得到全新编辑器并可独立录音。
    private static func testWindowClose() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let surface = Surface(state: state, dictation: fixture.coordinator)
        try await wait { surface.editor != nil }
        let oldEditor = surface.editor!
        try await fixture.start(into: oldEditor)
        surface.close()
        try await wait { fixture.coordinator.field == nil && !fixture.capture.isRecording }
        expect(!oldEditor.isEditable, "Teardown rejects delayed in-process writes")
        expect(oldEditor.delegate == nil, "Teardown releases the old draft binding")
        expect(oldEditor.onDropFiles == nil, "Teardown releases attachment callbacks")

        let reopened = Surface(state: state, dictation: fixture.coordinator)
        defer { reopened.close() }
        try await wait { reopened.editor != nil }
        expect(reopened.editor !== oldEditor, "Reopening creates a fresh editor")
        try await fixture.start(into: reopened.editor!)
        expect(fixture.capture.isRecording, "The reopened field can start its own recording")
        fixture.coordinator.cancel(in: reopened.editor!)
        try await wait { !fixture.capture.isRecording }
    }

    /// 校验插入排队期间的取消（关窗或切换聊天）会丢弃排队语音，且不报告插入错误。
    private static func testQueuedCancellation(closing: Bool) async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        var release: CheckedContinuation<Void, Never>?
        fixture.queue.enqueue(isAutomatic: false) {
            await withCheckedContinuation { release = $0 }
        }
        try await wait { release != nil }
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Already transcribed")
        try await wait { !fixture.panel.isVisible }
        expect(fixture.coordinator.field?.isTranscribing == true, "Queued insertion retains its session")

        if closing {
            surface.close()
        } else {
            state.chat = Draft("New chat")
            try await wait { surface.editor?.string == "New chat" }
        }
        try await wait { fixture.coordinator.field == nil }
        release?.resume()
        await fixture.queue.drain()
        expect(first.text == "First draft", "Queued speech cannot write into its canceled draft")
        expect(state.chat.text == (closing ? "First draft" : "New chat"), "Queued speech cannot cross chats")
        expect(fixture.messages.isEmpty, "Discarding queued speech is silent")
    }

    /// 轮询等待条件在 2 秒内成立，超时则抛出 CocoaError。
    private static func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// 断言条件成立，否则 precondition 失败；通过时打印对应的 PASS 信息。
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS  \(message)")
    }

    /// 测试夹具：用替身设置、模型、投递队列与提示回调组装真实的 DictationCoordinator。
    @MainActor
    private final class Fixture {
        let settings = AppSettings()
        let models = DictationModelStore()
        let queue = DeliveryQueue()
        var messages: [String] = []
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: HotKeyManager(), models: models,
            injector: TextInjector(
                clipboardManager: ClipboardManager(), settings: settings, deliveryQueue: queue),
            audioDucker: DictationAudioDucker(), confirmEnable: { false },
            showMessage: { [weak self] message, _ in self?.messages.append(message) })

        /// 最近一次创建的录音捕获对象。
        var capture: DictationCapture { DictationCapture.latest! }
        /// 最近一次创建的录音面板控制器。
        var panel: DictationPanelController { DictationPanelController.latest! }

        /// 开启一次录音并把会话绑定到给定编辑器，等待录音真正开始。
        func start(into editor: ComposerTextView) async throws {
            coordinator.toggle(into: editor)
            try await wait { capture.isRecording }
            expect(coordinator.field?.editor == ObjectIdentifier(editor), "The session belongs to its editor")
        }
    }

    /// 测试用草稿模型：切换聊天时通过其可变 text 观察注入结果。
    @MainActor
    @Observable
    fileprivate final class Draft {
        let id = UUID()
        var text: String
        init(_ text: String) { self.text = text }
    }

    /// 测试用界面状态，持有当前聊天草稿，可被替换以模拟切换聊天。
    @MainActor
    @Observable
    fileprivate final class SurfaceState {
        var chat = Draft("First draft")
    }

    /// 测试根视图：把状态中的草稿与协调器交给 Composer。
    private struct Root: View {
        let state: SurfaceState
        let dictation: DictationCoordinator

        var body: some View { Composer(chat: state.chat, dictation: dictation) }
    }

    /// 测试用输入框视图，承载真实的 ChatComposerTextView 并接上取消回调。
    private struct Composer: View {
        let chat: Draft
        let dictation: DictationCoordinator
        @State private var handle = ComposerTextViewHandle()
        @State private var targeted = false

        var body: some View {
            @Bindable var chat = chat
            ChatComposerTextView(
                text: $chat.text, focusKey: chat.id, maximumTextHeight: 180, handle: handle,
                isFileDragTargeted: $targeted, onDropFiles: { _ in },
                onInvalidate: { dictation.cancel(in: $0) }, onSubmit: {})
        }
    }

    /// 测试用窗口外壳：把 SwiftUI 视图装进 NSWindow，并提供查找编辑器与关闭能力。
    @MainActor
    private final class Surface {
        private var window: NSWindow?

        init(state: SurfaceState, dictation: DictationCoordinator) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Root(state: state, dictation: dictation))
            window.contentView?.layoutSubtreeIfNeeded()
            self.window = window
        }

        /// 在当前窗口视图树中查找 ComposerTextView。
        var editor: ComposerTextView? { window?.contentView.flatMap(Self.findEditor) }

        func close() {
            window?.close()
            window = nil
        }

        private static func findEditor(_ view: NSView) -> ComposerTextView? {
            if let editor = view as? ComposerTextView { return editor }
            return view.subviews.lazy.compactMap(findEditor).first
        }
    }
}

/// 测试替身：Dictation 相关设置的最小可写子集。
@MainActor
final class AppSettings {
    var snippetsEnabled = false
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.copy
    var dictationAdaptsCapitalization = true
    var language: AppLanguage = .english
    func text<K: LocalizableKey>(_ key: K) -> String { L10n.string(key, language: language) }
}

/// 测试替身：热键动作仅保留 dictation 一种。
enum HotKeyAction { case dictation }

/// 测试替身：热键管理器始终返回无绑定、无冲突。
@MainActor
final class HotKeyManager {
    struct Binding {
        var shortcut: Int?
        var holdKey: Int?
    }
    func binding(for action: HotKeyAction) -> Binding? { nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

/// 测试替身：可手动控制开始/停止并记录停止次数的录音捕获。
@MainActor
final class DictationCapture {
    /// 测试替身：采集失败类型，仅供 `catch ... as DictationCapture.Failure` 使用。
    enum Failure: Error {
        case captureUnavailable
        func message(_ language: AppLanguage) -> String { "" }
    }
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var isRecording = false
    var stopCount = 0

    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    func stop() async -> [Float] {
        isRecording = false
        stopCount += 1
        return [Float](repeating: 0, count: 1_600)
    }
}

/// 测试替身：可挂起等待的转写模型存储，用于控制转写完成时机。
@MainActor
final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var finished = false

    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}

    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        defer { finished = true }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    /// 结束挂起的转写并返回给定文本。
    func finish(_ text: String) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: text)
    }
}

/// 测试替身：记录可见状态的录音面板控制器。
@MainActor
final class DictationPanelController {
    /// 面板阶段：监听或转写中。
    enum Phase { case listening, transcribing }
    /// 面板状态：当前阶段与电平。
    @MainActor
    final class State {
        var phase = Phase.listening
        var levels: [Float] = []
    }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    var language: AppLanguage = .english
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}

/// 测试替身：音频闪避的空实现。
@MainActor
final class DictationAudioDucker {
    func begin() {}
    func end() {}
    func restoreImmediately() {}
}

/// 测试替身：剪贴板管理器，仅提供内部粘贴板类型与空实现。
@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.gearmac.internal")
    func prepareForGearMacPasteboardMutation() {}
    func synchronizeAfterGearMacPasteboardMutation(changeCount: Int) {}
}

/// 测试替身：权限检查始终返回未授权。
enum Permissions {
    @discardableResult
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

/// 测试替身：记录复制文本并忽略按键事件注入的粘贴器。
@MainActor
enum Paster {
    static let gearmacEventTag: Int64 = 0x54494E59
    static var copies: [String] = []
    static func copyPlainText(_ text: String) { copies.append(text) }
    static func postCommandV(toPid pid: pid_t? = nil) {}
    static func postCommandC(toPid pid: pid_t? = nil) {}
}

/// 测试替身：对话框语气枚举，仅保留 danger。
enum DialogTone { case danger }
