// 文件职责：监听系统「语言与地区」的数字格式变化，为计算器提供当前地区或英文的数字分隔符格式。
// 分层：Service；@MainActor 隔离，通过区域变更通知实时更新，无需重启应用。
import Foundation

/// 跟随「语言与地区」的数字格式设置，使其变更无需重启即可生效。
@MainActor
@Observable
final class RegionNumberFormatMonitor {
    private(set) var system = RegionNumberFormatMonitor.read()
    /// 仅 init 赋值一次、deinit 读取一次，无并发写；`nonisolated(unsafe)` 绕开 deinit
    /// 的隔离检查（NSObjectProtocol 非 Sendable，无法在 nonisolated deinit 中直接访问）。
    @ObservationIgnored nonisolated(unsafe) private var token: NSObjectProtocol?

    /// 注册区域变更通知，并在收到通知时重新读取系统格式。
    /// 用 `forName` 老 API 而非 26 的 `addObserver(of:for:using:)`：同一通知在两个系统上
    /// 行为一致，且无需维护可用性分支；`queue: .main` 保证回调在主线程。
    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.system = Self.read() }
        }
    }

    /// 释放时移除通知观察者。
    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    /// 按样式返回数字格式：跟随系统时用实时读取的格式，否则用英文格式。
    func format(for style: CalcNumberStyle) -> CalcNumberFormat {
        style == .system ? system : .english
    }

    /// 解析器无法处理的分隔符（如阿拉伯语 `٫`）回退到英文格式。
    /// 读取当前地区的数字格式，无法构造时回退到英文格式。
    private static func read() -> CalcNumberFormat {
        let locale = Locale.autoupdatingCurrent
        return CalcNumberFormat(
            decimalSeparator: locale.decimalSeparator ?? ".", groupingSeparator: locale.groupingSeparator)
            ?? .english
    }
}
