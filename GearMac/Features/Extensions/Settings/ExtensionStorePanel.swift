// 文件职责：Raycast Store 扩展搜索面板：防抖搜索、结果列表与逐项安装、重装。
// 分层：UI（SwiftUI 视图）；搜索与安装副作用经 AppCore 与 ExtensionStoreClient 执行。
import SwiftUI

/// Raycast Store 的搜索界面，每个结果带一个安装按钮。
struct ExtensionStorePanel: View {
    let onClose: () -> Void
    @Environment(AppCore.self) private var core

    @State private var query = ""
    @State private var results: [ExtensionListing] = []
    @State private var searchFailure: String?
    @State private var searching = false
    @State private var searched = false
    @State private var installing: [String: ExtensionInstaller.Progress] = [:]
    @State private var failures: [String: String] = [:]
    @State private var installed: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ExtensionSettingsEditorHeader(
                title: "Search Extensions",
                subtitle: "The Raycast Store's extensions arrive built, so they install as they are.")
            // 复用各面板通用的无边框输入框，而不是自造一个带边框的胶囊输入框。
            SettingsFilterField(prompt: "Search extensions…", query: $query)
            content
            // 没有这条分隔线时，列表会一直贴到页脚，最后一行被裁切。
            Divider()
            footer
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: 620, height: 560)
        .extensionSettingsEditorPanelSurface()
        .onChange(of: query) { _, value in scheduleSearch(value) }
        .onDisappear { searchTask?.cancel() }
    }

    /// 面板主体：按查询与搜索状态在空态、加载、失败、无结果与结果列表间切换。
    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyState
        } else if searching && results.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Searching…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let searchFailure {
            placeholder(searchFailure)
        } else if results.isEmpty && searched {
            placeholder("Nothing matches “\(query)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(results) { listing in
                        StoreRow(
                            listing: listing,
                            state: state(for: listing),
                            onInstall: { install(listing) })
                    }
                }
                .hideNativeScrollers()
            }
            .overflowFade()
            .thinScrollbar()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 不是在高而空的面板里放一行干巴巴的文字：这里说明可以做什么、会搜索什么。
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search for an extension")
                .font(.headline)
            Text(
                "By name, or by what it does — \u{201C}colour\u{201D}, \u{201C}github\u{201D}, \u{201C}window\u{201D}."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 居中的占位文案视图。
    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 底部操作区：仅一个关闭按钮，并绑定 Escape。
    private var footer: some View {
        HStack {
            Spacer()
            // 用 Escape 而非 Return：输入时 Return 属于搜索框。
            Button("Done", action: onClose)
                .buttonStyle(
                    ExtensionSettingsEditorButtonStyle(role: .cancel, fillsWidth: false)
                )
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - State

    /// 按已安装集合、进行中进度与失败记录推导某条结果当前的状态。
    private func state(for listing: ExtensionListing) -> StoreRow.InstallState {
        if installed.contains(listing.name) { return .installed }
        if let progress = installing[listing.id] { return .installing(progress.message) }
        if let failure = failures[listing.id] { return .failed(failure) }
        if core.extensions.installed.contains(where: { $0.manifest.name == listing.name }) {
            return .alreadyInstalled
        }
        return .idle
    }

    // MARK: - Searching

    /// 防抖：否则每次按键都会变成一次对第三方 API 的请求。
    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            searchFailure = nil
            searched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    /// 执行搜索：调用 `ExtensionStoreClient` 并把结果或错误写回状态。
    private func search(_ trimmed: String) async {
        searching = true
        defer {
            searching = false
            searched = true
        }
        do {
            let found = try await ExtensionStoreClient().search(trimmed)
            guard !Task.isCancelled else { return }
            (results, searchFailure) = (found, nil)
        } catch {
            guard !Task.isCancelled else { return }
            (results, searchFailure) = ([], error.localizedDescription)
        }
    }

    // MARK: - Installing

    /// 安装一条结果：开始下载并跟踪进度，失败时记录错误。
    private func install(_ listing: ExtensionListing) {
        failures[listing.id] = nil
        installing[listing.id] = .downloading
        Task {
            do {
                try await core.extensions.install(
                    listing,
                    onProgress: { progress in
                        Task { @MainActor in installing[listing.id] = progress }
                    })
                installed.insert(listing.name)
            } catch {
                failures[listing.id] = error.localizedDescription
            }
            installing[listing.id] = nil
        }
    }
}

/// 一条搜索结果：它是什么、作者是谁、有多少人使用，以及安装按钮。
private struct StoreRow: View {
    /// 单个结果的安装状态，决定右侧按钮的外观与行为。
    enum InstallState: Equatable {
        case idle
        case installing(String)
        case installed
        case alreadyInstalled
        case failed(String)
    }

    /// 比设置行的图标更大：在商店列表里，图标是用户找到结果的方式。
    private static let iconSide: CGFloat = 40

    let listing: ExtensionListing
    let state: InstallState
    let onInstall: () -> Void
    @Environment(\.isDarkAppearance) private var isDark
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: .remote($0))
                },
                size: Self.iconSide)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(listing.title)
                    .font(.headline)
                    .lineLimit(1)
                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
                if case .failed(let message) = state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            action
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    /// 结果的事实信息行：作者、命令数与安装量。
    private var facts: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if !listing.author.isEmpty {
                StoreFact(symbol: "person.crop.circle", text: listing.author)
            }
            StoreFact(
                symbol: "square.grid.2x2",
                text: "\(listing.commandCount) command\(listing.commandCount == 1 ? "" : "s")")
            if let downloads = listing.downloadCount, downloads > 0 {
                StoreFact(symbol: "arrow.down.circle", text: ExtensionListing.abbreviate(downloads))
                    .help("\(downloads.formatted()) installs")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    /// 右侧操作区：按安装状态显示安装、进度、已安装、重装或重试。
    @ViewBuilder
    private var action: some View {
        switch state {
        case .idle:
            Button("Install", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary, fillsWidth: false))
        case .installing(let message):
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize()
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .alreadyInstalled:
            Button("Reinstall", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false))
                .help("Already installed. Reinstalling replaces it with the store's copy.")
        case .failed:
            Button("Retry", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false))
        }
    }
}

/// 结果下方的一条事实信息，前面是标明该事实类型的图标。
private struct StoreFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
            Text(text)
        }
        .lineLimit(1)
    }
}
