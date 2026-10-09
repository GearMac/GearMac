// 文件职责：主进程与听写辅助进程之间的管道协议（长度前缀 + JSON）与共享常量。
// 分层：Service/协议定义；nonisolated，可跨 actor 与进程使用。
import Foundation

/// 管道消息编解码：4 字节小端长度前缀后跟 JSON 负载。
nonisolated enum DictationWire {
    /// 听写流程对用户可见的失败原因。
    enum Failure: LocalizedError {
        case notInstalled, busy, unavailable
        var errorDescription: String? {
            switch self {
            case .notInstalled: "Download the selected dictation model first."
            case .busy: "Wait for the current dictation to finish."
            case .unavailable: "The dictation model couldn't process the recording."
            }
        }
    }

    /// 采样率（16 kHz）。
    static let sampleRate = 16_000
    /// 单次听写最大采样数（5 分钟）。
    static let maximumSamples = sampleRate * 60 * 5
    /// 单条消息的最大字节数。
    static let maximumMessageBytes = 64_000

    /// 一次识别请求：模型、采样数与可选语言。
    struct Request: Codable, Sendable {
        let id: UUID
        let model: DictationModel
        let directory: URL
        let sampleCount: Int
        let language: String?
    }

    /// 辅助进程的应答：ready/result/failed 三态。
    struct Response: Codable, Sendable {
        enum Status: String, Codable { case ready, result, failed }
        let id: UUID
        let status: Status
        var text = ""
    }

    /// 读取一条长度前缀消息并解码，流结束返回 nil。
    static func read<Value: Decodable>(_ type: Value.Type, from handle: FileHandle) throws -> Value? {
        guard let header = try handle.read(upToCount: 1), !header.isEmpty else { return nil }
        let bytes = header + (try readExactly(3, from: handle))
        let length = bytes.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        guard (1...maximumMessageBytes).contains(length) else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(type, from: readExactly(length, from: handle))
    }

    /// 编码并写入一条长度前缀消息。
    static func write<Value: Encodable>(_ value: Value, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumMessageBytes else { throw CocoaError(.coderInvalidValue) }
        var length = UInt32(data.count).littleEndian
        try withUnsafeBytes(of: &length) { try handle.write(contentsOf: $0) }
        try handle.write(contentsOf: data)
    }

    /// 从 handle 准确读取 count 字节，不足即报错。
    static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let bytes = try handle.read(upToCount: count - data.count), !bytes.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            data.append(bytes)
        }
        return data
    }
}
