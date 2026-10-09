// 文件职责：实现 Claude Agent SDK 的未公开控制信道协议——解析工具授权请求并生成应答帧。
// 分层：Model；纯协议编解码，不持有进程或 I/O 状态。
import Foundation

/// Claude 的授权信道：Agent SDK 未公开的线格式，集中收敛在这一个类型中。
enum ClaudeControlProtocol {
    /// CLI 挂起等待 GearMac 应答的一次调用。
    struct Request: Equatable, Sendable {
        let id: String
        let call: AIToolServerCall
        /// 允许时原样回传：CLI 采用自己发出的参数，绝不被改写。
        let input: JSONValue
    }

    /// 对于不是 GearMac 服务器工具询问的帧返回 `nil`。
    static func request(_ object: [String: Any]) -> Request? {
        guard object["type"] as? String == "control_request",
            let id = object["request_id"] as? String,
            let request = object["request"] as? [String: Any],
            request["subtype"] as? String == "can_use_tool",
            let name = request["tool_name"] as? String,
            let call = ClaudeMCPLaunch.route(name)
        else { return nil }
        return Request(
            id: id, call: call, input: JSONValue(request["input"] ?? [String: Any]()))
    }

    /// 应答内容；绝不使用 `updatedPermissions`，否则 CLI 会自行写入设置。
    static func response(to request: Request, allowed: Bool, message: String) -> Data? {
        let answer: [String: Any] =
            allowed
            ? ["behavior": "allow", "updatedInput": request.input.jsonObject]
            : ["behavior": "deny", "message": message]
        var line = try? JSONSerialization.data(
            withJSONObject: [
                "type": "control_response",
                "response": [
                    "subtype": "success", "request_id": request.id, "response": answer
                ]
            ])
        line?.append(0x0A)
        return line
    }

    /// 不属于我们工具询问的控制请求；不应答会让 CLI 一直等待。
    static func unsupportedRequestID(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "control_request", request(object) == nil else {
            return nil
        }
        return object["request_id"] as? String
    }

    /// 针对无法处理的请求返回错误应答帧。
    static func error(to id: String, message: String) -> Data? {
        var line = try? JSONSerialization.data(
            withJSONObject: [
                "type": "control_response",
                "response": ["subtype": "error", "request_id": id, "error": message]
            ])
        line?.append(0x0A)
        return line
    }

    /// `stream-json` 单轮所用的用户消息，并按 stdin 帧格式编码。
    static func userMessage(_ text: String, images: [AIImage] = []) -> Data? {
        let pictures: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ]
        }
        let content: Any = images.isEmpty ? text : pictures + [["type": "text", "text": text]]
        var line = try? JSONSerialization.data(
            withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
        line?.append(0x0A)
        return line
    }
}
