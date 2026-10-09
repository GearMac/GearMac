// 文件职责：验证 SystemActionCatalog 的 32 个系统操作：数量、ID 往返映射、命名唯一性与确认策略。
// 分层：测试 harness；仅 import Foundation，直接断言目录数据表，不触碰 AppKit/UI。

import Foundation

/// 系统操作目录的独立测试 harness（直接运行，不依赖 XCTest）。
@main
@MainActor
struct SystemActionTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件不成立时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// harness 入口：逐项校验目录的数量、身份与确认策略，失败时以退出码 1 结束。
    static func main() {
        let actions = SystemActionCatalog.all
        expect(actions.count == 32, "catalog contains all 32 agreed actions")
        expect(actions.map(\.id) == SystemAction.ID.allCases, "catalog covers every ID once")
        expect(Set(actions.map { $0.name.lowercased() }).count == actions.count, "names are unique")
        expect(actions.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(actions.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for action in actions {
            expect(
                SystemActionCatalog.action(forEntryID: action.entryID) == action,
                "\(action.id.rawValue) round-trips through its entry ID")
            expect(
                action.entryID == "system-action:" + action.id.rawValue,
                "\(action.id.rawValue) is namespaced")
        }

        let confirmed: Set<SystemAction.ID> = [
            .restart, .shutDown, .logOut, .emptyTrash, .quitAllApps
        ]
        expect(
            Set(actions.filter { $0.confirmation != .none }.map(\.id)) == confirmed,
            "only the agreed disruptive actions require confirmation")
        for action in actions {
            switch action.confirmation {
            case .required(let title, let message), .followsFinder(let title, let message):
                expect(
                    !L10n.string(title, language: .english).isEmpty
                        && !L10n.string(message, language: .english).isEmpty,
                    "\(action.id.rawValue) carries confirmation copy")
            case .none, .computed:
                continue
            }
        }
        expect(
            actions.filter { if case .followsFinder = $0.confirmation { true } else { false } }
                .map(\.id) == [.emptyTrash],
            "only Empty Trash defers its confirmation to Finder's own preference")
        expect(
            SystemActionCatalog.action(id: .quitAllApps).confirmation == .computed,
            "Quit All builds its own copy from the target count")
        expect(
            SystemActionCatalog.all.allSatisfy { SystemActionCatalog.action(id: $0.id) == $0 },
            "every action round-trips through its ID")
        expect(
            SystemActionCatalog.action(forEntryID: "system-action:unknown") == nil,
            "unknown entry IDs are rejected")
        expect(
            !actions.contains { $0.id.rawValue == "quit-all-apps-except-frontmost" },
            "Quit All Except Frontmost remains out of scope")

        let microphone = SystemActionCatalog.action(id: .toggleMicrophoneMute)
        expect(microphone.name == "Toggle Microphone Mute", "microphone mute has its own launcher row")
        expect(microphone.sfSymbol == "mic.slash", "microphone mute uses a microphone glyph")
        expect(
            microphone.entryID == "system-action:toggle-microphone-mute",
            "microphone mute has a stable identity separate from output mute")
        expect(microphone.confirmation == .none, "microphone mute runs directly from a global hotkey")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
