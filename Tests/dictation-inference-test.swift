// 文件职责：Dictation 推理层的独立测试 harness，校验评分选择、BPE 分词、傅里叶变换、mel 特征、聆听频段与音频分块。
// 分层：测试 harness；依赖真实的 DictationTensor/Tokenizer/Mel/Spectrum/AudioChunks 实现，不加载模型权重。

import Foundation

/// 独立可执行测试入口：逐个校验推理辅助工具的边界条件与形状约束。
@main
struct DictationInferenceTest {
    static func main() throws {
        // 评分选择：应返回首个最大值下标，平局时保留靠前的位置。
        var tied = [Float16](repeating: -1, count: 64)
        tied[7] = 4
        tied[32] = 4
        var wide = [Float16](repeating: -1, count: 151936)
        wide[151934] = 4
        let fixtures: [[Float16]] = [[-5, -1, -1, -3], [4, 4, -2], [-2, 0, 3], [7], tied, wide]
        for values in fixtures {
            let scores = try DictationTensor.zeros([1, 1, values.count], type: .float16)
            scores.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
                _ = buffer.update(from: values)
            }
            let expected = values.indices.reduce(0) { values[$1] > values[$0] ? $1 : $0 }
            guard try DictationTensor.indexOfMaximum(in: scores) == expected else {
                fatalError("Score selection changed the first maximum")
            }
        }
        for scores in [try DictationTensor.zeros([1, 2]), try DictationTensor.zeros([2, 2], type: .float16)] {
            do {
                _ = try DictationTensor.indexOfMaximum(in: scores)
                fatalError("Score selection accepted an incompatible tensor")
            } catch DictationInferenceError.incompatibleModel {}
        }

        // 分词器：构造覆盖全部字节字面量的 GPT-2 风格词表与合并规则。
        var vocabulary = [String: Int]()
        var extra = 256
        for byte in 0...255 {
            let literal =
                (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            let scalar = Unicode.Scalar(literal ? byte : extra)!
            if !literal { extra += 1 }
            vocabulary[String(scalar)] = byte
        }
        vocabulary["ab"] = 256
        let prompts = ["ab", "GearMac", "é 新 🍋", "two\nlines", "1, 2, 300"]
        let tokenizer = try DictationTokenizer(
            vocabulary: JSONEncoder().encode(vocabulary),
            merges: "#version: 0.2\na b\n", prompts: prompts + ["ab"])
        guard try tokenizer.tokens(for: "ab") == [256] else { fatalError("BPE merge failed") }
        for text in prompts {
            guard try tokenizer.decode(tokenizer.tokens(for: text)) == text else {
                fatalError("Tokenizer round trip failed")
            }
        }
        do {
            _ = try tokenizer.tokens(for: "not prepared")
            fatalError("Tokenizer accepted an unprepared prompt")
        } catch CocoaError.coderInvalidValue {}

        // mel 特征：静音归一化、Fourier 频段落点与跳过静音补零的一致性。
        let mel = try DictationMel()
        let silence = try mel.features([Float](repeating: 0, count: 16_000)[...])
        guard silence.frames == 100, silence.values.allSatisfy({ $0 == -1.5 }),
            DictationMel.embeddingCount(frames: 3000) == 390,
            DictationMel.embeddingCount(frames: 1500) == 195
        else { fatalError("Mel shape or normalization failed") }
        for (frequency, expected) in [(440.0, 18), (2500.0, 80)] {
            let samples = (0..<16_000).map { Float(sin(2 * .pi * frequency * Double($0) / 16_000)) }
            let spectrum = try mel.features(samples[...])
            let peak = (0..<128).max { spectrum.values[$0 * 100 + 10] < spectrum.values[$1 * 100 + 10] }!
            guard abs(peak - expected) <= 1 else {
                fatalError("Fourier transform placed energy in the wrong band")
            }
        }
        let paddedAudio = (0..<11_111).map { Float(sin(Double($0) * 0.017)) }
        let padded = try mel.features(paddedAudio[...])
        let baseline = try referenceMel(paddedAudio, length: padded.length)
        guard zip(padded.values, baseline).allSatisfy({ abs($0 - $1) < 0.0001 }) else {
            fatalError("Skipping silent padding changed the mel spectrum")
        }

        // 聆听波形频段：静音保持不动，纯音落在预期频段且数值有界。
        let waveform = try DictationSpectrum()
        guard
            waveform.levels(for: [Float](repeating: 0, count: 512)[...]) == [Float](repeating: 0, count: 21),
            waveform.levels(for: [Float]()[...]).allSatisfy({ $0 == 0 })
        else {
            fatalError("Silent audio moved the waveform")
        }
        for (frequency, expected) in [(440.0, 11), (2500.0, 18)] {
            let tone = (0..<800).map { Float(0.2 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
            let levels = waveform.levels(for: tone[...])
            let peak = levels.indices.max { levels[$0] < levels[$1] }!
            guard levels.count == 21, abs(peak - expected) <= 1,
                levels.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                levels == waveform.levels(for: tone.suffix(512))
            else {
                fatalError("Listening bands moved, saturated or retained old samples")
            }
        }

        // 音频分块：在静音处切分，保证不丢失、不重复且每块不超过上限。
        var samples = [Float](repeating: 0.5, count: 480_001)
        for index in 210_000..<218_000 { samples[index] = 0 }
        let ranges = DictationAudioChunks.ranges(in: samples, maximum: 240_000)
        guard ranges.first?.lowerBound == 0, ranges.last?.upperBound == samples.count,
            ranges.first.map({ (210_000..<218_000).contains($0.upperBound) }) == true,
            ranges.allSatisfy({ !$0.isEmpty && $0.count <= 240_000 }),
            zip(ranges, ranges.dropFirst()).allSatisfy({ $0.upperBound == $1.lowerBound }),
            DictationAudioChunks.ranges(in: [], maximum: 240_000).isEmpty
        else {
            fatalError("Audio chunks lost, repeated or cut samples outside a pause")
        }
        print(
            "Dictation scores, tokenizer, Fourier transform, mel features, listening bands and audio chunks passed"
        )
    }

    /// 参考实现：对补零后的音频重新计算 mel 特征，用于对比跳过静音补零是否改变结果。
    private static func referenceMel(_ samples: [Float], length: Int) throws -> [Float] {
        let padded = samples + [Float](repeating: 0, count: length * 160 - samples.count)
        return try DictationMel().features(padded[...]).values
    }
}
