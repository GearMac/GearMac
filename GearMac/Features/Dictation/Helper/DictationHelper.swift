// 文件职责：Dictation 辅助进程的入口，通过 stdin/stdout 的 DictationWire 协议接收识别请求并回写转录文本。
// 分层：Helper/独立进程入口；与主进程仅通过管道通信，不依赖 AppKit/SwiftUI。
import Foundation

/// 语音识别器的统一接口：输入归一化音频采样与可选语言，返回转录文本。
protocol DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String
}

/// QwenRecognizer 已提供匹配签名，直接遵循该接口。
extension QwenRecognizer: DictationRecognizer {}
/// ParakeetRecognizer 适配：忽略外部语言参数，仅使用其内置语言配置。
extension ParakeetRecognizer: DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try transcribe(samples)
    }
}

/// 辅助进程入口：按请求加载对应模型并在子进程中执行推理。
@main
enum DictationHelper {
    /// 循环读取请求、按需重载模型、校验音频并写回响应，直到 stdin 关闭或出错。
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        guard fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { exit(1) }
        var recognizer: (any DictationRecognizer)?
        var loaded: DictationModel?
        do {
            while let request = try DictationWire.read(DictationWire.Request.self, from: input) {
                try DictationTensor.checkParent()
                guard (1...DictationWire.maximumSamples).contains(request.sampleCount),
                    request.directory.isFileURL
                else {
                    throw DictationInferenceError.invalidAudio
                }
                if loaded != request.model {
                    recognizer = nil
                    loaded = nil
                    do {
                        recognizer = try autoreleasepool { () throws -> any DictationRecognizer in
                            request.model.isQwen
                                ? try QwenRecognizer(directory: request.directory)
                                : try ParakeetRecognizer(directory: request.directory, model: request.model)
                        }
                        loaded = request.model
                    } catch {
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output)
                        continue
                    }
                }
                guard let recognizer else { throw DictationInferenceError.incompatibleModel }
                try DictationWire.write(DictationWire.Response(id: request.id, status: .ready), to: output)
                try autoreleasepool {
                    let data = try DictationWire.readExactly(
                        request.sampleCount * MemoryLayout<Float>.size, from: input)
                    let samples = [Float](unsafeUninitializedCapacity: request.sampleCount) { buffer, count in
                        data.withUnsafeBytes { bytes in
                            UnsafeMutableRawBufferPointer(buffer).copyMemory(from: bytes)
                        }
                        count = request.sampleCount
                    }
                    guard samples.allSatisfy({ $0.isFinite }) else {
                        throw DictationInferenceError.invalidAudio
                    }
                    do {
                        let text = try recognizer.transcribe(samples, language: request.language)
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .result, text: text), to: output)
                    } catch {
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output)
                    }
                }
            }
        } catch {
            exit(1)
        }
    }
}
