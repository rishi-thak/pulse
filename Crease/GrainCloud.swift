import AVFoundation
import Synchronization

/// A granular voice that plays a cloud of tiny overlapping grains from one
/// spot in the sample, so a sound can be frozen and scrubbed through.
///
/// Parameters are atomics written from the main actor and read on the audio
/// thread. The sample itself sits behind a mutex the render block only
/// tries to take, so swapping samples never stalls audio.
final class GrainCloud: Sendable {
    /// Where the cloud sits, as a fraction of the full sample.
    let position = Atomic<Float>(0)
    /// How far grains wander from the position, as a fraction of the sample.
    let spread = Atomic<Float>(0.02)
    let grainSeconds = Atomic<Float>(0.09)
    /// Playback ratio applied to every grain; 2 is an octave up.
    let rate = Atomic<Float>(1)
    /// Target loudness; the render thread glides toward it to avoid clicks.
    let gain = Atomic<Float>(0)

    private let frames = Mutex<[Float]>([])
    private let renderState = RenderState()

    static let grainCount = 8

    func setSample(_ newFrames: [Float]) {
        frames.withLock { $0 = newFrames }
    }

    func makeNode(sampleRate: Double) -> AVAudioSourceNode {
        AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!) { [self] _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let output = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let count = Int(frameCount)
            let rendered: Bool = frames.withLockIfAvailable { frames in
                frames.withUnsafeBufferPointer { source in
                    render(into: output, count: count, source: source, sampleRate: Float(sampleRate))
                }
                return true
            } ?? false
            if !rendered {
                output.update(repeating: 0, count: count)
            }
            return noErr
        }
    }

    private func render(into output: UnsafeMutablePointer<Float>, count: Int, source: UnsafeBufferPointer<Float>, sampleRate: Float) {
        let state = renderState
        let target = gain.load(ordering: .relaxed)
        // Silent and asked to stay silent: skip the work entirely.
        if target <= 0, state.currentGain < 0.0005 {
            output.update(repeating: 0, count: count)
            state.currentGain = 0
            return
        }
        guard source.count > 2 else {
            output.update(repeating: 0, count: count)
            return
        }

        let total = source.count
        let center = position.load(ordering: .relaxed)
        let spread = spread.load(ordering: .relaxed)
        let length = max(Int(grainSeconds.load(ordering: .relaxed) * sampleRate), 256)
        let rate = rate.load(ordering: .relaxed)
        let normalize = 1 / Float(Self.grainCount).squareRoot()

        for frame in 0..<count {
            var sum: Float = 0
            for g in 0..<Self.grainCount {
                var grain = state.grains[g]
                if grain.phase >= Float(grain.length) {
                    let wander = (state.random() - 0.5) * spread
                    let startFraction = min(max(center + wander, 0), 1)
                    grain.start = min(Int(startFraction * Float(total)), total - 2)
                    grain.length = length
                    grain.phase = 0
                }
                let read = Float(grain.start) + grain.phase * rate
                let index = Int(read)
                if index >= 0, index + 1 < total {
                    let fraction = read - Float(index)
                    let value = source[index] + (source[index + 1] - source[index]) * fraction
                    let window = 0.5 - 0.5 * cos(2 * Float.pi * grain.phase / Float(grain.length))
                    sum += value * window
                } else {
                    grain.phase = Float(grain.length)
                }
                grain.phase += 1
                state.grains[g] = grain
            }
            state.currentGain += (target - state.currentGain) * 0.0015
            output[frame] = sum * normalize * state.currentGain
        }
    }
}

/// Mutable state touched only by the audio thread.
private final class RenderState: @unchecked Sendable {
    struct Grain {
        var start = 0
        var length = 1
        var phase: Float = 1
    }

    var grains: [Grain]
    var currentGain: Float = 0
    private var seed: UInt32 = 0x1234_5678

    init() {
        // Stagger the grains so they don't all start together.
        grains = (0..<GrainCloud.grainCount).map { index in
            Grain(start: 0, length: 4096, phase: Float(index) * 4096 / Float(GrainCloud.grainCount))
        }
    }

    func random() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }
}
