// 文件职责：用 pty（伪终端）启动子进程，使其输出实时且有序，并提供会话信号与退出码等待。
// 分层：Service；POSIX 层实现，@unchecked Sendable，不依赖 AppKit/SwiftUI。
import Darwin
import Foundation

/// libc 会对管道做块缓冲，因此只有 pty 才能让输出实时且顺序正确。
final class PseudoTerminal: @unchecked Sendable {
    /// 命令写入其三个描述符的一切内容都会到达这里。
    let parentEnd: Int32
    let processID: pid_t

    /// 仅供 `spawn` 调用，外部不可直接构造。
    private init(parentEnd: Int32, processID: pid_t) {
        self.parentEnd = parentEnd
        self.processID = processID
    }

    /// 在 pty 上启动命令，失败时返回 nil。
    static func spawn(
        executable: String, arguments: [String], environment: [String: String],
        workingDirectory: String
    ) -> PseudoTerminal? {
        // POSIX 将二者称作 master 与 slave 端；这里就是这两个描述符。
        var parentEnd: Int32 = 0
        var childEnd: Int32 = 0
        var settings = terminalSettings()
        guard openpty(&parentEnd, &childEnd, nil, &settings, nil) == 0 else { return nil }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // 关键所在：子进程自成一个会话，从而 `kill(-pid)` 能触达全部子孙进程。
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        // addchdir（POSIX 2024 标准名）macOS 26 才有；用 Apple 一直在的 _np 扩展名，两个系统同一条路径。
        posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
        for descriptor in Int32(0)...Int32(2) {
            posix_spawn_file_actions_adddup2(&actions, childEnd, descriptor)
        }
        posix_spawn_file_actions_addclose(&actions, parentEnd)
        posix_spawn_file_actions_addclose(&actions, childEnd)

        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        var processID: pid_t = 0
        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        let status = posix_spawn(
            &processID, executable, &actions, &attributes, argv.pointers, envp.pointers)
        Darwin.close(childEnd)
        guard status == 0, processID > 0 else {
            Darwin.close(parentEnd)
            return nil
        }
        // 代替 `/dev/null` 的 stdin：会提示输入的命令读到 EOF 后继续执行。
        var endOfTransmission: UInt8 = 0x04
        _ = write(parentEnd, &endOfTransmission, 1)
        return PseudoTerminal(parentEnd: parentEnd, processID: processID)
    }

    /// 发信号给整个会话而非单个进程——负的 pid 才能触达子进程。
    func signalSession(_ signal: Int32) {
        guard processID > 0 else { return }
        kill(-processID, signal)
    }

    /// 阻塞直到命令退出。被信号杀死时按 shell 的方式报告信号值。
    func wait() -> Int32 {
        var status: Int32 = 0
        while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
        if status & 0x7F != 0 { return 128 + (status & 0x7F) }
        return (status >> 8) & 0xFF
    }

    /// 关闭父端描述符。
    func close() {
        Darwin.close(parentEnd)
    }

    /// 整行采用规范模式，关闭回显以免 EOF 字节被回显为文本。
    private static func terminalSettings() -> termios {
        var settings = termios()
        cfmakeraw(&settings)
        settings.c_lflag = tcflag_t(ICANON | ISIG)
        settings.c_oflag = tcflag_t(OPOST | ONLCR)
        return settings
    }
}

/// argv/envp 数组必须比 `posix_spawn` 存活更久，因此这里需要真实分配。
private final class CStringArray {
    let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    private let count: Int

    /// 将字符串数组复制为 C 字符串指针数组，末尾补 NULL 哨兵。
    init(_ values: [String]) {
        count = values.count
        pointers = .allocate(capacity: count + 1)
        for (index, value) in values.enumerated() { pointers[index] = strdup(value) }
        pointers[count] = nil
    }

    /// 释放每个 C 字符串与指针数组本身。
    deinit {
        for index in 0..<count { free(pointers[index]) }
        pointers.deallocate()
    }
}
