// 文件职责：About（关于）设置页，展示应用图标、版本号、检查更新入口、外链与赞助入口。
// 分层：UI；纯 SwiftUI 视图，业务动作一律委托给 AppCore 上的协调器。
import AppKit
import SwiftUI

/// 关于页主体视图。
struct AboutView: View {
    @Environment(AppCore.self) private var core

    /// 由 bundle 中的短版本号与构建号拼出的展示用版本字符串。
    private static func version(_ language: AppLanguage) -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return String(format: L10n.string(WindowsKey.aboutVersionFormat, language: language), short, build)
    }

    // 从 bundle 读取并缓存：在 LaunchServices 完成注册之前，应用图标只是通用占位图。
    @MainActor private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    private static let iconSize: CGFloat = 88
    private static let supportTile: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    hero
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                .settingsAnchor(.aboutAbout)
                links
                support
            }
            .formStyle(.grouped)
            .settingsScrollTarget(.about)

            // 放在 Form 之外，使版权信息始终贴住底边。
            footer
                .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    /// 顶部区域：应用图标、名称、版本胶囊与“Check for Updates”链接。
    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Bundle.main.appDisplayName)
                    .font(.title.weight(.bold))
                Text(Self.version(core.settings.language))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(
                        Capsule().fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
                Button {
                    core.updateCoordinator.checkForUpdates()
                } label: {
                    SettingsRowTitle(.aboutAbout, core.settings.text(WindowsKey.aboutCheckForUpdates))
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Text(core.settings.text(WindowsKey.aboutTagline))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// 外链分区，逐条列出 `AboutLink.all`。
    private var links: some View {
        Section {
            ForEach(AboutLink.all) { link in
                AboutLinkRow(link: link)
            }
        } header: {
            SettingsSectionHeader(.aboutLinks)
        }
    }

    /// 赞助/支持分区，提供打开赞助窗口的入口。
    private var support: some View {
        Section {
            HStack(spacing: Theme.Spacing.xl) {
                // 品牌色是固定色相，叠加透明度后在浅色和深色外观下都成立。
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.brand.opacity(0.16))
                    .frame(width: Self.supportTile, height: Self.supportTile)
                    .overlay(
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Colors.brand)
                    )
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    SettingsRowTitle(.aboutLinks, core.settings.text(WindowsKey.aboutSupportTitle))
                        .font(.body.weight(.medium))
                    Text(core.settings.text(WindowsKey.aboutSupportBlurb))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.lg)
                Button(core.settings.text(WindowsKey.aboutSupportButton)) {
                    core.supportCoordinator.showSupport()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.brand)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    /// 固定在页面底部的版权信息。
    private var footer: some View {
        Text(core.settings.text(WindowsKey.aboutCopyright))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

/// 关于页“Links”卡片中的一个外部跳转目标。
private struct AboutLink: Identifiable {
    enum Glyph {
        case symbol(String)
        /// 来自资源目录的品牌图标；SF Symbols 没有提供这类 logo。
        case brand(String)
    }

    let id: String
    let glyph: Glyph
    /// 展示用的本地化标题键。
    let title: WindowsKey
    /// 目标地址或句柄；本身不翻译。
    let detail: String
    /// 需要翻译的说明文字；有值时优先于 `detail`。
    var detailKey: WindowsKey? = nil
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "website", glyph: .symbol("globe"), title: .aboutLinkWebsite,
            detail: "gearmac.dev",
            url: URL(string: "https://gearmac.dev/")!),
        AboutLink(
            id: "github", glyph: .brand("BrandGitHub"), title: .aboutLinkGitHub,
            detail: "github.com/GearMac/GearMac",
            url: URL(string: "https://github.com/GearMac/GearMac")!),
    ]
}

/// 关于页“Links”卡片中的一行：图标、标题、目标地址与跳转箭头。
private struct AboutLinkRow: View {
    let link: AboutLink

    @Environment(AppSettings.self) private var settings
    @State private var hovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(link.detailKey.map { settings.text($0) } ?? link.detail)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hovered ? .secondary : .tertiary)
                }
            } label: {
                Label {
                    Text(settings.text(link.title))
                } icon: {
                    glyph
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    /// 按目标类型渲染 SF Symbol 或资源目录中的品牌图标。
    @ViewBuilder
    private var glyph: some View {
        switch link.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
        case .brand(let name):
            // 品牌图标是满幅绘制的，因此缩到符号框大小以与 SF Symbol 保持一致。
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
    }
}
