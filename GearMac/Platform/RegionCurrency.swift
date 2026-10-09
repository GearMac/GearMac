// 文件职责：读取当前区域的货币代码。
// 分层：Model；仅读 Locale，绝不使用 CoreLocation，因此不会触发任何授权弹窗。
import Foundation

/// 读取“语言与地区”设置，绝不使用 CoreLocation，因此不会弹窗。
enum RegionCurrency {
    /// 当前区域货币的 ISO 代码，取不到时为 nil。
    static var code: String? { Locale.current.currency?.identifier }
}
