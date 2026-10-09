// 文件职责：CoreML 推理的通用张量工具，提供 MLMultiArray 构造、模型加载、预测与结果解析。
// 分层：Helper/纯工具；封装 CoreML 与 Accelerate，不持有业务状态。
import Accelerate
import CoreML
import Foundation

/// 推理相关的失败原因。
enum DictationInferenceError: Error {
    case incompatibleModel, invalidAudio, outputLimit, parentExited
}

/// 对 MLMultiArray/MLModel 的薄封装，统一形状与数据类型约定。
enum DictationTensor {
    /// 创建指定形状、全部置零的 MLMultiArray（默认 float32）。
    static func zeros(_ shape: [Int], type: MLMultiArrayDataType = .float32) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
        array.withUnsafeMutableBytes { bytes, _ in
            _ = bytes.initializeMemory(as: UInt8.self, repeating: 0)
        }
        return array
    }

    /// 创建单个 int32 标量张量，常用于序列长度等输入。
    static func integer(_ value: Int, shape: [Int] = [1]) throws -> MLMultiArray {
        let array = try zeros(shape, type: .int32)
        array[0] = NSNumber(value: value)
        return array
    }

    /// 校验父进程存活后执行一次模型预测。
    static func predict(_ model: MLModel, _ inputs: [String: MLMultiArray]) throws -> MLFeatureProvider {
        try checkParent()
        return try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
    }

    /// 从输出特征中按名称取出 MLMultiArray，缺失即视为模型不兼容。
    static func array(_ name: String, from features: MLFeatureProvider) throws -> MLMultiArray {
        guard let array = features.featureValue(for: name)?.multiArrayValue else {
            throw DictationInferenceError.incompatibleModel
        }
        return array
    }

    /// 在 float16 的一维 scores 中找出最大值的下标（贪心解码用）。
    static func indexOfMaximum(in scores: MLMultiArray) throws -> Int {
        guard scores.count > 0, scores.dataType == .float16,
            scores.shape.last?.intValue == scores.count, scores.strides.last?.intValue == 1
        else {
            throw DictationInferenceError.incompatibleModel
        }
        let values = try [Float](unsafeUninitializedCapacity: scores.count) { values, initialized in
            try scores.withUnsafeBytes { bytes in
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                    height: 1, width: vImagePixelCount(scores.count), rowBytes: scores.count * 2)
                var destination = vImage_Buffer(
                    data: values.baseAddress!,
                    height: 1, width: vImagePixelCount(scores.count), rowBytes: scores.count * 4)
                let status = vImageConvert_Planar16FtoPlanarF(
                    &source, &destination, vImage_Flags(kvImageDoNotTile))
                guard status == kvImageNoError else {
                    throw DictationInferenceError.incompatibleModel
                }
            }
            initialized = scores.count
        }
        return Int(vDSP.indexOfMaximum(values).0)
    }

    /// 从目录加载 <name>.mlmodelc，并指定计算单元。
    static func load(_ name: String, at directory: URL, units: MLComputeUnits = .all) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        return try MLModel(
            contentsOf: directory.appendingPathComponent(name + ".mlmodelc"),
            configuration: configuration)
    }

    /// 父进程退出（被 init 收养）时抛错，避免辅助进程变成孤儿。
    static func checkParent() throws {
        guard getppid() != 1 else { throw DictationInferenceError.parentExited }
    }
}
