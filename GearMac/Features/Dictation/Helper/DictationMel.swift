// 文件职责：Qwen 识别器的 log-mel 特征提取，用 vDSP 实现 Whisper 风格的 128 频带频谱。
// 分层：Helper/纯计算；基于 Accelerate，不做 I/O，不持有外部状态。
import Accelerate
import Foundation

/// 计算 log-mel 频谱特征：将 16 kHz 单声道采样转为 128 频带的归一化矩阵。
final class DictationMel {
    private let transform: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let filters: [Float]
    private let rotations: [(real: Float, imaginary: Float)]
    static let lengths = [100, 200, 400, 600, 800, 1000, 1500, 2000, 3000]

    /// 预计算 FFT、Hann 窗、梅尔滤波器组与旋转因子，供 features 复用。
    init() throws {
        // Accelerate 支持 80 点 FFT，但不支持 Whisper 需要的 400 点窗口；因此拆成 5 个 80 点变换再合并。
        transform = try vDSP.DiscreteFourierTransform(
            count: 80, direction: .forward,
            transformType: .complexComplex, ofType: Float.self)
        window = (0..<400).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / 400) }
        rotations = (0..<5).flatMap { residue in
            (0..<201).map { bin in
                let angle = -2 * Float.pi * Float(bin * residue) / 400
                return (cos(angle), sin(angle))
            }
        }
        func mel(_ hz: Float) -> Float {
            hz < 1000 ? hz / (200 / 3) : 15 + log(hz / 1000) / (log(6.4) / 27)
        }
        func hz(_ mel: Float) -> Float {
            mel < 15 ? mel * (200 / 3) : 1000 * exp((mel - 15) * (log(6.4) / 27))
        }
        let edges = (0..<130).map { hz(Float($0) * mel(8000) / 129) }
        filters = (0..<128).flatMap { band in
            (0..<201).map { bin -> Float in
                let frequency = Float(bin) * 40
                let rising = (frequency - edges[band]) / (edges[band + 1] - edges[band])
                let falling = (edges[band + 2] - frequency) / (edges[band + 2] - edges[band + 1])
                return max(0, min(rising, falling)) * 2 / (edges[band + 2] - edges[band])
            }
        }
    }

    /// 提取特征：返回展平的 log-mel 值、实际帧数与补齐后的帧长度 length。
    func features(_ samples: ArraySlice<Float>) throws -> (values: [Float], frames: Int, length: Int) {
        let frames = samples.count / 160
        guard frames > 0, let length = Self.lengths.first(where: { $0 >= frames }) else {
            throw DictationInferenceError.invalidAudio
        }
        var powers = [Float](repeating: 0, count: 201 * length)
        var real = [Float](repeating: 0, count: 80)
        let imaginary = [Float](repeating: 0, count: 80)
        var outputReal = imaginary
        var outputImaginary = imaginary
        var spectrumReal = [Float](repeating: 0, count: 201)
        var spectrumImaginary = spectrumReal
        let activeFrames = min(length, (samples.count + window.count / 2 - 1) / 160 + 1)
        for frame in 0..<activeFrames {
            for bin in 0..<201 { spectrumReal[bin] = 0; spectrumImaginary[bin] = 0 }
            for residue in 0..<5 {
                for index in 0..<80 {
                    let windowIndex = index * 5 + residue
                    let position = abs(frame * 160 + windowIndex - 200)
                    real[index] =
                        position < samples.count
                        ? samples[samples.startIndex + position] * window[windowIndex] : 0
                }
                transform.transform(
                    inputReal: real, inputImaginary: imaginary,
                    outputReal: &outputReal, outputImaginary: &outputImaginary)
                for bin in 0..<201 {
                    let rotation = rotations[residue * 201 + bin]
                    let index = bin % 80
                    spectrumReal[bin] +=
                        outputReal[index] * rotation.real - outputImaginary[index] * rotation.imaginary
                    spectrumImaginary[bin] +=
                        outputImaginary[index] * rotation.real + outputReal[index] * rotation.imaginary
                }
            }
            for bin in 0..<201 {
                powers[bin * length + frame] =
                    spectrumReal[bin] * spectrumReal[bin]
                    + spectrumImaginary[bin] * spectrumImaginary[bin]
            }
        }
        var values = [Float](repeating: 0, count: 128 * length)
        vDSP_mmul(filters, 1, powers, 1, &values, 1, 128, vDSP_Length(length), 201)
        var maximum: Float = -.infinity
        for index in values.indices {
            values[index] = log10(max(1e-10, values[index]))
            maximum = max(maximum, values[index])
        }
        for index in values.indices { values[index] = (max(maximum - 8, values[index]) + 4) / 4 }
        return (values, frames, length)
    }

    /// 按帧数推算编码器输出的音频 embedding 数量（每 100 帧产生 13 个，余数每 8 帧产生 1 个）。
    static func embeddingCount(frames: Int) -> Int { frames / 100 * 13 + (frames % 100 + 7) / 8 }
}
