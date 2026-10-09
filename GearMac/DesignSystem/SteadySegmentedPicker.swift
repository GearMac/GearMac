// 文件职责：将 `NSSegmentedControl` 封装为 SwiftUI 控件 `SteadySegmentedPicker`，固定分段宽度以避免切换选项时控件在指针下变宽。
// 分层：UI（DesignSystem，AppKit 桥接）；宽度由显式设置的段宽累加计算，不依赖控件自适应。
import AppKit
import SwiftUI

/// 将系统分段控件固定在一种尺寸，每个分段的宽度与其标签等宽。
///
/// 若交给控件自行计算尺寸，它会紧贴标签展开，并在首次切换选项时于指针下方变宽；
/// 显式声明每段宽度后，控件从一开始就是最终尺寸。
struct SteadySegmentedPicker<Value: Hashable>: NSViewRepresentable {
    /// 单个分段选项：对外取值与显示标题。
    struct Option {
        let value: Value
        let title: String
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 按标题文字宽度预先设定每个分段的宽度，使控件一开始就是最终尺寸。
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.setAccessibilityLabel(title)
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for (index, option) in options.enumerated() {
            let label = (option.title as NSString).size(withAttributes: [.font: font]).width
            control.setWidth(
                (label + Theme.Size.segmentLabelInset * 2).rounded(.up), forSegment: index)
        }
        return control
    }

    /// 同步绑定值与协调器引用，并按当前 `selection` 设置选中分段。
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    /// 控件自身的宽度估计在首次切换后也会缩小，因此这里不采用它的估计值。
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        let width = (0..<nsView.segmentCount).reduce(0) { $0 + nsView.width(forSegment: $1) }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    /// 桥接 NSSegmentedControl 的目标/动作，把选中变化写回 SwiftUI 的绑定。
    @MainActor
    final class Coordinator: NSObject {
        var parent: SteadySegmentedPicker

        init(_ parent: SteadySegmentedPicker) {
            self.parent = parent
        }

        /// 分段控件选中项变化时，把对应取值写回 `selection`。
        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
