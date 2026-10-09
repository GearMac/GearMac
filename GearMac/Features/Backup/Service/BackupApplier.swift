// 文件职责：把备份 staging 目录中的内容应用到运行中的各 store（设置、剪贴板、片段、笔记、启动器学习数据）。
// 分层：Service；除启动器学习数据为整体替换外，其余均做合并导入，失败只记录不抛出。
import Foundation

/// 把 staging 产物写入运行中的 store：除启动器学习数据为整体替换外，其余均为合并。
@MainActor
enum BackupApplier {
    /// 应用备份后的汇总结果，供上层拼装提示文案。
    struct Summary: Sendable {
        var settings: SettingsBackup.ApplySummary?
        var clipboard = 0
        var snippets = 0
        var snippetsNeedEnabling = false
        var notes = 0
        var learning = 0
        /// 只上报而不抛出：这里的失败不能中断其后类别的处理。
        var problems: [String] = []
    }

    /// 按类别筛选逐个应用：设置、剪贴板、片段、笔记与学习数据，禁用流结束后返回汇总。
    static func apply(
        _ categories: Set<BackupCategory>, from bundle: BackupBundle, to core: AppCore,
        language: AppLanguage
    ) async -> Summary {
        var summary = Summary()
        if categories.contains(.configuration), let data = try? Data(contentsOf: bundle.settingsURL),
            let backup = try? SettingsBackup(json: data)
        {
            summary.settings = backup.apply(to: core)
        }
        if categories.contains(.clipboard) {
            summary.clipboard = await importClipboard(bundle, into: core.clipboardStore)
            if summary.clipboard > 0 { core.clipboardStore.load() }
        }
        if categories.contains(.snippets) {
            do {
                summary.snippets = try await applySnippets(bundle, to: core)
                summary.snippetsNeedEnabling =
                    summary.snippets > 0 && !core.settings.snippetsEnabled
            } catch {
                summary.problems.append(
                    String(
                        format: L10n.string(BackupKey.problemSnippets, language: language),
                        error.localizedDescription))
            }
        }
        if categories.contains(.notes) {
            summary.notes = await applyNotes(bundle, to: core)
        }
        if categories.contains(.learning) {
            summary.learning = applyLearning(bundle, to: core)
        }
        return summary
    }

    // MARK: - Parts

    /// 在主线程之外流式导入：恢复的剪贴板历史可达数十万条。
    private nonisolated static func importClipboard(
        _ bundle: BackupBundle, into store: ClipboardStore
    ) async -> Int {
        ClipboardStore.importStoredItems(
            inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir,
            bundle.clipboardItems().lazy.compactMap { staged($0, in: bundle) })
    }

    /// 该行仍然指向 staging 目录；store 在接受这条剪贴板记录时才接管对应的图片文件。
    private nonisolated static func staged(
        _ item: BackupClipboardItem, in bundle: BackupBundle
    ) -> ClipboardItem? {
        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            return ClipboardItem(
                id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: item.createdAt,
                sourceBundleID: item.sourceBundleID, pinnedAt: item.pinnedAt, tag: item.tag)
        case .image:
            guard let name = item.imageName, let url = bundle.clipboardImageURL(named: name) else {
                return nil
            }
            return ClipboardItem(
                id: UUID(), kind: .image, text: nil, imagePath: url.path,
                createdAt: item.createdAt, sourceBundleID: item.sourceBundleID,
                pinnedAt: item.pinnedAt, tag: item.tag)
        case .file:
            // 来自其他 Mac 的路径在本机没有对应文件，因此直接丢弃该行而不是留下无效记录。
            guard let path = item.text, FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            return ClipboardItem(
                id: UUID(), kind: .file, text: path, imagePath: nil, createdAt: item.createdAt,
                sourceBundleID: item.sourceBundleID, pinnedAt: item.pinnedAt, tag: item.tag)
        }
    }

    /// 从备份目录解析并去重导入 Markdown 片段，返回实际导入条数。
    private static func applySnippets(_ bundle: BackupBundle, to core: AppCore) async throws -> Int {
        let documents = bundle.documents(in: bundle.snippetsDirectory, extension: "md")
        guard !documents.isEmpty else { return 0 }
        // 先启动 store，使导入的片段立即被启动器使用，而不必等到下次启动。
        if core.settings.snippetsEnabled { await core.snippetsStore.start() }
        let existing = Set(core.snippetsStore.snippets.map { Pair($0.snippet.name, $0.snippet.text) })
        let incoming = documents.compactMap { document in
            try? SnippetMarkdownSerializer.parse(
                content: document.contents,
                fileURL: bundle.snippetsDirectory.appendingPathComponent(document.name))
        }
        // 去重：同一份备份重复导入不会留下第二份副本。
        let fresh = incoming.filter { !existing.contains(Pair($0.name, $0.text)) }
        guard !fresh.isEmpty else { return 0 }
        return try await core.snippetsStore.importSnippets(fresh).count
    }

    /// 把备份中的 Markdown 笔记导入笔记库，返回导入条数。
    private static func applyNotes(_ bundle: BackupBundle, to core: AppCore) async -> Int {
        let documents = bundle.documents(in: bundle.notesDirectory, extension: "md")
        guard !documents.isEmpty else { return 0 }
        return await core.notesStore.importNotes(
            documents.map {
                NotesRepository.Incoming(
                    title: ($0.name as NSString).deletingPathExtension, source: $0.contents)
            })
    }

    /// 用备份中的学习数据整体替换排序、常用 Emoji 与计算历史，返回替换的条目总数。
    private static func applyLearning(_ bundle: BackupBundle, to core: AppCore) -> Int {
        var applied = 0
        if let visits = bundle.decodeLearning(.ranking, as: [String: LauncherVisit].self) {
            core.launcherRanking.replace(visits)
            applied += visits.count
        }
        if let records = bundle.decodeLearning(.emoji, as: [FrequentEmoji].self) {
            core.frequentEmoji.replace(records)
            applied += records.count
        }
        if let entries = bundle.decodeLearning(.calculator, as: [CalcHistoryEntry].self) {
            core.calcHistory.replace(entries)
            applied += entries.count
        }
        return applied
    }

    /// 同时以名称与正文作为标识，所以同名但内容不同的两个片段都能在导入后保留。
    private struct Pair: Hashable {
        let name: String
        let text: String

        init(_ name: String, _ text: String) {
            self.name = name
            self.text = text
        }
    }
}
