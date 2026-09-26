import AVFoundation

/// A single polyphonic voice: a player feeding its own pitch and time shifter.
@MainActor
final class Voice {
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()

    var padIndex: Int?
    /// Pitch from the pad itself, before the fold bend is added, in cents.
    var baseCents: Float = 0
    var frameCount: AVAudioFrameCount = 0
    var region: ClosedRange<Double> = 0...1
    var isReversed = false

    func apply(_ shape: SoundShape) {
        timePitch.pitch = min(max(baseCents + shape.pitchCents, -2400), 2400)
        timePitch.rate = shape.rate
    }

    func stop() {
        player.stop()
        padIndex = nil
    }

    /// How far through its region the voice is, or nil when it has finished.
    var progress: Double? {
        guard padIndex != nil, frameCount > 0, player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        guard playerTime.sampleTime >= 0 else { return nil }
        let fraction = Double(playerTime.sampleTime) / Double(frameCount)
        return (0...1).contains(fraction) ? fraction : nil
    }
}
