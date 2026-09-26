import Foundation

/// The live sound-shaping values derived from how far the device is folded.
struct SoundShape: Equatable {
    /// Pitch bend applied to every voice, in cents.
    var pitchCents: Float = 0
    /// Playback rate applied without changing pitch.
    var rate: Float = 1
    /// Amount of grit and space, from 0 to 1.
    var texture: Float = 0
    /// Low-pass cutoff in hertz.
    var cutoff: Float = 20_000

    static let maxBendSemitones: Float = 12
    static let minRate: Float = 0.25
    static let minCutoff: Float = 350
    static let maxCutoff: Float = 20_000

    init() {}

    init(fold: Double, targets: Set<FoldTarget>) {
        let amount = Float(min(max(fold, 0), 1))
        if targets.contains(.pitch) {
            pitchCents = amount * Self.maxBendSemitones * 100
        }
        if targets.contains(.stretch) {
            rate = 1 - amount * (1 - Self.minRate)
        }
        if targets.contains(.texture) {
            texture = amount
        }
        if targets.contains(.filter) {
            // Exponential sweep sounds even to the ear.
            cutoff = Self.maxCutoff * pow(Self.minCutoff / Self.maxCutoff, amount)
        }
    }

    var pitchDescription: String {
        let semitones = pitchCents / 100
        return semitones < 0.05 ? "0 st" : "+\(semitones.formatted(.number.precision(.fractionLength(1)))) st"
    }

    var rateDescription: String {
        "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }

    var textureDescription: String {
        texture.formatted(.percent.precision(.fractionLength(0)))
    }

    var cutoffDescription: String {
        cutoff >= 1000
            ? "\((cutoff / 1000).formatted(.number.precision(.fractionLength(1)))) kHz"
            : "\(Int(cutoff)) Hz"
    }
}
