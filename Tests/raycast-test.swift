// 文件职责：Raycast 迁移 harness，验证 RAYCFG3 容器签名识别与解密、gzip 解压（含切片与输出上限），以及剪贴板条目的映射与导入时保留策略。
// 分层：测试 harness；fixture 在进程内构造，不提交真实导出文件。
import CryptoKit
import Foundation

/// 独立运行的测试入口：依次执行各测试分组，最后打印通过/失败数并以失败数决定退出码。
@main
@MainActor
enum RaycastTests {
    static var failures = 0
    static var passes = 0

    /// 断言：条件为真则计入通过，否则计为失败并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 断言闭包会抛出指定的 RaycastImportError；expected 为 nil 时接受任一 RaycastImportError。
    static func expectThrows(
        _ message: String, _ expected: RaycastImportError? = nil,
        _ body: () throws -> some Any
    ) {
        do {
            _ = try body()
            failures += 1
            print("FAIL: \(message) — did not throw")
        } catch let error as RaycastImportError {
            guard let expected, error != expected else {
                passes += 1
                return
            }
            failures += 1
            print("FAIL: \(message) — threw \(error), expected \(expected)")
        } catch {
            passes += 1
        }
    }

    static func main() {
        recognition()
        decryption()
        gunzipSlices()
        gunzipCap()
        clipboardMapping()
        clipboardPinMetadata()
        clipboardRetention()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Fixtures

    /// gzip 压缩后的 `{"raycast_version":"1.104.24"}`，以 mtime 0 生成，保证字节稳定。
    static let gzippedJSON = Data([
        0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xab, 0x56,
        0x2a, 0x4a, 0xac, 0x4c, 0x4e, 0x2c, 0x2e, 0x89, 0x2f, 0x4b, 0x2d, 0x2a,
        0xce, 0xcc, 0xcf, 0x53, 0xb2, 0x52, 0x32, 0xd4, 0x33, 0x34, 0x30, 0xd1,
        0x33, 0x32, 0x51, 0xaa, 0x05, 0x00, 0x6f, 0xf1, 0x55, 0x48, 0x1e, 0x00,
        0x00, 0x00
    ])
    static let plainJSON = Data(#"{"raycast_version":"1.104.24"}"#.utf8)

    static let passphrase = "12345678"

    /// 在进程内构造，因此不提交任何真实导出文件；共享同一次 scrypt 派生。
    static let fixture: (file: Data, payloadStart: Int, futureSchema: Data)? = {
        let salt = Data(repeating: 0x22, count: 16)
        let iv = Data(repeating: 0x33, count: 16)
        let key = SymmetricKey(
            data: Scrypt.derive(
                passphrase: Array(passphrase.utf8), salt: [UInt8](salt),
                n: 16384, r: 8, p: 1, dkLen: 32))
        /// 把字节序列格式化为小写十六进制字符串。
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        /// 组装一个 RAYCFG3 文件：签名 + 压缩头长度 + 压缩头 + 密文 + tag。
        func container(schemaVersion: Int, sealed: AES.GCM.SealedBox) -> Data? {
            let header: [String: Any] = [
                "appVersion": "2.0.5.0",
                "schemaVersion": schemaVersion,
                "encryption": ["iv": hex(iv), "salt": hex(salt)]
            ]
            guard let headerJSON = try? JSONSerialization.data(withJSONObject: header),
                let compressedHeader = try? Zlib.gzip(headerJSON)
            else { return nil }
            var file = Data("RAYCFG3\n".utf8)
            let length = UInt32(compressedHeader.count)
            file.append(contentsOf: [
                UInt8(length & 0xff), UInt8((length >> 8) & 0xff),
                UInt8((length >> 16) & 0xff), UInt8(length >> 24)
            ])
            file.append(compressedHeader)
            file.append(sealed.ciphertext)
            file.append(sealed.tag)
            return file
        }
        guard let nonce = try? AES.GCM.Nonce(data: iv),
            let sealed = try? AES.GCM.seal(gzippedJSON, using: key, nonce: nonce),
            let file = container(schemaVersion: 3, sealed: sealed),
            let futureSchema = container(schemaVersion: 4, sealed: sealed)
        else { return nil }
        return (file, file.count - sealed.ciphertext.count - 16, futureSchema)
    }()

    // MARK: - Recognition

    /// 校验容器签名在读取正文之前就能被识别。
    static func recognition() {
        expect(
            RaycastDecoder.isExport(Data("RAYCFG3\n".utf8)),
            "the container signature is recognised before its body is read")
        expect(!RaycastDecoder.isExport(Data()), "empty data is not an export")
        expect(
            !RaycastDecoder.isExport(Data(repeating: 0xa5, count: 512)),
            "an unsigned blob is not an export")
        expect(
            !RaycastDecoder.isExport(Data("RAYCFG3".utf8)),
            "the signature includes its trailing newline")
    }

    // MARK: - Decrypt

    /// 校验解密：正确容器能还原载荷，而错误口令、签名缺失、头过短、未知 schema 与截断都被拒绝。
    static func decryption() {
        guard let fixture else {
            failures += 1
            print("FAIL: fixture encryption")
            return
        }
        let file = fixture.file

        expect(
            (try? RaycastDecoder.decrypt(file, passphrase: passphrase)) == plainJSON,
            "the container decrypts its length-prefixed gzip header and tagged payload")
        expectThrows("wrong passphrase", .incorrectPassphrase) {
            try RaycastDecoder.decrypt(file, passphrase: "wrong-passphrase")
        }

        // 切片会保留调用方的索引，因此解码器内部的偏移量不得假设索引从 0 开始。
        let padded = Data(repeating: 0x00, count: 7) + file
        expect(
            (try? RaycastDecoder.decrypt(padded.dropFirst(7), passphrase: passphrase)) == plainJSON,
            "a non-zero-based slice decrypts the same as the whole file")

        // 以下情况都在密钥派生之前被拒绝，因此都不必付出 scrypt 的开销。
        expectThrows("without the container signature", .notRaycastFile) {
            try RaycastDecoder.decrypt(file.dropFirst(), passphrase: passphrase)
        }
        expectThrows("shorter than the fixed header", .corrupt) {
            try RaycastDecoder.decrypt(file.prefix(11), passphrase: passphrase)
        }
        expectThrows("unknown container schema", .corrupt) {
            try RaycastDecoder.decrypt(fixture.futureSchema, passphrase: passphrase)
        }

        // 遍历载荷之前的每一种截断长度，确保没有任何偏移量会越界。
        var misclassified: [Int] = []
        for cut in 0..<fixture.payloadStart {
            let expected: RaycastImportError = cut < 8 ? .notRaycastFile : .corrupt
            do {
                _ = try RaycastDecoder.decrypt(file.prefix(cut), passphrase: "")
                misclassified.append(cut)
            } catch {
                if (error as? RaycastImportError) != expected { misclassified.append(cut) }
            }
        }
        expect(misclassified.isEmpty, "a truncated container is rejected, not read: \(misclassified)")

        var lengthsRead: [UInt32] = []
        for value: UInt32 in [0, 1, 0x0010_0001, 0xffff_ffff] {
            var damaged = file
            damaged[8] = UInt8(value & 0xff)
            damaged[9] = UInt8((value >> 8) & 0xff)
            damaged[10] = UInt8((value >> 16) & 0xff)
            damaged[11] = UInt8(value >> 24)
            if (try? RaycastDecoder.decrypt(damaged, passphrase: "")) != nil {
                lengthsRead.append(value)
            }
        }
        expect(lengthsRead.isEmpty, "an out-of-range header length is rejected: \(lengthsRead)")
    }

    // MARK: - Clipboard

    /// 构造一个合成剪贴板条目字典，pin 元数据可控。
    static func clipboardEntry(
        _ text: String, createdAt: String = "2001-01-01T00:00:00.123Z", pinned: Any? = nil
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "createdAt": createdAt,
            "items": [["representations": [["mimeType": "text/plain", "content": text]]]]
        ]
        entry["pinned"] = pinned
        return entry
    }

    /// 把合成 JSON 序列化后再解析，模拟导入路径并返回映射结果与缺失计数。
    static func clipboardImport(
        _ entries: [[String: Any]], existingImages: Set<String> = []
    ) -> (items: [ClipboardItem], missing: Int) {
        let json: [String: Any] = ["clipboardEntries": entries]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
            let decoded = try? JSONSerialization.jsonObject(with: data)
        else {
            expect(false, "the synthetic clipboard fixture serializes")
            return ([], 0)
        }
        return RaycastClipboardImport.parse(
            decoded, now: { Date(timeIntervalSince1970: 1_700_000_000) },
            fileExists: { existingImages.contains($0) })
    }

    /// 校验收据映射：text/plain 优先于富文本与图片、图片路径保留、createdAt 与 pin 元数据映射。
    static func clipboardMapping() {
        var text = clipboardEntry("unused", pinned: true)
        text["items"] = [
            [
                "representations": [
                    ["mimeType": "text/html", "content": "<b>rich text</b>"],
                    ["mimeType": "text/plain;charset=utf-8", "content": "plain text"],
                    ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/text.png"]
                ]
            ]
        ]
        let image: [String: Any] = [
            "createdAt": "2001-01-02T00:00:00Z", "pinned": true,
            "items": [
                [
                    "representations": [
                        ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/pin.png"]
                    ]
                ]
            ]
        ]
        var missingImage = image
        missingImage["items"] = [
            [
                "representations": [
                    ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/missing.png"]
                ]
            ]
        ]
        var unpinnedMissingImage = missingImage
        unpinnedMissingImage["pinned"] = false
        let result = clipboardImport(
            [text, clipboardEntry("ordinary", pinned: false), image, missingImage, unpinnedMissingImage],
            existingImages: ["/synthetic/pin.png"])
        expect(result.items.count == 3, "text and existing images import; missing images do not")
        expect(result.missing == 2, "missing images count equally with and without a pin")
        guard result.items.count == 3 else { return }
        let clip = result.items[0]
        expect(
            clip.kind == .text && clip.text == "plain text", "text/plain still wins over rich text and images"
        )
        expect(clip.imagePath == nil && clip.sourceBundleID == nil, "text paths and source stay unchanged")
        expect(
            abs(clip.createdAt.timeIntervalSince1970 - 978_307_200.123) < 0.000_001,
            "fractional createdAt is preserved")
        expect(
            clip.isPinned && clip.pinnedAt == clip.createdAt, "a Boolean pin uses the original creation date")
        expect(!result.items[1].isPinned, "an explicit false stays unpinned")
        let imageClip = result.items[2]
        expect(imageClip.kind == .image && imageClip.text == nil, "image kind and text stay unchanged")
        expect(imageClip.imagePath == "/synthetic/pin.png", "the original image path is preserved")
        expect(imageClip.sourceBundleID == nil, "an imported image still has no source bundle ID")
        expect(
            imageClip.createdAt == Date(timeIntervalSince1970: 978_393_600), "whole-second dates still parse")
        expect(imageClip.isPinned && imageClip.pinnedAt == imageClip.createdAt, "image pins are preserved")

        var emptyTextImage = image
        emptyTextImage["items"] = [
            [
                "representations": [
                    ["mimeType": "text/plain", "content": ""],
                    ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/pin.png"]
                ]
            ]
        ]
        expect(
            clipboardImport([emptyTextImage], existingImages: ["/synthetic/pin.png"]).items.first?.kind
                == .image,
            "empty text still falls through to an image")
    }

    /// 校验 pin 元数据容错：畸形或缺失的 pin 不丢弃文本，坏日期回退到当前时钟。
    static func clipboardPinMetadata() {
        let malformed: [Any?] = [nil, NSNull(), "true", "false", 0, 1, 42, 1.0, [], ["pinned": true]]
        for (index, value) in malformed.enumerated() {
            let result = clipboardImport([clipboardEntry("malformed \(index)", pinned: value)])
            expect(result.items.count == 1, "malformed or missing pin \(index) does not discard the text")
            expect(result.items.first?.isPinned == false, "malformed or missing pin \(index) stays unpinned")
        }
        for date in ["invalid", ""] {
            let clip = clipboardImport([clipboardEntry("fallback", createdAt: date, pinned: true)]).items
                .first
            expect(
                clip?.createdAt == Date(timeIntervalSince1970: 1_700_000_000), "bad dates still use the clock"
            )
            expect(
                clip?.isPinned == true && clip?.pinnedAt == clip?.createdAt,
                "a pin uses the fallback date too")
        }
        var absentDate = clipboardEntry("absent date", pinned: true)
        absentDate.removeValue(forKey: "createdAt")
        let clip = clipboardImport([absentDate]).items.first
        expect(
            clip?.isPinned == true && clip?.pinnedAt == clip?.createdAt,
            "missing createdAt still preserves a pin")
        let empty = RaycastClipboardImport.parse(nil, now: Date.init, fileExists: { _ in false })
        expect(empty.items.isEmpty && empty.missing == 0, "missing clipboard history stays empty")
    }

    /// 校验导入时的保留策略与 SQLite 持久化，包括置顶文本与图片。
    static func clipboardRetention() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("raycast-clipboard-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = clipboardImport(
            [
                clipboardEntry("later pin", createdAt: "2001-01-02T00:00:00Z", pinned: true),
                clipboardEntry("earlier pin", pinned: true),
                clipboardEntry("expired ordinary", pinned: false),
                clipboardEntry("recent ordinary", createdAt: Date().ISO8601Format(), pinned: false),
                [
                    "createdAt": "2001-01-03T00:00:00Z", "pinned": true,
                    "items": [
                        [
                            "representations": [
                                [
                                    "mimeType": "image/png", "contentType": "url",
                                    "content": "/synthetic/retained.png"
                                ]
                            ]
                        ]
                    ]
                ]
            ], existingImages: ["/synthetic/retained.png"])
        let store = ClipboardStore(directory: root)
        expect(
            store.maxAge == ClipboardRetention.threeMonths.maxAge,
            "the default retention remains three months")
        expect(store.importEntries(imported.items) == 5, "all mapped candidates reach the real store")
        expect(
            store.search("", filter: .all).compactMap(\.text) == [
                "earlier pin", "later pin", "recent ordinary"
            ],
            "old pins survive immediate pruning in deterministic date order; old unpinned text does not")
        store.enforceLimits()
        expect(
            store.items.filter(\.isPinned).count == 3, "subsequent retention also keeps text and image pins")
        store.close()
        let reopened = ClipboardStore(directory: root)
        reopened.load()
        expect(
            reopened.search("", filter: .all).compactMap(\.text) == [
                "earlier pin", "later pin", "recent ordinary"
            ],
            "pins and pruning persist in SQLite across a reload")
        expect(
            reopened.items.filter(\.isPinned).allSatisfy { $0.pinnedAt == $0.createdAt },
            "the original pin metadata is persisted, not just held in the import array")
        expect(
            reopened.items.contains { $0.isPinned && $0.imagePath == "/synthetic/retained.png" },
            "an old pinned image survives import-time retention and reload too")
    }

