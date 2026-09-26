import Foundation

/// A part of the sound that folding the device can bend.
enum FoldTarget: String, CaseIterable, Identifiable, Codable {
    case pitch
    case stretch
    case texture
    case filter
    case scrub

    var id: Self { self }

    var title: String {
        switch self {
        case .pitch: "Pitch"
        case .stretch: "Stretch"
        case .texture: "Shatter"
        case .filter: "Filter"
        case .scrub: "Scrub"
        }
    }

    var systemImage: String {
        switch self {
        case .pitch: "tuningfork"
        case .stretch: "arrow.left.and.right"
        case .texture: "sparkles"
        case .filter: "line.3.horizontal.decrease"
        case .scrub: "hand.draw"
        }
    }

    var summary: String {
        switch self {
        case .pitch: "Bends up an octave"
        case .stretch: "Slows to quarter speed"
        case .texture: "Breaks into grit and space"
        case .filter: "Muffles the highs"
        case .scrub: "Freezes and moves through the sound"
        }
    }
}
