import Foundation

/// Where a playing voice currently is within the full sample.
struct Playhead: Identifiable {
    enum Source: Hashable {
        case pad(Int)
        case loop
        case grain
        case deck(Deck.Slot)
    }

    var id: Int
    var source: Source
    /// Position as a fraction of the full sample's length.
    var position: Double

    var padIndex: Int? {
        if case .pad(let index) = source { return index }
        return nil
    }

    /// Hue for the shader: pads and decks use their colour; negative values pick white or ice.
    var shaderHue: Float {
        switch source {
        case .pad(let index): Float(Pad.hue(for: index))
        case .loop: -1
        case .grain: -2
        case .deck(let slot): Float(slot.hue)
        }
    }
}
