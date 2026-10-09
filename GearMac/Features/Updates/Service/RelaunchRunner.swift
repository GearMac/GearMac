// 文件职责：在当前进程退出后重新启动指定的应用包。
// 分层：Service（进程与 shell 调用）；依赖 /bin/sh 与 /usr/bin/open，不涉及任何 UI。
import Foundation

/// 对已在运行的 bundle ID 调用 `open` 只会激活它，因此这次重启必须活过本进程。
enum RelaunchRunner {
    /// 启动一个独立 shell，等待本进程退出后再打开给定应用包。
    static func relaunchAfterExit(_ bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let quoted = bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; "
                + "/usr/bin/open '\(quoted)'"
        ]
        // 该子进程在本进程退出后被孤儿化并交由 launchd 接管，这正是此设计的目的。
        try? process.run()
    }
}
