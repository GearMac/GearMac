// 文件职责：用 vDSP 计算实时频谱电平，驱动听写面板的波形条显示。
// 分层：Service/纯计算；仅在采集队列上调用，不访问 UI。
import Accelerate
import Foundation

/// 频谱分析器：把最近的采样变换为固定数量的对数频段电平。
final class DictationSpectrum {
    /// 波形条数量。
    static let barCount = 21
    /// 每次分析使用的采样窗口长度。
    private static let sampleCount = 512
    private let transform: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let bands: [Range<Int>]
    private var real = [Float](repeating: 0, count: sampleCount)
    private let imaginary = [Float](repeating: 0, count: sampleCount)
    private var outputReal = [Float](repeating: 0, count: sampleCount)
    private var outputImaginary = [Float](repeating: 0, count: sampleCount)

    /// 预先构造 FFT、Hann 窗与对数分布的频段边界。
    init() throws {
        transform = try vDSP.DiscreteFourierTransform(
            count: Self.sampleCount, direction: .forward,
            transformType: .complexComplex, ofType: Float.self)
        window = (0..<Self.sampleCount).map {
            0.5 - 0.5 * cos(2 * .pi * Float($0) / Float(Self.sampleCount - 1))
        }
        let edges = (0...Self.barCount).map {
            Int(32 * pow(5000.0 / 32, Double($0) / Double(Self.barCount)) * Double(Self.sampleCount) / 16_000)
        }
        bands = (0..<Self.barCount).map { edges[$0]..<max(edges[$0] + 1, edges[$0 + 1]) }
    }

    /// 用最近的采样计算各频段电平，并做非线性压缩便于显示。
    func levels(for samples: ArraySlice<Float>) -> [Float] {
        let recent = samples.suffix(Self.sampleCount)
        for index in real.indices {
            real[index] = index < recent.count ? recent[recent.startIndex + index] * window[index] : 0
        }
        transform.transform(
            inputReal: real, inputImaginary: imaginary,
            outputReal: &outputReal, outputImaginary: &outputImaginary)
        return bands.map { band in
            let energy = band.reduce(Float(0)) {
                $0 + outputReal[$1] * outputReal[$1] + outputImaginary[$1] * outputImaginary[$1]
            }
            let amplitude = sqrt(energy) / Float(Self.sampleCount)
            let level = max(0, (sqrt(amplitude) - 0.025) * 15)
            return level / sqrt(1 + level * level)
        }
    }
}
