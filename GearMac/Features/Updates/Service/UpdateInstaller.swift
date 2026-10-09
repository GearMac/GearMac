// 文件职责：下载发布归档、校验其身份，并用它替换当前应用包。
// 分层：Service（更新安装编排）；用 ditto 解压、用 Security 校验签名，详见 docs/features/updates.md。
import Foundation

/// 获取发布归档、证明其归属，然后原地替换。详见 docs/features/updates.md。
struct UpdateInstaller: Sendable {
    /// 安装过程的各个阶段。
    enum Phase: Sendable, Equatable {
        case downloading(received: Int64, expected: Int64)
        case extracting
        case verifying
        case replacing

        /// 各阶段对应的进度文案。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .downloading(let received, let expected):
                return String(
                    format: L10n.string(UpdatesKey.phaseDownloading, language: language),
                    Self.size(received), Self.size(expected))
            case .extracting: return L10n.string(UpdatesKey.phaseExtracting, language: language)
            case .verifying: return L10n.string(UpdatesKey.phaseVerifying, language: language)
            case .replacing: return L10n.string(UpdatesKey.phaseReplacing, language: language)
            }
        }

        /// 只有下载阶段知道具体进度；其余阶段短促且无法量化。
        var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else {
                return nil
            }
            return min(1, Double(received) / Double(expected))
        }

        private static func size(_ bytes: Int64) -> String {
            bytes.formatted(.byteCount(style: .file))
        }
    }

    let bundleURL: URL
    let stagingDirectory: URL

    /// 依次完成下载、解压、校验与替换，并通过回调上报阶段。
    func install(
        _ release: AvailableRelease, onProgress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        try? FileManager.default.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)
        let archive = stagingDirectory.appendingPathComponent("\(release.tag).zip")
        let expanded = stagingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try? FileManager.default.removeItem(at: expanded)

        onProgress(.downloading(received: 0, expected: release.assetSize))
        for try await event in UpdateDownloader.download(release, to: archive) {
            guard case .progress(let received, let expected) = event else { continue }
            onProgress(.downloading(received: received, expected: expected))
        }

        onProgress(.extracting)
        let staged = try await expand(archive, into: expanded)

        onProgress(.verifying)
        try verify(staged, is: release)

        onProgress(.replacing)
        do {
            _ = try FileManager.default.replaceItemAt(
                bundleURL, withItemAt: staged, options: .usingNewMetadataOnly)
        } catch {
            throw UpdateFailure.replaceFailed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.removeItem(at: expanded)
    }

    private func expand(_ archive: URL, into directory: URL) async throws -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `ditto` 随 macOS 提供、能保持应用包封存完整，而 Foundation 没有解压能力。
        let result = try await ToolRunner.run(
            URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, directory.path])
        guard result.succeeded else { throw UpdateFailure.extractFailed(result.tail) }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        // 名称带通道标识——是 "GearMac Beta.app" 而不是 "GearMac.app"。
        guard let app = contents?.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateFailure.noAppInArchive
        }
        return app
    }

    /// 校验解压产物：清除隔离标记、核对 bundle ID 与版本，并验证签名。
    private func verify(_ staged: URL, is release: AvailableRelease) throws {
        if Quarantine.isSet(on: staged) { Quarantine.clear(from: staged) }
        // 宁可拒绝安装，也不让用户之后还得手动解除隔离。
        guard !Quarantine.isSet(on: staged) else { throw UpdateFailure.quarantined }

        let info = Self.info(at: staged)
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateFailure.bundleMismatch
        }
        let found = info?["CFBundleShortVersionString"] as? String
        guard found == release.version.description else {
            throw UpdateFailure.versionMismatch(
                expected: release.version.description, found: found ?? "unknown")
        }
        guard BundleSignature.isTrusted(staged) else { throw UpdateFailure.identityMismatch }
    }

    /// 直接从磁盘读取，而不是经由 `Bundle`——后者的缓存会返回旧副本的信息。
    private static func info(at bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appending(components: "Contents", "Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }
}
