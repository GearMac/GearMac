// 文件职责：在 Apple `Compression` 之上补齐 gzip（RFC 1952）与 zlib（RFC 1950）的帧头、校验和与解压上限。
// 分层：Service；纯函数式实现，不依赖 AppKit/SwiftUI。
import Compression
import Foundation

/// 解压/解压过程中的错误类型。
enum ZlibError: Error { case notGzip, corrupt, tooLarge }

/// Apple 的 `Compression` 只支持原始 DEFLATE，因此帧结构与校验和都在这里完成。
enum Zlib {
    /// 该上限用于抵御压缩炸弹：导入信封在验签之前会先被解压。
    static let defaultMaxOutput = 64 * 1024 * 1024

    // MARK: - gzip (RFC 1952)

    /// 解压 gzip（RFC 1952）数据，超出 `maxOutput` 字节时抛错。
    static func gunzip(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        let bytes = [UInt8](data)
        // 魔数 (1f 8b) + deflate 方法 (08) + 10 字节固定头 + 8 字节尾部。
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw ZlibError.notGzip
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {  // FEXTRA：2 字节长度 + 载荷
            guard index + 2 <= bytes.count else { throw ZlibError.corrupt }
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        if flags & 0x08 != 0 { index = try skipCString(bytes, from: index) }  // FNAME
        if flags & 0x10 != 0 { index = try skipCString(bytes, from: index) }  // FCOMMENT
        if flags & 0x02 != 0 { index += 2 }  // FHCRC
        guard index < bytes.count - 8 else { throw ZlibError.corrupt }
        // 切片基于 `bytes` 而非 `data`：`data` 可能是索引从别处开始的切片。
        return try inflateRaw(Data(bytes[index..<(bytes.count - 8)]), maxOutput: maxOutput)
    }

    /// 将数据压缩为 gzip（RFC 1952）格式。
    static func gzip(_ data: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(try deflateRaw(data))
        out.append(littleEndian(crc32(data)))
        out.append(littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    // MARK: - zlib (RFC 1950)

    /// 解压 zlib（RFC 1950）数据；首字节不是 zlib 头时按裸 DEFLATE 处理。
    static func inflate(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        // 0x78 是 deflate 唯一产生的 CMF 字节；其他值说明已经是裸数据流。
        guard data.count > 6, data[data.startIndex] & 0x0f == 8 else {
            return try inflateRaw(data, maxOutput: maxOutput)
        }
        let start = data.startIndex + 2
        let end = data.endIndex - 4
        guard start < end else { throw ZlibError.corrupt }
        return try inflateRaw(data.subdata(in: start..<end), maxOutput: maxOutput)
    }

    /// 将数据压缩为 zlib（RFC 1950）格式。
    static func deflate(_ data: Data) throws -> Data {
        var out = Data([0x78, 0x9c])
        out.append(try deflateRaw(data))
        out.append(bigEndian(adler32(data)))
        return out
    }

    // MARK: - raw DEFLATE (RFC 1951)

    /// 解压原始 DEFLATE（RFC 1951）数据。
    static func inflateRaw(_ data: Data, maxOutput: Int = defaultMaxOutput) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_DECODE, maxOutput: maxOutput)
    }

    /// 将数据压缩为原始 DEFLATE（RFC 1951）数据。
    static func deflateRaw(_ data: Data) throws -> Data {
        try stream(data, operation: COMPRESSION_STREAM_ENCODE, maxOutput: Int.max)
    }

    // MARK: - Internals

    /// 跳过一个以 NUL 结尾的字符串，返回下一个字节的索引。
    private static func skipCString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0 { return i + 1 }
            i += 1
        }
        throw ZlibError.corrupt
    }

    /// 调用 `compression_stream` 完成一次编码或解码，并施加上限。
    private static func stream(
        _ input: Data, operation: compression_stream_operation, maxOutput: Int
    ) throws -> Data {
        let bufferSize = 256 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        // C 结构体没有零参初始化器；这些占位值在使用前会被覆盖。
        var handle = compression_stream(
            dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&handle, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR
        else { throw ZlibError.corrupt }
        defer { compression_stream_destroy(&handle) }

        enum Outcome { case done(Data), overflow, failed }
        let outcome: Outcome = input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return .done(Data()) }
            handle.src_ptr = base
            handle.src_size = raw.count
            var out = Data()
            while true {
                handle.dst_ptr = dst
                handle.dst_size = bufferSize
                let status = compression_stream_process(
                    &handle, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    out.append(dst, count: bufferSize - handle.dst_size)
                    if out.count > maxOutput { return .overflow }
                    if status == COMPRESSION_STATUS_END { return .done(out) }
                default:
                    return .failed
                }
            }
        }
        switch outcome {
        case .done(let data): return data
        case .overflow: throw ZlibError.tooLarge
        case .failed: throw ZlibError.corrupt
        }
    }

    /// CRC-32 查表，惰性构建一次。
    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    /// 计算数据的 CRC-32 校验和（gzip 尾部使用）。
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// 计算数据的 Adler-32 校验和（zlib 尾部使用）。
    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    /// 将 32 位整数编码为小端字节序列。
    private static func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)
        ])
    }

    /// 将 32 位整数编码为大端字节序列。
    private static func bigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ])
    }
}
