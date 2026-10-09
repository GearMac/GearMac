// 文件职责：支持窗口的内容视图：展示应用图标、文案、支持按钮与提醒开关，并把实测高度回传给窗口。
// 分层：UI；仅读取 AppSettings 与 SupportCoordinator，不直接执行系统操作。
import AppKit
import SwiftUI

/// 支持界面：说明文案、唯一的按钮与提醒开关。
struct SupportWindowView: View {
    /// 直接持有而非注入：它不发布任何变化，用 `@Observable` 没有意义。
    let support: SupportCoordinator

    @Environment(AppSettings.self) private var settings

    static let width: CGFloat = 460
    /// 仅用于首次布局测量出真实尺寸之前，之后窗口会采用实测高度。
    static let initialSize = CGSize(width: width, height: 340)

    private static let iconSize: CGFloat = 76

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: Theme.Spacing.xxl) {
            hero
            action
            reminder(isOn: $settings.supportRemindersEnabled)
        }
        // 顶部内边距更小：标题栏本身已在其上方贡献了 32pt。
        .padding(.top, Theme.Spacing.md)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        // 取理想高度而非窗口高度：测量自身输出会形成反馈循环。
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            support.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // 只有渐变延伸到标题栏下方，内容仍保持在安全区内。
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear], startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            VStack(spacing: Theme.Spacing.sm) {
                Text(supportTitle)
                    .font(.title2.weight(.semibold))
                Text(settings.text(SupportKey.builtWithLove))
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action

    private var action: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SupportActionButton(title: supportTitle, icon: "heart") {
                support.openCheckout()
            }
            Text(settings.text(SupportKey.secureCheckout))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Reminder

    private func reminder(isOn: Binding<Bool>) -> some View {
        Toggle(settings.text(SupportKey.remindMe), isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(String(format: settings.text(SupportKey.remindHelp), Bundle.main.appDisplayName))
    }

    /// 标题与按钮共用的「支持 <应用名>」文案。
    private var supportTitle: String {
        String(format: settings.text(SupportKey.windowTitle), Bundle.main.appDisplayName)
    }
}

/// 窗口唯一的行动按钮。与支持功能的其它视图一样，仅在本模块内使用。
private struct SupportActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var hovered = false

    private static let height: CGFloat = 46

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.headline)
            }
            // 两种外观下都用白色文字：饱和的填充色自身已提供足够对比度。
            .foregroundStyle(Color.white)
            .padding(.horizontal, Theme.Spacing.xxxl)
            .frame(height: Self.height)
            .background(
                Capsule()
                    .fill(Theme.Colors.brand)
                    .brightness(hovered ? 0.08 : 0)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}
