import SwiftUI

/// One playable pad and the part of the sample it triggers.
struct Pad: Identifiable {
    static let count = 16

    var index: Int
    var title: String
    var accessibilityName: String
    /// Waveform shape for the pad's thumbnail.
    var peaks: [Float]
    /// Pitch offset in semitones, used in Keys mode.
    var semitones: Int
    /// The part of the full sample this pad plays, as fractions of its length.
    var region: ClosedRange<Double>

    var id: Int { index }

    var color: Color {
        Self.color(for: index)
    }

    static func hue(for index: Int) -> Double {
        0.02 + Double(index) / Double(count - 1) * 0.52
    }

    static func color(for index: Int) -> Color {
        Color(hue: hue(for: index), saturation: 0.72, brightness: 1)
    }
}
