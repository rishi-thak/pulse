import AVFoundation
import Synchronization

/// Measures the loudness of the engine's output for the visualizer.
final class LevelMeter: Sendable {
    private let level = Mutex<Float>(0)

    /// Recent output loudness from 0 to roughly 1.
    var current: Float {
        level.withLock { $0 }
    }

    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in
            measure(buffer)
        }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = (sum / Float(count)).squareRoot()
        level.withLock { value in
            // Rise fast, fall slowly, so hits read clearly.
            let target = min(rms * 3, 1)
            value = target > value ? target : value * 0.8 + target * 0.2
        }
    }
}
