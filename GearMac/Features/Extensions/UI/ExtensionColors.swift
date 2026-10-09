// 文件职责：定义扩展界面专用的颜色常量（输入框、复选框、网格项、详情卡片等）。
// 分层：UI；颜色独立于 Theme，避免第三方界面影响启动器界面的外观。
import SwiftUI

/// 定义在此而非 `Theme`：第三方界面不得强行改变启动器界面的外观。
enum ExtensionColors {
    /// 与设置卡片相同的表面色，使表单字段与应用的材质一致。
    static let fieldFill = Theme.Colors.ramp(dark: 0.05, light: 0.04)
    /// 系统强调色，与应用中其他获得焦点的控件一致。
    static let fieldFocusStroke = Color.accentColor
    static let fieldStroke = Theme.Colors.ramp(dark: 0.10, light: 0.10)
    /// 复选框自身的描边，比输入框更亮：它是控件本身，而非容器。
    static let checkboxStroke = Theme.Colors.ramp(dark: 0.26, light: 0.30)
    /// 指针悬停时的填充色，与应用中其他可悬停行的抬升效果一致。
    static let fieldHoverFill = Theme.Colors.ramp(dark: 0.08, light: 0.07)
    static let fieldHoverStroke = Theme.Colors.ramp(dark: 0.18, light: 0.18)
    /// 比列表行更淡，因为网格会平铺许多这样的项。
    static let gridItemFill = Theme.Colors.ramp(dark: 0.03, light: 0.035)
    static let detailCardFill = Theme.Colors.ramp(dark: 0.05, light: 0.04)
}
