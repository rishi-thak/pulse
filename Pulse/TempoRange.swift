import Foundation

/// How far a deck's tempo fader can push, like the range switch on a CDJ.
enum TempoRange: Double, CaseIterable, Identifiable {
    case narrow = 0.08
    case standard = 0.16
    case wide = 0.5
    case full = 1

    var id: Self { self }

    /// The fader's limit either way, as a fraction of the track's speed.
    var limit: Double { rawValue }

    var title: String {
        "±\(Int((rawValue * 100).rounded()))%"
    }

    /// The narrowest range that reaches this tempo offset, if any does.
    static func fitting(_ tempo: Double) -> TempoRange? {
        allCases.first { abs(tempo) <= $0.limit + 0.0001 }
    }
}
