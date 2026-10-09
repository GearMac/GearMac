// 文件职责：MCP 所使用的 JSON-RPC 2.0 编解码：两种传输共用一个编码器，stdio 以换行分帧。
// 分层：Model；不得 import AppKit/SwiftUI，仅做 JSON 编解码与消息解析。
import Foundation

/// MCP 所说的 JSON-RPC 2.0：两种传输共用一个编码器，stdio 以换行符分帧。
enum MCPProtocol {
    /// 从服务器收到的消息：响应、失败、通知、反向请求或无法解析。
    enum Message: Equatable {
        case response(id: Int, result: JSONValue)
        case failure(id: Int, message: String)
        case notification(method: String, params: JSONValue)
        case request(id: JSONValue, method: String)
        case invalid
    }

    /// 本实现所声明的 MCP 协议版本。
    static let version = "2025-06-18"

    /// 编码一条带 id 的 JSON-RPC 请求。
    static func request(
        id: Int, method: String, params: [String: Any]? = nil, newlineTerminated: Bool = false
    ) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { object["params"] = params }
        return try encode(object, newlineTerminated: newlineTerminated)
    }

    /// 编码一条无 id 的 JSON-RPC 通知。
    static func notification(
        method: String, params: [String: Any]? = nil, newlineTerminated: Bool = false
    ) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { object["params"] = params }
        return try encode(object, newlineTerminated: newlineTerminated)
    }

    /// GearMac 不对外暴露任何能力，因此服务器的反向请求一律以同样方式拒绝。
    static func decline(id: JSONValue, newlineTerminated: Bool = false) throws -> Data {
        try encode(
            [
                "jsonrpc": "2.0", "id": id.jsonObject,
                "error": ["code": -32_601, "message": "GearMac exposes no MCP capabilities."]
            ],
            newlineTerminated: newlineTerminated)
    }

    /// 把服务器返回的数据解析为 `Message`；无法解析时返回 `.invalid`。
    static func parse(_ data: Data) -> Message {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid
        }
        let numericID = (object["id"] as? NSNumber).flatMap {
            CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue
        }
        if let method = object["method"] as? String {
            guard let id = object["id"], !(id is NSNull) else {
                return .notification(method: method, params: JSONValue(object["params"] ?? [:]))
            }
            return .request(id: JSONValue(id), method: method)
        }
        guard let id = numericID else { return .invalid }
        if let error = object["error"] as? [String: Any] {
            return .failure(id: id, message: error["message"] as? String ?? "The server failed.")
        }
        guard let result = object["result"] else { return .invalid }
        return .response(id: id, result: JSONValue(result))
    }

    /// 序列化为 JSON；`newlineTerminated` 为真时在末尾追加换行。
    private static func encode(_ object: [String: Any], newlineTerminated: Bool) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        if newlineTerminated { data.append(0x0A) }
        return data
    }
}