    // MARK: - Zlib

    /// 校验 gzip 解压对非零起始索引切片、零起始数据与非 gzip 数据的处理。
    static func gunzipSlices() {
        // `decompress` 索引的是一份从 0 开始的副本，因此切片不得被重新索引。
        var prefixed = Data(repeating: 0xa5, count: 32)
        prefixed.append(gzippedJSON)
        expect(
            (try? Zlib.gunzip(prefixed.dropFirst(32))) == plainJSON,
            "a non-zero-index gzip slice decompresses instead of trapping")
        expect((try? Zlib.gunzip(gzippedJSON)) == plainJSON, "a zero-based gzip still works")
        expect((try? Zlib.gunzip(Data(repeating: 0x00, count: 32))) == nil, "non-gzip throws")
    }

    /// 在此处构造、从不提交：超过默认上限的 fixture 不能放进仓库。
    static func gunzipCap() {
        let oversized = Data(repeating: 0x5a, count: 70 * 1024 * 1024)
        guard let gzipped = try? Zlib.gzip(oversized) else {
            failures += 1
            print("FAIL: the oversized fixture did not gzip")
            return
        }
        do {
            _ = try Zlib.gunzip(gzipped)
            failures += 1
            print("FAIL: a 70 MB payload passed the 64 MB default cap")
        } catch ZlibError.tooLarge {
            passes += 1
        } catch {
            failures += 1
            print("FAIL: the default cap threw \(error), expected tooLarge")
        }
        expect(
            (try? Zlib.gunzip(gzipped, maxOutput: 512 * 1024 * 1024))?.count == oversized.count,
            "the same payload inflates under the 512 MB payload cap")
    }
}
