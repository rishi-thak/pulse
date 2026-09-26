import Foundation

/// How the sample is spread across the pads.
enum PadMode: String, CaseIterable, Identifiable {
    /// Each pad plays its own slice of the sample.
    case slices
    /// Every pad plays the whole sample at a different pitch.
    case keys

    var id: Self { self }

    var title: String {
        switch self {
        case .slices: "Slices"
        case .keys: "Keys"
        }
    }

    var systemImage: String {
        switch self {
        case .slices: "square.split.2x2"
        case .keys: "pianokeys"
        }
    }
}
