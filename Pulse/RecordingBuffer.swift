import AVFoundation
import Synchronization

/// Collects microphone audio on the render thread so the main actor can read it safely.
final class RecordingBuffer: Sendable {
    private struct State {
        var frames: [Float] = []
        var peaks: [Float] = []
        var sampleRate: Double = Sample.sampleRate
    }

    /// Longest recording kept, in seconds.
    static let maxDuration: Double = 8

    private let state = Mutex(State())

    func reset(sampleRate: Double) {
        state.withLock { $0 = State(sampleRate: sampleRate) }
    }

    /// Peak levels of the audio captured so far, one per render buffer.
    var livePeaks: [Float] {
        state.withLock { $0.peaks }
    }

    var elapsed: Double {
        state.withLock { Double($0.frames.count) / $0.sampleRate }
    }

    func take() -> (frames: [Float], sampleRate: Double) {
        state.withLock { state in
            defer { state.frames = [] }
            return (state.frames, state.sampleRate)
        }
    }

    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in
            append(buffer)
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        state.withLock { state in
            guard Double(state.frames.count) < Self.maxDuration * state.sampleRate else { return }
            state.frames.append(contentsOf: samples)
            state.peaks.append(peak)
        }
    }
}
