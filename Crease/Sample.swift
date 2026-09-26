import Foundation

/// A mono sound held in memory at the engine's sample rate.
struct Sample: Identifiable {
    enum Kind {
        case track
        case sound
        case recording
        case imported
    }

    static let sampleRate: Double = 48_000
    static let peakCount = 256

    let id = UUID()
    var name: String
    var frames: [Float]
    /// Normalized peak amplitudes across the whole sample, for drawing.
    var peaks: [Float]
    /// Tempo, when known, so decks can be beatmatched.
    var bpm: Double?
    var kind: Kind

    init(name: String, frames: [Float], bpm: Double? = nil, kind: Kind = .sound) {
        self.name = name
        self.frames = frames
        self.bpm = bpm
        self.kind = kind
        self.peaks = Self.peaks(of: frames[...], count: Self.peakCount)
    }

    var duration: Double {
        Double(frames.count) / Self.sampleRate
    }

    static func peaks(of frames: ArraySlice<Float>, count: Int) -> [Float] {
        guard !frames.isEmpty, count > 0 else { return Array(repeating: 0, count: max(count, 0)) }
        let binSize = max(1, frames.count / count)
        var result: [Float] = []
        result.reserveCapacity(count)
        var index = frames.startIndex
        for _ in 0..<count {
            let end = min(index + binSize, frames.endIndex)
            var peak: Float = 0
            if index < end {
                for i in index..<end { peak = max(peak, abs(frames[i])) }
            }
            result.append(peak)
            index = end
        }
        let loudest = result.max() ?? 0
        return loudest > 0 ? result.map { $0 / loudest } : result
    }
}
