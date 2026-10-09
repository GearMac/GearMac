// 文件职责：解密 Raycast 的 `RAYCFG3` 导出容器（头部分析、scrypt 派生密钥、AES-GCM 解密与 gunzip）。
// 分层：Service；纯解码工具，无 UI 参与；详细格式见 docs/features/raycast-import.md。
import CryptoKit
import Foundation

/// 将 `RAYCFG3` 容器拆解到其中的 payload JSON。参见 docs/features/raycast-import.md。
enum RaycastDecoder {
    /// 容器头部明文部分：schema 版本与加密参数。
    private struct Header: Decodable {
        struct Encryption: Decodable {
            let iv: String
            let salt: String
        }

        let schemaVersion: Int
        let encryption: Encryption
    }

    /// 仅凭开头字节判断：在输入口令之前即可标注文件类型。
    static func isExport(_ raw: Data) -> Bool { raw.starts(with: magic) }

    /// 校验魔数/头部/版本后，用 scrypt 派生密钥以 AES-GCM 解开载荷并解压。
    static func decrypt(_ raw: Data, passphrase: String) throws -> Data {
        guard isExport(raw) else { throw RaycastImportError.notRaycastFile }
        // `raw` 可能是切片，因此下面所有偏移都从它自身的起点算起。
        let base = raw.startIndex
        guard raw.count >= fixedHeaderLength else { throw RaycastImportError.corrupt }
        let headerLength =
            Int(raw[base + 8]) | Int(raw[base + 9]) << 8
            | Int(raw[base + 10]) << 16 | Int(raw[base + 11]) << 24
        guard headerLength > 0, headerLength <= maximumHeaderLength,
            fixedHeaderLength + headerLength <= raw.count
        else { throw RaycastImportError.corrupt }

        let payloadStart = base + fixedHeaderLength + headerLength
        let payloadEnd = raw.endIndex - authenticationTagLength
        guard payloadEnd > payloadStart,
            let headerJSON = try? Zlib.gunzip(
                raw[(base + fixedHeaderLength)..<payloadStart], maxOutput: maximumHeaderLength),
            let header = try? JSONDecoder().decode(Header.self, from: headerJSON),
            header.schemaVersion == containerSchemaVersion,
            let iv = Data(hex: header.encryption.iv), iv.count == ivLength,
            let salt = Data(hex: header.encryption.salt), salt.count == saltLength
        else { throw RaycastImportError.corrupt }

        let key = Scrypt.derive(
            passphrase: Array(passphrase.utf8), salt: [UInt8](salt),
            n: 16384, r: 8, p: 1, dkLen: 32)
        let payloadGzip: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: iv),
                ciphertext: raw[payloadStart..<payloadEnd],
                tag: raw[payloadEnd...])
            payloadGzip = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.incorrectPassphrase
        }

        do {
            return try Zlib.gunzip(payloadGzip, maxOutput: maximumPayloadLength)
        } catch ZlibError.tooLarge {
            throw RaycastImportError.tooLarge
        } catch {
            throw RaycastImportError.corrupt
        }
    }

    private static let magic = Data("RAYCFG3\n".utf8)
    private static let containerSchemaVersion = 3
    private static let fixedHeaderLength = 12
    private static let maximumHeaderLength = 1024 * 1024
    // AES 已对这段数据做过认证；这里的上限只是内存保护。
    private static let maximumPayloadLength = 512 * 1024 * 1024
    private static let authenticationTagLength = 16
    private static let ivLength = 16
    private static let saltLength = 16
}

extension Data {
    /// 解析偶数长度的十六进制字符串；遇到任何非十六进制字符返回 nil。
    fileprivate init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)

        func nibble(_ char: UInt8) -> UInt8? {
            switch char {
            case 0x30...0x39: return char - 0x30
            case 0x61...0x66: return char - 0x61 + 10
            case 0x41...0x46: return char - 0x41 + 10
            default: return nil
            }
        }

        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        self = Data(bytes)
    }
}
