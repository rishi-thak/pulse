import Foundation

/// The musical scale used to tune pads in Keys mode.
enum PadScale: String, CaseIterable, Identifiable {
    case chromatic
    case major
    case minorPentatonic

    var id: Self { self }

    var title: String {
        switch self {
        case .chromatic: "Chromatic"
        case .major: "Major"
        case .minorPentatonic: "Minor Pentatonic"
        }
    }

    private var degrees: [Int] {
        switch self {
        case .chromatic: Array(0..<12)
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        }
    }

    private var lowestSemitone: Int {
        switch self {
        case .chromatic: -8
        case .major, .minorPentatonic: -12
        }
    }

    /// The semitone offset from the original sample pitch for a pad.
    func semitones(forPad index: Int) -> Int {
        let octave = index / degrees.count
        let degree = degrees[index % degrees.count]
        return lowestSemitone + octave * 12 + degree
    }
}
