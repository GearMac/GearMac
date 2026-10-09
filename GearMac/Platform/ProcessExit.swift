// 文件职责：提供不依赖 run loop 的进程退出等待能力（`ProcessExit` 与 `runObservingExit`）。
// 分层：Service；基于 DispatchSemaphore，可在任意线程安全等待。
import Foundation

extension Process {
    /// 用它替代 `waitUntilExit`：后者的 run loop 在 GCD 线程上可能错过退出事件而挂起。
    func runObservingExit() throws -> ProcessExit {
        let exit = ProcessExit()
        terminationHandler = { _ in exit.signal() }
        try run()
        return exit
    }
}

/// 无需 run loop 即可阻塞等待；退出后再次等待会立即返回。
struct ProcessExit: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    fileprivate func signal() {
        semaphore.signal()
    }

    func wait() {
        semaphore.wait()
        semaphore.signal()
    }
}
