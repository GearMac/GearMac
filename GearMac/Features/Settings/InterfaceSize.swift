// 文件职责：定义界面尺寸档位（标准/大/更大）及其缩放比例与派生度量。
// 分层：Settings（Model）；纯值类型，仅提供缩放系数和由它派生的 InterfaceMetrics。
import CoreGraphics

/// 面板及其浮动附属界面的渲染尺寸档位；键未设置时按 `.standard` 处理。
enum InterfaceSize: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case larger

    var id: String { rawValue }

    /// 设置界面中展示的名称。
    var title: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    /// 相对标准尺寸的缩放系数。
    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.1
        case .larger: 1.2
        }
    }

    /// 由缩放系数派生的具体度量和尺寸。
    var metrics: InterfaceMetrics { InterfaceMetrics(scale: scale) }
}
