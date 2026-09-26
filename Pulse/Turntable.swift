import AVFoundation
import Synchronization

/// A vinyl-style player: continuous playback at any speed, forwards or
/// backwards, that follows a finger when scratched and glides back to its
/// motor speed when let go. Rendered on the audio thread.
final class Turntable: Sendable {
    /// Motor speed as a playback multiplier; 0 is stopped, negative is reverse.
    let motorRate = Atomic<Float>(0)
    /// Speed demanded by a finger on the platter, valid while scratching.
    let scratchRate = Atomic<Float>(0)
    let isScratching = Atomic<Bool>(false)
    /// When the last scratch update arrived, so a resting finger reads as stopped.
    let scratchTimestamp = Atomic<UInt64>(0)
    let gain = Atomic<Float>(1)
    /// The region that loops, as fractions of the sample.
    let loopStart = Atomic<Float>(0)
    let loopEnd = Atomic<Float>(1)
    /// Set to a fraction to jump there on the next render; negative means none.
    let cueRequest = Atomic<Float>(-1)
    /// Where the needle is, as a fraction of the sample. Written by the audio thread.
    let position = Atomic<Float>(0)
    /// Recent output loudness from 0 to about 1, for the channel meter.
    let level = Atomic<Float>(0)

    private let frames = Mutex<[Float]>([])
    private let renderState = RenderState()

    /// How long a finger can rest before the platter is treated as held still.
    private static let scratchHold: UInt64 = 90_000_000

    func setSample(_ newFrames: [Float]) {
        frames.withLock { $0 = newFrames }
        cueRequest.store(loopStart.load(ordering: .relaxed), ordering: .relaxed)
    }

    func makeNode(sampleRate: Double) -> AVAudioSourceNode {
        AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!) { [self] _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let output = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let count = Int(frameCount)
            let rendered: Bool = frames.withLockIfAvailable { frames in
                frames.withUnsafeBufferPointer { source in
                    render(into: output, count: count, source: source)
                }
                return true
            } ?? false
            if !rendered {
                output.update(repeating: 0, count: count)
            }
            return noErr
        }
    }

    private func render(into output: UnsafeMutablePointer<Float>, count: Int, source: UnsafeBufferPointer<Float>) {
        let state = renderState
        let total = source.count
        guard total > 2 else {
            output.update(repeating: 0, count: count)
            return
        }

        let start = Double(loopStart.load(ordering: .relaxed)) * Double(total)
        let end = max(start + 2, Double(loopEnd.load(ordering: .relaxed)) * Double(total))
        let requested = cueRequest.load(ordering: .relaxed)
        if requested >= 0 {
            state.readHead = Double(requested) * Double(total)
            cueRequest.store(-1, ordering: .relaxed)
        }

        let scratching = isScratching.load(ordering: .relaxed)
        var wanted = motorRate.load(ordering: .relaxed)
        if scratching {
            let age = DispatchTime.now().uptimeNanoseconds &- scratchTimestamp.load(ordering: .relaxed)
            wanted = age > Self.scratchHold ? 0 : scratchRate.load(ordering: .relaxed)
        }
        // A finger moves the platter instantly; the motor spins up and down.
        let glide: Float = scratching ? 0.02 : 0.0012
        let targetGain = gain.load(ordering: .relaxed)

        if !scratching, abs(state.currentRate) < 0.0005, abs(wanted) < 0.0005 {
            output.update(repeating: 0, count: count)
            state.currentGain = targetGain
            position.store(Float(state.readHead / Double(total)), ordering: .relaxed)
            level.store(level.load(ordering: .relaxed) * 0.8, ordering: .relaxed)
            return
        }

        var energy: Float = 0
        for frame in 0..<count {
            state.currentRate += (wanted - state.currentRate) * glide
            state.currentGain += (targetGain - state.currentGain) * 0.002
            var head = state.readHead + Double(state.currentRate)
            if head >= end { head -= (end - start) }
            if head < start { head += (end - start) }
            state.readHead = head

            let index = Int(head)
            let next = index + 1 < total ? index + 1 : index
            let fraction = Float(head - Double(index))
            let value = source[index] + (source[next] - source[index]) * fraction
            let sample = value * state.currentGain
            output[frame] = sample
            energy += sample * sample
        }
        position.store(Float(state.readHead / Double(total)), ordering: .relaxed)
        // Rise fast, fall slowly, so hits read clearly on the meter.
        let rms = min((energy / Float(count)).squareRoot() * 3, 1)
        let previous = level.load(ordering: .relaxed)
        level.store(rms > previous ? rms : previous * 0.8 + rms * 0.2, ordering: .relaxed)
    }
}

/// Mutable state touched only by the audio thread.
private final class RenderState: @unchecked Sendable {
    var readHead: Double = 0
    var currentRate: Float = 0
    var currentGain: Float = 1
}
