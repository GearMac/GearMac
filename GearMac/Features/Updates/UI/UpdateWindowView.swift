// 文件职责：更新窗口的全部界面——提示、发布说明、进度与结果。
// 分层：UI（SwiftUI）；状态与动作均来自 UpdateCoordinator，实测高度会回传给窗口。
import AppKit
import SwiftUI

/// 更新的完整界面：把提示、发布说明、进度与结果放在同一个窗口内。
struct UpdateWindowView: View {
    @Environment(UpdateCoordinator.self) private var updates
    @Environment(AppSettings.self) private var settings

    static let width: CGFloat = 460
    /// 仅在首次布局测出真实高度之前使用，之后窗口便采用实测高度。
    static let initialSize = CGSize(width: width, height: 158)

    private static let iconSize: CGFloat = 52
    /// macOS 会在应用图标中留出透明边距；把图标外扩可以对齐图像本体。
    private static let iconBleed: CGFloat = 6
    /// 固定的阅读区高度：发布说明从一行到五十行不等，窗口不宜随其伸缩。
    private static let cardHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero
            detail
            actions
        }
        // 顶部留白更少：标题栏会额外占 32pt，且必须避开窗口控制按钮。
        .padding(.top, Theme.Spacing.sm)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        // 使用理想高度而非窗口当前高度，使按此调整尺寸时收敛而不会形成反馈循环。
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            updates.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // 只有渐变延伸到标题栏之下，内容仍保持在安全区内。
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear], startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Hero

    /// 顶部区域：应用图标、标题与副标题。
    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Self.iconSize + Self.iconBleed * 2,
                    height: Self.iconSize + Self.iconBleed * 2
                )
                .padding(-Self.iconBleed)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// 随当前阶段变化的窗口标题。
    private var title: String {
        switch updates.stage {
        case .checking:
            return settings.text(UpdatesKey.titleChecking)
        case .upToDate:
            return String(
                format: settings.text(UpdatesKey.titleUpToDate), Bundle.main.appDisplayName)
        case .localBuild:
            return String(
                format: settings.text(UpdatesKey.titleLocalBuild), Bundle.main.appDisplayName)
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return String(
                format: settings.text(UpdatesKey.titleAvailable), Bundle.main.appDisplayName,
                release.version.description)
        case .readyToRelaunch:
            return settings.text(UpdatesKey.titleInstalled)
        case .failed:
            return settings.text(UpdatesKey.titleFailed)
        }
    }

    /// 随当前阶段变化的副标题。
    private var subtitle: String {
        switch updates.stage {
        case .checking, .upToDate, .failed:
            return String(
                format: settings.text(UpdatesKey.subtitleVersion), updates.runningVersion)
        case .localBuild:
            return settings.text(UpdatesKey.subtitleLocalBuild)
        case .available, .blocked, .installing:
            return String(
                format: settings.text(UpdatesKey.subtitleAvailable), updates.runningVersion)
        case .readyToRelaunch:
            return settings.text(UpdatesKey.subtitleRelaunch)
        }
    }

    // MARK: - Detail

    /// 中部详情区：依阶段显示发布说明、阻塞原因、进度或失败原因。
    @ViewBuilder
    private var detail: some View {
        switch updates.stage {
        case .checking, .upToDate, .localBuild, .readyToRelaunch:
            EmptyView()
        case .available(let release):
            card { notes(release) }
        case .blocked(let blocker, _):
            Label(blocker.message(settings.language), systemImage: "clock")
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .installing(_, let phase):
            progress(phase)
        case .failed(let failure):
            card { report(failure) }
        }
    }

    private func notes(_ release: AvailableRelease) -> some View {
        ReleaseNotesView(text: release.notes)
    }

    /// 失败报告：错误描述与可选的恢复建议。
    private func report(_ failure: UpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(failure.localizedDescription(settings.language))
                .font(.callout)
            if let recovery = failure.localizedRecoverySuggestion(settings.language) {
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 进度视图：有比例时显示确定进度，否则显示线性不确定进度。
    private func progress(_ phase: UpdateInstaller.Phase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let fraction = phase.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(phase.message(settings.language))
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    /// 可滚动的卡片容器，用于发布说明与失败报告。
    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .textSelection(.enabled)
                .padding(Theme.Spacing.xl)
        }
        .frame(height: Self.cardHeight)
        .background(Theme.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Actions

    /// 底部操作按钮，按阶段给出不同的按钮组合。
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            switch updates.stage {
            case .checking:
                ProgressView().controlSize(.small)
                Button(settings.text(UpdatesKey.buttonCancel)) { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .upToDate, .localBuild:
                Button(settings.text(UpdatesKey.buttonOK)) { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .available:
                Button(settings.text(UpdatesKey.buttonLater)) { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(UpdatesKey.buttonUpdateNow)) { updates.install() }
                    .keyboardShortcut(.defaultAction)
            case .blocked:
                Button(settings.text(UpdatesKey.buttonLater)) { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(UpdatesKey.buttonTryAgain)) { updates.retry() }
                    .keyboardShortcut(.defaultAction)
            case .installing:
                Button(settings.text(UpdatesKey.buttonCancel)) { updates.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
            case .readyToRelaunch:
                Button(settings.text(UpdatesKey.buttonLater)) { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(UpdatesKey.buttonRelaunch)) { updates.relaunch() }
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button(settings.text(UpdatesKey.buttonClose)) { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
