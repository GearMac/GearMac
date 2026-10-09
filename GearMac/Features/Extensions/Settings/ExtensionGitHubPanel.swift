// 文件职责：从 GitHub 源码构建并安装扩展的设置面板，含包管理器选择与自定义搜索路径。
// 分层：UI（SwiftUI 视图）；构建与安装副作用全部经 AppCore 的 extensions 服务执行。
import SwiftUI

/// 从 GitHub 源码构建一个扩展；只保留构建产物。
struct ExtensionGitHubPanel: View {
    let onClose: () -> Void

    @Environment(AppCore.self) private var core
    @State private var repository = ""
    @State private var progress: ExtensionInstaller.Progress?
    @State private var failure: String?
    @State private var installedTitle: String?
    @State private var installTask: Task<Void, Never>?

    private var source: ExtensionGitHubSource? { ExtensionGitHubSource(repository) }
    /// 是否正在安装：只要存在安装进度即视为进行中。
    private var isInstalling: Bool { progress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ExtensionSettingsEditorHeader(
                title: "Install from GitHub",
                subtitle: "Builds an extension from source on this Mac. Only the build is kept — "
                    + "the source and its dependencies are deleted once it installs.")

            repositoryField
            ExtensionToolchainFields()
                .disabled(isInstalling)

            Text(
                "Installing runs your package manager and the extension's own build script. "
                    + "Install only from someone you trust."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            status

            HStack(spacing: Theme.Spacing.md) {
                Button(installedTitle == nil ? "Cancel" : "Done", action: onClose)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Install", action: install)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isInstalling)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .extensionSettingsEditorPanelSurface()
        .onChange(of: repository) {
            failure = nil
            installedTitle = nil
        }
        // 构建中途关闭会终止构建，工作区随之删除，因此不会留下半成品。
        .onDisappear { installTask?.cancel() }
    }

    /// 仓库地址输入区：解析失败时提示格式，解析成功时说明将构建什么。
    private var repositoryField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Repository").font(.callout.weight(.medium))
            TextField("", text: $repository, prompt: Text("owner/repo, or a link to the extension's folder"))
                .extensionSettingsEditorTextField()
                .pointerStyle(.horizontalText)
                .disabled(isInstalling)
            if let source {
                Text("Builds \(source.summary).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !repository.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("That doesn't look like a GitHub repository.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 面板状态区：按优先级显示安装进度、失败信息或安装完成提示。
    @ViewBuilder
    private var status: some View {
        if let progress {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(progress.message).font(.caption).foregroundStyle(.secondary)
            }
        } else if let failure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if let installedTitle {
            Label("Installed \(installedTitle).", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    /// 发起安装：读取包管理器设置并启动后台构建任务。
    private func install() {
        guard let source, !isInstalling else { return }
        let settings = core.settings
        failure = nil
        installedTitle = nil
        progress = .downloading
        installTask = Task {
            defer { progress = nil }
            do {
                let installed = try await core.extensions.install(
                    source, packageManager: settings.extensionPackageManager,
                    additionalSearchPaths: settings.extensionCustomSearchPaths,
                    onProgress: { step in
                        // 加保护：安装结束后，晚到的主线程调度不得重新点亮 loading 指示器。
                        Task { @MainActor in if progress != nil { progress = step } }
                    })
                installedTitle = installed.title
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }
}

/// 独立成视图：否则输入仓库地址时，每敲一个键都会去磁盘探测包管理器。
private struct ExtensionToolchainFields: View {
    @Environment(AppCore.self) private var core
    /// 只在真正编辑时写回，避免一次写入-读取往返把分隔符丢掉。
    @State private var searchPathsText = ""

    var body: some View {
        @Bindable var settings = core.settings
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Package manager").font(.callout.weight(.medium))
                    Spacer()
                    Picker("", selection: $settings.extensionPackageManager) {
                        ForEach(ExtensionPackageManager.allCases) { manager in
                            Text(manager.title).tag(manager)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text(packageManagerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Custom search paths").font(.callout.weight(.medium))
                TextField("", text: $searchPathsText, prompt: Text("~/.local/share/mise/shims"))
                    .extensionSettingsEditorTextField()
                    .pointerStyle(.horizontalText)
                    .onChange(of: searchPathsText) { _, value in
                        settings.extensionCustomSearchPaths = Self.parseSearchPaths(value)
                    }
                Text(
                    "Colon-separated, like PATH — checked before Homebrew and the rest. For mise: "
                        + "~/.local/share/mise/shims. For Nix (Home Manager): "
                        + "/etc/profiles/per-user/<you>/home-path/bin."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            searchPathsText = core.settings.extensionCustomSearchPaths.joined(separator: ":")
        }
    }

    /// 包管理器选择项下方的说明：描述是否解析成功及其可执行文件路径。
    private var packageManagerDetail: String {
        let chosen = core.settings.extensionPackageManager
        let additionalSearchPaths = core.settings.extensionCustomSearchPaths
        guard let resolved = chosen.resolve(additionalSearchPaths: additionalSearchPaths) else {
            return chosen == .automatic
                ? "None found on this Mac. Install pnpm, npm, Yarn or Bun to build an extension."
                : "\(chosen.title) isn't installed on this Mac."
        }
        return chosen == .automatic
            ? "Found \(resolved.manager.title) at \(resolved.url.path)."
            : "Found at \(resolved.url.path)."
    }

    /// 按 `:` 拆分，与 PATH 本身使用同一分隔符，并丢弃中间的空项。
    private static func parseSearchPaths(_ text: String) -> [String] {
        text.split(separator: ":", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
