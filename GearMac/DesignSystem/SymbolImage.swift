// 文件职责：提供 `SymbolImage` 视图，按名称优先渲染 SF Symbol，名称不存在时回退到同名打包资源图。
// 分层：UI（DesignSystem）；只做名称解析与渲染，不缓存图片。
import SwiftUI

/// 按名称渲染的图标：若不是系统符号，则回退到同名的打包资源图。
struct SymbolImage: View {
    let name: String
    let size: CGFloat
    var monochrome = false

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            if monochrome {
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: .regular))
                .symbolRenderingMode(monochrome ? .monochrome : .hierarchical)
        }
    }
}
