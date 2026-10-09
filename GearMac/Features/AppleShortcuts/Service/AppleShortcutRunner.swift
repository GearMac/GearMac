// 文件职责：通过 Apple 自带的 `shortcuts` 命令行工具列出并运行快捷指令。
// 分层：Service；承担外部进程调用这类副作用。
import Foundation

/// 通过 Apple 自带的 `shortcuts` 工具列出与运行快捷指令，无需申请权限。
enum AppleShortcutRunner {
    /// 调用 `shortcuts` 失败时携带的错误描述。
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// 列出当前所有快捷指令。
    static func list() async throws(Failure) -> [AppleShortcut] {
        let result = try await invoke(["list", "--show-identifiers"], timeout: 10)
        return AppleShortcut.parseList(result.output)
    }

    /// 不设置超时：快捷指令可能合法地一直等待自身的对话框。
    static func run(id: UUID) async throws(Failure) {
        _ = try await invoke(["run", id.uuidString], timeout: nil)
    }

    private static func invoke(
        _ arguments: [String], timeout: TimeInterval?
    ) async throws(Failure) -> ToolRunner.Result {
        let result: ToolRunner.Result
        do {
            result = try await ToolRunner.run(executable, arguments, timeout: timeout)
        } catch {
            throw Failure(errorDescription: error.localizedDescription)
        }
        guard result.succeeded else { throw Failure(errorDescription: result.tail) }
        return result
    }
}
