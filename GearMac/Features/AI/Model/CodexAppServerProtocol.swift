// 文件职责：编解码 `codex app-server` 的 JSON-RPC 行协议（请求、通知、应答与错误）。
// 分层：Model；纯序列化/反序列化，不持有连接状态。
import Foundation

/// `codex app-server` 的 JSON-RPC 行协议。
enum CodexAppServerProtocol {
    /// 请求 ID，可为整数或字符串。
    enum RequestID: Equatable, Sendable {
        case integer(Int)
        case string(String)

        /// 还原为 JSON 可编码的原始值。
        var jsonValue: Any {
            switch self {
            case .integer(let value): return value
            case .string(let value): return value
            }
        }
    }

    /// 解析后的入站消息种类。
    enum Message {
        case response(id: Int, result: [String: JSONValue])
        case failure(id: Int, message: String)
        case notification(method: String, params: [String: JSONValue])
        case request(id: RequestID, method: String, params: [String: JSONValue])
        case invalid
    }

    /// 编码一个带 id 的请求行。
    static func request(id: Int, method: String, params: [String: Any]) throws -> Data {
        try line(["id": id, "method": method, "params": params])
    }

    /// 编码一个无 id 的通知行。
    static func notification(method: String, params: [String: Any] = [:]) throws -> Data {
        try line(["method": method, "params": params])
    }

    /// 编码一次成功应答。
    static func response(id: RequestID, result: [String: Any]) throws -> Data {
        try line(["id": id.jsonValue, "result": result])
    }

    /// 编码一次错误应答（错误码 -32601）。
    static func errorResponse(id: RequestID, message: String) throws -> Data {
        try line(["id": id.jsonValue, "error": ["code": -32_601, "message": message]])
    }

    /// 解析一行入站 JSON，识别为应答、失败、通知或请求。
    static func parse(_ data: Data) -> Message {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid
        }
        let numericID = (object["id"] as? NSNumber)?.intValue
        let requestID: RequestID?
        if let numericID {
            requestID = .integer(numericID)
        } else if let stringID = object["id"] as? String {
            requestID = .string(stringID)
        } else {
            requestID = nil
        }
        if let method = object["method"] as? String {
            let params = (object["params"] as? [String: Any] ?? [:]).mapValues(JSONValue.init)
            if let requestID { return .request(id: requestID, method: method, params: params) }
            return .notification(method: method, params: params)
        }
        guard let id = numericID else { return .invalid }
        if let result = object["result"] as? [String: Any] {
            return .response(id: id, result: result.mapValues(JSONValue.init))
        }
        if let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return .failure(id: id, message: message)
        }
        return .invalid
    }

    /// 序列化对象并追加换行，作为一行 JSON-RPC 帧。
    private static func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }
}
