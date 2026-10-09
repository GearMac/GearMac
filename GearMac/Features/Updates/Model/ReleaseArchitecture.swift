// 文件职责：表示当前运行的发布架构（Apple Silicon 或 Intel）。
// 分层：Model（Sendable 枚举）；`current` 在编译期按切片静态解析，不依赖 AppKit/SwiftUI。
import Foundation

/// macOS 26 是最后一个能在 Intel 上启动的版本，因此稳定版同时提供瘦架构包与通用包。
enum ReleaseArchitecture: Sendable {
    case appleSilicon
    case intel

    /// 在编译期按切片静态解析，因此通用二进利会报告 macOS 实际启动的那一份架构。
    static var current: ReleaseArchitecture {
        #if arch(x86_64)
            .intel
        #else
            .appleSilicon
        #endif
    }
}
