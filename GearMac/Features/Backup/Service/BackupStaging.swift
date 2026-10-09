// 文件职责：管理单次备份/导入运行的临时目录（staging），包括目录的创建、过期孤儿目录清理与用后删除。
// 分层：Service；目录位于 Caches 下，以便图片可硬链接且崩溃遗留目录能自然过期。
import Foundation

/// 一次运行的临时目录树；放在 Caches 中，因此 PNG 可硬链接，崩溃遗留的孤儿目录也能自然过期。
struct BackupStaging: Sendable {
    let root: URL

    /// 先清理容器中的过期目录，再为本次运行创建以 UUID 命名的子目录。
    init(base: URL = AppPaths.caches()) throws {
        let container = base.appendingPathComponent("backup-staging", isDirectory: true)
        Self.sweep(container)
        root = container.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 运行中途被杀会遗留目录树，而再没有其他机制回收它们。
    private static func sweep(_ container: URL) {
        let cutoff = Date().addingTimeInterval(-86_400)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let orphans =
            (try? FileManager.default.contentsOfDirectory(
                at: container, includingPropertiesForKeys: Array(keys))) ?? []
        for url in orphans {
            let modified = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
            if modified ?? .distantPast < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// 以当前 root 构造一个可读写的备份 bundle。
    var bundle: BackupBundle { BackupBundle(root: root) }

    /// 删除本次运行的临时目录树。
    func discard() {
        try? FileManager.default.removeItem(at: root)
    }
}
