// 文件职责：命令输出窗口的视图，包含头部（命令名/命令文本/操作按钮）、终端日志区与底部状态栏。
// 分层：UI；仅做展示，所有状态与动作都委托给 CommandOutputPresenter。
import AppKit
import SwiftUI

/// 单一平面：日志即页面，仅用留白与字重分隔，不使用分隔线。
struct CommandOutputView: View {
    let presenter: CommandOutputPresenter
    let settings: AppSettings

    /// 输出窗口的初始尺寸。
    static let initialSize = CGSize(width: 720, height: 460)

    var body: some View {
        Group {
            if let run = presenter.run {
                VStack(alignment: .leading, spacing: 0) {
                    header(run)
                    TerminalLogView(run: run)
                    footer(run)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.terminalSurface)
    }

    // MARK: - Header

    /// 窗口头部：图标、命令名与命令文本，右侧为操作按钮。
    private func header(_ run: CommandRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            SymbolImage(name: run.symbol, size: Self.headerGlyph)
                .foregroundStyle(Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(run.name)
                    .font(.headline)
                Text(run.commandText)
                    .font(Theme.Typography.code)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.md)
            actions(run)
        }
        // 顶部留白更少：透明标题栏本身已经在其上方贡献了高度。
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    /// 一个按钮只做一件事：运行中显示 Stop，结束后显示 Run Again。
    private func actions(_ run: CommandRun) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            CopyLogButton(log: run.log, settings: settings)
            if run.isRunning {
                iconButton("stop.fill", help: settings.text(CustomCommandsKey.outputStop)) {
                    presenter.stopRunning()
                }
            } else {
                iconButton("arrow.clockwise", help: settings.text(CustomCommandsKey.outputRunAgain)) {
                    presenter.runAgain()
                }
            }
        }
    }

    /// 头部使用的圆角图标按钮，带 tooltip 提示。
    private func iconButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        BarButton(chrome: .rounded, action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .tooltip(help)
    }

    // MARK: - Footer

    /// 底部状态栏：状态圆点、结果摘要、耗时与结束时间。
    private func footer(_ run: CommandRun) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(statusTint(run))
                .frame(width: Self.statusDot, height: Self.statusDot)
            if let outcome = run.outcome {
                Text(outcome.summary)
                Text("·")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(
                    CommandDuration.text(
                        from: run.startedAt, to: outcome.finishedAt,
                        language: settings.language))
            } else {
                Text(settings.text(CustomCommandsKey.outputRunning))
                Text("·")
                    .foregroundStyle(Theme.Colors.textTertiary)
                elapsed(from: run.startedAt)
            }
            Spacer(minLength: Theme.Spacing.md)
            if let outcome = run.outcome {
                Text(outcome.finishedAt, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.Colors.textSecondary)
        .overlay(alignment: .topLeading) { hint(run) }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    /// 自行按秒刷新，而无需窗口自己持有一个定时器。
    private func elapsed(from start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(
                CommandDuration.text(
                    from: start, to: context.date, language: settings.language)
            )
            .monospacedDigit()
        }
    }

    /// 悬浮在底栏之上而非嵌入其中：提示是一句话，而底栏只有一行。
    @ViewBuilder
    private func hint(_ run: CommandRun) -> some View {
        if let hint = run.outcome?.hint {
            HStack(spacing: Theme.Spacing.sm) {
                Text(hint)
                Button(settings.text(CustomCommandsKey.outputOpenSettings)) {
                    presenter.showCommandSettings()
                }
                .buttonStyle(.link)
            }
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize()
            .alignmentGuide(.top) { $0[.bottom] + Theme.Spacing.md }
        }
    }

    private static let statusDot: CGFloat = 7
    private static let headerGlyph: CGFloat = 15

    /// 状态圆点的颜色：运行中为进度色，结束后按成功/失败着色。
    private func statusTint(_ run: CommandRun) -> Color {
        guard let outcome = run.outcome else { return Theme.Colors.progress }
        return outcome.succeeded ? Theme.Colors.success : Theme.Colors.destructive
    }
}

/// 复制整份日志，随后短暂显示对勾作为反馈。
private struct CopyLogButton: View {
    let log: String
    let settings: AppSettings
    @State private var copiedAt: Date?

    var body: some View {
        BarButton(chrome: .rounded) {
            Paster.copyPlainText(log)
            copiedAt = Date()
        } label: {
            Image(systemName: copiedAt == nil ? "square.on.square" : "checkmark")
                .font(Theme.Typography.bar)
                .foregroundStyle(copiedAt == nil ? Theme.Colors.textSecondary : Theme.Colors.success)
        }
        .tooltip(settings.text(CustomCommandsKey.outputCopy))
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }
}

/// 耗时文本的唯一生成处。
enum CommandDuration {
    /// 将起止时间格式化为一位小数的秒、整秒或「分 秒」形式。
    static func text(from start: Date, to end: Date, language: AppLanguage) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 10 {
            return String(format: L10n.string(CustomCommandsKey.durationSeconds, language: language), seconds)
        }
        if seconds < 60 {
            return String(
                format: L10n.string(CustomCommandsKey.durationWholeSeconds, language: language),
                Int(seconds))
        }
        let whole = Int(seconds)
        return String(
            format: L10n.string(CustomCommandsKey.durationMinutesSeconds, language: language),
            whole / 60, whole % 60)
    }
}
