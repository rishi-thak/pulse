import Foundation

/// Cleans up raw recordings so they're ready to play from pads.
enum SampleProcessing {
    /// Resamples to the engine rate, trims leading and trailing silence, and normalizes.
    static func prepare(_ input: [Float], sourceRate: Double) -> [Float] {
        let resampled = resample(input, from: sourceRate, to: Sample.sampleRate)
        return normalize(trimSilence(resampled))
    }

    static func resample(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate > 0, sourceRate != targetRate, input.count > 1 else { return input }
        let ratio = sourceRate / targetRate
        let outputCount = Int(Double(input.count) / ratio)
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let position = Double(i) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            output[i] = input[lower] + (input[upper] - input[lower]) * fraction
        }
        return output
    }

    static func trimSilence(_ input: [Float], threshold: Float = 0.02) -> [Float] {
        let loudest = input.lazy.map(abs).max() ?? 0
        guard loudest > 0 else { return [] }
        let gate = loudest * threshold
        guard let first = input.firstIndex(where: { abs($0) > gate }),
              let last = input.lastIndex(where: { abs($0) > gate }) else { return [] }
        // Keep a little air around the sound so attacks aren't clipped.
        let pad = Int(Sample.sampleRate * 0.01)
        return Array(input[max(0, first - pad)...min(input.count - 1, last + pad)])
    }

    static func normalize(_ input: [Float], ceiling: Float = 0.9) -> [Float] {
        let loudest = input.lazy.map(abs).max() ?? 0
        guard loudest > 0 else { return input }
        let gain = ceiling / loudest
        return input.map { $0 * gain }
    }

    /// Applies a short fade at both ends to avoid clicks.
    static func fadeEdges(_ input: inout [Float], length: Int = 96) {
        let n = min(length, input.count / 2)
        guard n > 0 else { return }
        for i in 0..<n {
            let gain = Float(i) / Float(n)
            input[i] *= gain
            input[input.count - 1 - i] *= gain
        }
    }
}
