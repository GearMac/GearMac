// 文件职责：实现首次启动引导向导的多步骤界面，以及该向导的导入步骤状态模型 OnboardingModel。
// 分层：UI；由自身的 step 状态驱动页面切换，右侧内容区通过 Coordinator 贴合高度。
import AppKit
import Combine
import SwiftUI

/// 首次启动向导，用应用自身的控件搭建；可从设置中重新运行。
struct OnboardingView: View {
    @State private var step = 0
    @State private var model = OnboardingModel()
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys

    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let lastStep = 3
    static let width: CGFloat = 520
    /// 仅在首次布局测出真实高度前使用，之后窗口就会采用实测值。
    static let initialSize = CGSize(width: width, height: 352)

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            hero
            stepContent
            footer
        }
        // 顶部留白更少：标题栏已占 32pt，且必须避开左上角的窗口控件。
        .padding(.top, Theme.Spacing.xs)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        // 用理想高度而非窗口高度，这样按它定尺寸会收敛而不是自反循环。
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            core.onboardingCoordinator.fit(height: $0)
        }
        // 只有渐变延伸到标题栏下方；内容仍在安全区域内。
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
        // 引导的快捷键步骤也有录制器，而它不在 `SettingsPane` 内。
        .shortcutRecorderPopoverHost()
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }

    // MARK: - Hero (icon/glyph + title + subtitle)

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            heroMark
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var heroMark: some View {
        if step == 0 {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 60, height: 60)
        } else {
            Image(systemName: heroSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(heroTint.opacity(0.14)))
        }
    }

    private var title: String {
        switch step {
        case 0: settings.text(OnboardingKey.titleWelcome)
        case 1: settings.text(OnboardingKey.titleEnablePasting)
        case 2: settings.text(OnboardingKey.titleImportRaycast)
        default: settings.text(OnboardingKey.titleAllSet)
        }
    }

    private var subtitle: String {
        switch step {
        case 0: settings.text(OnboardingKey.subtitleShortcut)
        case 1: settings.text(OnboardingKey.subtitlePasting)
        case 2: settings.text(OnboardingKey.subtitleImport)
        default: readyMessage
        }
    }

    private var heroSymbol: String {
        switch step {
        case 1: "accessibility"
        case 2: "wand.and.stars"
        default: "checkmark"
        }
    }

    private var heroTint: Color {
        switch step {
        case 1: .blue
        case 2: .orange
        default: .green
        }
    }

    private var readyMessage: String {
        if let caps = hotKeys.binding(for: .togglePalette)?.keycaps {
            return String(format: settings.text(OnboardingKey.readyPress), caps.joined())
        }
        return settings.text(OnboardingKey.readySetShortcut)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: shortcutStep
        case 1: accessibilityStep
        case 2: raycastStep
        default: doneStep
        }
    }

    private var shortcutStep: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: settings.text(OnboardingKey.rowAppLauncher),
                    subtitle: settings.text(OnboardingKey.rowAppLauncherSubtitle),
                    systemImage: "magnifyingglass", tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: settings.text(OnboardingKey.rowLaunchAtLogin),
                    subtitle: settings.text(OnboardingKey.rowLaunchAtLoginSubtitle),
                    systemImage: "power", tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            caption(settings.text(OnboardingKey.captionChangeAnytime))
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: settings.text(OnboardingKey.rowAccessibility),
                    subtitle: settings.text(OnboardingKey.rowAccessibilitySubtitle),
                    systemImage: "accessibility", tint: .blue
                ) {
                    statusBadge
                }
            }
            caption(settings.text(OnboardingKey.captionEnableLater))
        }
    }

    private var raycastStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: settings.text(OnboardingKey.rowRaycastExport),
                    subtitle: model.fileSubtitle(settings.language),
                    systemImage: "doc.badge.gearshape", tint: .orange
                ) {
                    Button(settings.text(OnboardingKey.buttonChoose)) { model.chooseFile() }
                        .controlSize(.small)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: settings.text(OnboardingKey.rowPassphrase),
                    subtitle: settings.text(OnboardingKey.rowPassphraseSubtitle),
                    systemImage: "key", tint: .gray
                ) {
                    RevealableSecureField(
                        title: settings.text(OnboardingKey.rowPassphrase), text: $model.passphrase
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit { model.run(core: core) }
                }
            }
            RaycastImportSelection(selection: $model.selection)
                .padding(.horizontal, Theme.Spacing.xs)
            if let status = model.status {
                importStatus(status)
            } else {
                caption(settings.text(OnboardingKey.captionImportLater))
            }
        }
    }

    private var doneStep: some View {
        caption(settings.text(OnboardingKey.captionDone))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Footer (step dots + navigation)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label(settings.text(OnboardingKey.buttonBack), systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if showsSkip {
                    Button(settings.text(OnboardingKey.buttonSkip)) { advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                if step == 2 && model.importing {
                    Button {
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text(settings.text(OnboardingKey.buttonImporting))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                } else {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(primaryDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var showsSkip: Bool {
        (step == 1 && !accessibilityTrusted) || (step == 2 && !model.didImport)
    }

    private var primaryTitle: String {
        switch step {
        case 0: settings.text(OnboardingKey.buttonContinue)
        case 1:
            accessibilityTrusted
                ? settings.text(OnboardingKey.buttonContinue)
                : settings.text(OnboardingKey.buttonGrantAccess)
        case 2:
            if model.didImport {
                settings.text(OnboardingKey.buttonContinue)
            } else if model.importing {
                settings.text(OnboardingKey.buttonImporting)
            } else {
                settings.text(OnboardingKey.buttonImport)
            }
        default: settings.text(OnboardingKey.buttonGetStarted)
        }
    }

    private var primaryDisabled: Bool {
        step == 2 && !model.didImport && !model.canImport
    }

    private func primaryAction() {
        switch step {
        case 1 where !accessibilityTrusted:
            Permissions.openAccessibilitySettings()
        case 2 where !model.didImport:
            model.run(core: core)
        case Self.lastStep:
            core.onboardingCoordinator.finishOnboarding()
        default:
            advance()
        }
    }

    private func advance() {
        step = min(step + 1, Self.lastStep)
    }

    // MARK: - Shared bits

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func importStatus(_ status: OnboardingModel.ImportStatus) -> some View {
        switch status {
        case .success(let message):
            statusLine(message, systemImage: "checkmark.circle.fill", tint: .green)
        case .failure(let message):
            statusLine(message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func statusLine(_ message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(
                accessibilityTrusted
                    ? settings.text(OnboardingKey.statusGranted)
                    : settings.text(OnboardingKey.statusNotGranted))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14)))
    }

    // 直接读 bundle：在 LaunchServices 注册之前，应用图标是通用占位图标。
    private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()
}

/// 导入步骤的状态与异步调用，从视图里抽出来以保持 body 的声明式。
@MainActor
@Observable
final class OnboardingModel {
    /// Raycast 导入的结果状态。
    enum ImportStatus {
        case success(String)
        case failure(String)
    }

    var file: URL?
    var passphrase = ""
    var importing = false
    var status: ImportStatus?
    var selection: RaycastImportOptions = .all
    var isRaycastExport = false

    /// 当前是否具备导入条件：已选中 Raycast 导出文件、口令非空、至少选中一项且未在导入中。
    var canImport: Bool {
        isRaycastExport && !passphrase.isEmpty && !selection.isEmpty && !importing
    }
    /// 本次导入是否已成功。
    var didImport: Bool {
        if case .success = status { return true }
        return false
    }

    /// 导入步骤给出行副标题的文案：未选文件时提示，选中后显示文件名与是否为 Raycast 导出。
    func fileSubtitle(_ language: AppLanguage) -> String {
        guard let name = file?.lastPathComponent else {
            return L10n.string(OnboardingKey.fileChooseHint, language: language)
        }
        let key =
            isRaycastExport ? OnboardingKey.fileSubtitleRaycast : OnboardingKey.fileSubtitleNotRaycast
        return String(format: L10n.string(key, language: language), name)
    }

    /// 弹出文件选择器，选中的文件会触发是否为 Raycast 导出文件的判定。
    func chooseFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        file = url
        isRaycastExport = BackupActions.isRaycastExport(url)
        status = nil
    }

    /// 执行 Raycast 导入，并把结果或错误写入 `status`。
    func run(core: AppCore) {
        guard canImport, let file else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    core: core, file: file, passphrase: passphrase, options: selection)
                status = .success(BackupActions.raycastText(outcome, language: core.settings.language))
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
