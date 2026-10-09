// 文件职责：设置面板的「备份与恢复」页面：导出/导入 GearMac 备份、导入 Raycast 导出，以及 settings.json 镜像开关。
// 分层：UI；只负责展示、选择状态与把动作转发给 BackupActions，不直接操作 store。
import AppKit
import SwiftUI

/// 备份与恢复设置面板。
struct BackupSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var runningApps: RunningAppsMonitor { core.runningApps }
    @State private var raycastFile: URL?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var status: Status?
    @State private var selection: RaycastImportOptions = .all
    @State private var isRaycastExport = false
    @State private var exportSelection = BackupCategory.all
    @State private var importSelection: Set<BackupCategory> = []
    @State private var exporting = false
    @State private var importingBackup = false
    @State private var backupStatus: Status?
    @State private var backupFile: URL?
    @State private var openedManifest: BackupManifest?
    /// 在打开文件与执行导入之间持有，使解压出来的目录树不会因文件选择器而丢失。
    @State private var openedStaging: BackupStaging?

    /// 单行状态提示：成功或失败文案。
    private enum Status {
        case success(String)
        case failure(String)
    }

    /// 当前是否有 Raycast 在运行（含各发布渠道）。
    private var raycastRunning: Bool {
        runningApps.runningBundleIDs.contains(where: BackupActions.isRaycastBundleID)
    }

    /// 开启时可能先弹窗询问，因此开关状态跟随设置值而非点击结果。
    private var settingsFileSync: Binding<Bool> {
        Binding(
            get: { core.settings.settingsFileEnabled },
            set: { enabled in Task { await BackupActions.setSettingsFileEnabled(enabled, core: core) } })
    }

    /// `.rayconfig` 选择器的副标题：未选择时提示格式说明，已选时显示文件名与类型判定。
    private var raycastFileSubtitle: String {
        guard let name = raycastFile?.lastPathComponent else {
            return settings.text(BackupKey.raycastFileHint)
        }
        let key =
            isRaycastExport ? BackupKey.raycastFileIsExport : BackupKey.raycastFileNotExport
        return String(format: settings.text(key), name)
    }

    /// 面板主体：导出、导入备份、从 Raycast 导入、设置文件镜像四个分组。
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if exporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(settings.text(BackupKey.buttonExport)) { runExport() }
                            .disabled(exportSelection.isEmpty)
                    }
                } label: {
                    SettingsRowTitle(.backupExport, settings.text(BackupKey.exportSection))
                    Text(settings.text(BackupKey.exportSubtitle))
                }
                BackupCategorySelection(selection: $exportSelection)
                if let backupStatus { statusRow(backupStatus) }
            } header: {
                SettingsSectionHeader(.backupExport)
            }

            Section {
                LabeledContent {
                    Button(settings.text(BackupKey.buttonChoose)) { chooseBackupFile() }
                } label: {
                    SettingsRowTitle(.backupImport, settings.text(BackupKey.importSection))
                    Text(backupFileSubtitle)
                }
                if let manifest = openedManifest {
                    BackupCategorySelection(
                        selection: $importSelection, available: available(in: manifest))
                    LabeledContent {
                        if importingBackup {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(settings.text(BackupKey.buttonImport)) { runBackupImport() }
                                .disabled(importSelection.isEmpty)
                        }
                    } label: {
                        Text(settings.text(BackupKey.buttonImport))
                    }
                }
            } header: {
                SettingsSectionHeader(.backupImport)
            }

            Section {
                LabeledContent {
                    Button(settings.text(BackupKey.buttonChoose)) { chooseRaycastFile() }
                } label: {
                    SettingsRowTitle(
                        .backupImportFromRaycast, settings.text(BackupKey.raycastSection))
                    Text(raycastFileSubtitle)
                }
                LabeledContent {
                    RevealableSecureField(
                        title: settings.text(BackupKey.passphrase), text: $passphrase,
                        prompt: Text(settings.text(BackupKey.passphrasePrompt))
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    // LabeledContent 会把值文本（含光标）右对齐；输入框应左对齐阅读。
                    .multilineTextAlignment(.leading)
                    .frame(width: 160)
                    .onSubmit(runRaycastImport)
                } label: {
                    Text(settings.text(BackupKey.passphrase))
                }
                RaycastImportSelection(selection: $selection)
                conflictNotice
                LabeledContent {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(settings.text(BackupKey.buttonImport)) { runRaycastImport() }
                            .disabled(!isRaycastExport || passphrase.isEmpty || selection.isEmpty)
                    }
                } label: {
                    Text(settings.text(BackupKey.buttonImport))
                }
                if let status { statusRow(status) }
            } header: {
                SettingsSectionHeader(.backupImportFromRaycast)
            }

            Section {
                Toggle(isOn: settingsFileSync) {
                    SettingsRowTitle(
                        .backupSettingsFile, settings.text(BackupKey.settingsFileSection))
                    Text(BackupActions.settingsFilePath)
                }
                if core.settings.settingsFileEnabled {
                    LabeledContent {
                        Button(
                            settings.text(BackupKey.settingsFileShowInFinder),
                            action: BackupActions.revealSettingsFile)
                    } label: {
                        Text(settings.text(BackupKey.settingsFileDescription))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SettingsSectionHeader(.backupSettingsFile)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.backup)
        .onDisappear { if !importingBackup { discardStagedBackup() } }
    }

    /// Raycast 快捷键冲突提示：正在运行时给出退出按钮，否则给出提示性文案。
    @ViewBuilder
    private var conflictNotice: some View {
        if raycastRunning {
            LabeledContent {
                Button(settings.text(BackupKey.raycastQuit)) { BackupActions.quitRaycast() }
            } label: {
                Label(
                    settings.text(BackupKey.raycastRunning),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } else {
            Label(
                settings.text(BackupKey.raycastUnsetShortcuts),
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    /// 根据状态类型渲染绿色成功或橙色警告行。
    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    /// 备份文件选择器的副标题：未选择时说明格式，已选时显示名称或读取失败提示。
    private var backupFileSubtitle: String {
        guard let name = backupFile?.lastPathComponent else {
            return settings.text(BackupKey.backupFileHint)
        }
        guard openedManifest != nil else {
            return String(format: settings.text(BackupKey.backupFileUnreadable), name)
        }
        return name
    }

    /// 从 manifest 中提取可用类别及其数量，供多选框展示。
    private func available(in manifest: BackupManifest) -> [BackupCategory: Int] {
        Dictionary(
            uniqueKeysWithValues: BackupCategory.ordered(manifest.categories).map {
                ($0, manifest.count($0))
            })
    }

    /// 在后台导出选中的类别，并把结果写入状态提示。
    private func runExport() {
        guard !exporting else { return }
        exporting = true
        backupStatus = nil
        let categories = exportSelection
        Task {
            defer { exporting = false }
            do {
                let result = try await BackupActions.exportBackup(
                    core: core, categories: categories)
                backupStatus = .success(
                    BackupActions.exportText(result, language: settings.language))
            } catch is CancellationError {
                // 用户关闭了保存面板；无需汇报。
            } catch {
                backupStatus = .failure(
                    BackupActions.message(for: error, language: settings.language))
            }
        }
    }

    /// 选择备份文件并预先打开：成功后记录 staging 与 manifest，供后续选择类别再导入。
    private func chooseBackupFile() {
        guard let url = BackupActions.chooseBackupFile() else { return }
        discardStagedBackup()
        backupFile = url
        backupStatus = nil
        Task {
            do {
                let (staging, manifest) = try await BackupActions.openBackup(at: url)
                openedStaging = staging
                openedManifest = manifest
                importSelection = manifest.categories
            } catch {
                backupStatus = .failure(
                    BackupActions.message(for: error, language: settings.language))
            }
        }
    }

    /// 将已打开的 backup staging 按选定类别应用到运行中的 AppCore，并清理临时目录。
    private func runBackupImport() {
        guard let staging = openedStaging, !importingBackup, !importSelection.isEmpty else {
            return
        }
        importingBackup = true
        let categories = importSelection
        Task {
            defer { importingBackup = false }
            let summary = await BackupActions.applyBackup(
                categories, from: staging, to: core)
            // staging 中的文件在应用过程中已被各 store 接管，因此无论结果如何都要清理目录树。
            discardStagedBackup()
            backupFile = nil
            if let summary {
                backupStatus = .success(
                    BackupActions.summaryText(summary, language: settings.language))
            }
        }
    }

    /// 解压出的目录树可达数 GB，因此离开面板时必须回收它。
    private func discardStagedBackup() {
        openedStaging?.discard()
        openedStaging = nil
        openedManifest = nil
    }

    /// 选择 `.rayconfig` 文件并预先判断它是否为 Raycast 导出（未通过时不启用导入按钮）。
    private func chooseRaycastFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        raycastFile = url
        isRaycastExport = BackupActions.isRaycastExport(url)
        status = nil
    }

    /// 在后台读取并应用 Raycast 导出，成功后清空口令并展示结果文案。
    private func runRaycastImport() {
        guard let file = raycastFile, isRaycastExport, !passphrase.isEmpty, !selection.isEmpty,
            !importing
        else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    core: core, file: file, passphrase: passphrase, options: selection)
                status = .success(
                    BackupActions.raycastText(outcome, language: settings.language))
                passphrase = ""
            } catch {
                status = .failure(
                    BackupActions.message(for: error, language: settings.language))
            }
        }
    }
}
