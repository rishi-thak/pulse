import Foundation

/// The live sound-shaping values derived from how far each fold target is bent.
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

    /// Each amount runs from 0, untouched, to 1, fully bent.
    init(pitch: Double, stretch: Double, texture: Double, filter: Double) {
        let clamp = { (amount: Double) in Float(min(max(amount, 0), 1)) }
        pitchCents = clamp(pitch) * Self.maxBendSemitones * 100
        rate = 1 - clamp(stretch) * (1 - Self.minRate)
        self.texture = clamp(texture)
        // Exponential sweep sounds even to the ear.
        cutoff = Self.maxCutoff * pow(Self.minCutoff / Self.maxCutoff, clamp(filter))
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
