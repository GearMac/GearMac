// 文件职责：导出备份的组装：先读取各 store 生成可跨线程传递的 Plan，再在后台将字节写入 staging bundle。
// 分层：Service；`plan` 在主线程读，`write` 在主线程之外写 IO，Plan 为 Sendable。
import Foundation

/// 从各 store 读取数据到 staging bundle：`plan` 在主 actor 读取，`write` 把全部 IO 放在主线程之外。
@MainActor
enum BackupComposer {
    /// 写入所需的一切内容，以 `Sendable` 形式装适，使繁重的写入部分可以离开主 actor。
    struct Plan: Sendable {
        var categories: Set<BackupCategory>
        var appVersion: String
        var settings: Data?
        var clipboardDatabase: URL?
        var snippetsDirectory: URL?
        var notesDirectory: URL?
        var learning: [BackupBundle.LearningPart: Data] = [:]
        var learningRecords = 0
    }

    /// 写入完成后的结果：manifest 与缺失图片计数。
    struct Result: Sendable {
        var manifest: BackupManifest
        /// 图片文件已丢失的剪贴板记录数；只上报而不静默丢弃。
        var missingImages: Int
    }

    /// 按选定类别从运行中的 AppCore 收集导出数据与文件路径，组装为可传递的 Plan。
    static func plan(_ categories: Set<BackupCategory>, from core: AppCore) -> Plan {
        var plan = Plan(
            categories: categories,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "unknown")
        if categories.contains(.configuration) {
            plan.settings = try? SettingsBackup.gather(from: core).encoded()
        }
        if categories.contains(.clipboard) { plan.clipboardDatabase = core.clipboardStore.dbURL }
        if categories.contains(.snippets) {
            plan.snippetsDirectory = core.snippetsStore.snippetsDirectory
        }
        if categories.contains(.notes) { plan.notesDirectory = core.notesStore.notesDirectory }
        if categories.contains(.learning) {
            // 从内存而非文件读取：排序 store 是异步落盘的。
            let encoder = BackupBundle.encoder
            plan.learning[.ranking] = try? encoder.encode(core.launcherRanking.visits)
            plan.learning[.emoji] = try? encoder.encode(core.frequentEmoji.records)
            plan.learning[.calculator] = try? encoder.encode(core.calcHistory.entries)
            plan.learningRecords =
                core.launcherRanking.visits.count + core.frequentEmoji.records.count
                + core.calcHistory.entries.count
        }
        return plan
    }

    /// 在后台将 Plan 写入 bundle 并回写 manifest，返回计数与缺失图片数。
    nonisolated static func write(_ plan: Plan, into bundle: BackupBundle) throws -> Result {
        try bundle.prepare(plan.categories)
        var counts: [String: Int] = [:]
        var missingImages = 0

        if let settings = plan.settings {
            try bundle.write(settings, to: bundle.settingsURL)
            counts[BackupCategory.configuration.rawValue] = 1
        }
        if let database = plan.clipboardDatabase {
            let outcome = try writeClipboard(from: database, into: bundle)
            counts[BackupCategory.clipboard.rawValue] = outcome.written
            missingImages = outcome.missing
        }
        if let directory = plan.snippetsDirectory {
            counts[BackupCategory.snippets.rawValue] = try copyDocuments(
                from: directory, to: bundle.snippetsDirectory)
        }
        if let directory = plan.notesDirectory {
            counts[BackupCategory.notes.rawValue] = try copyDocuments(
                from: directory, to: bundle.notesDirectory)
        }
        if !plan.learning.isEmpty {
            for (part, data) in plan.learning { try bundle.write(data, to: bundle.learningURL(part)) }
            counts[BackupCategory.learning.rawValue] = plan.learningRecords
        }

        let manifest = BackupManifest(
            appVersion: plan.appVersion, createdAt: Date(), counts: counts)
        try bundle.writeManifest(manifest)
        return Result(manifest: manifest, missingImages: missingImages)
    }

    // MARK: - Parts

    /// 逐条导出剪贴板记录并写入 bundle，返回成功写入数与图片缺失数。
    private nonisolated static func writeClipboard(
        from database: URL, into bundle: BackupBundle
    )
        throws -> (written: Int, missing: Int)
    {
        let writer = try bundle.clipboardWriter()
        var written = 0
        var missing = 0
        var failure: Error?
        ClipboardStore.forEachStoredItem(inDatabaseAt: database) { item in
            guard failure == nil else { return }
            do {
                guard let portable = try portableItem(item, into: bundle) else {
                    missing += 1
                    return
                }
                try writer.write(portable)
                written += 1
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return (written, missing)
    }

    /// 图片已丢失时返回 nil；在卷允许时使用硬链接，使 PNG 只多占一个 inode。
    /// 把一条剪贴板记录转换为可搬运的备份项（图片另存并记下文件名）。
    private nonisolated static func portableItem(
        _ item: ClipboardItem, into bundle: BackupBundle
    )
        throws -> BackupClipboardItem?
    {
        var imageName: String?
        if item.kind == .image {
            guard let path = item.imagePath,
                FileManager.default.fileExists(atPath: path)
            else { return nil }
            let source = URL(fileURLWithPath: path)
            // 沿用已存储图片自身的文件名，使同一张图两次导出得到相同名称。
            var name = source.lastPathComponent
            var destination = bundle.clipboardImagesDirectory.appendingPathComponent(name)
            if !BackupBundle.isSafeName(name)
                || FileManager.default.fileExists(atPath: destination.path)
            {
                name = UUID().uuidString + ".png"
                destination = bundle.clipboardImagesDirectory.appendingPathComponent(name)
            }
            if (try? FileManager.default.linkItem(at: source, to: destination)) == nil {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            imageName = name
        }
        // 引用型文件仅导出其路径；备份不会携带自己从未持有的字节内容。
        if item.kind == .file, item.filePath.map(FileManager.default.fileExists) != true {
            return nil
        }
        let kind: BackupClipboardItem.Kind
        switch item.kind {
        case .text: kind = .text
        case .image: kind = .image
        case .file: kind = .file
        }
        return BackupClipboardItem(
            kind: kind, text: item.text, imageName: imageName,
            createdAt: item.createdAt, sourceBundleID: item.sourceBundleID,
            pinnedAt: item.pinnedAt, tag: item.tag)
    }

    /// 原样拷贝 Markdown：两侧仓库都以 `.md` 读回，因此往返不丢信息。
    private nonisolated static func copyDocuments(
        from source: URL, to destination: URL
    ) throws
        -> Int
    {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        var copied = 0
        for name in names.sorted() where (name as NSString).pathExtension == "md" {
            guard BackupBundle.isSafeName(name) else { continue }
            // 先解析符号链接：笔记若为链接必须以文件形式携带，因为读取端不接受链接。
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(name).resolvingSymlinksInPath(),
                to: destination.appendingPathComponent(name))
            copied += 1
        }
        return copied
    }
}
