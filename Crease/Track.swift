import Foundation

/// Bundled loops with known tempos, so two channels can be beatmatched and mixed.
enum Track: String, CaseIterable, Identifiable {
    case nightDrive
    case lowRider
    case acidLine
    case breaker
    case dreamwash
    case hearts

    var id: Self { self }

    var title: String {
        switch self {
        case .nightDrive: "Night Drive"
        case .lowRider: "Low Rider"
        case .acidLine: "Acid Line"
        case .breaker: "Breaker"
        case .dreamwash: "Dreamwash"
        case .hearts: "Hearts"
        }
    }

    var bpm: Double {
        switch self {
        case .nightDrive: 124
        case .lowRider: 92
        case .acidLine: 128
        case .breaker: 140
        case .dreamwash: 100
        case .hearts: 120
        }
    }

    var genre: String {
        switch self {
        case .nightDrive: "House"
        case .lowRider: "Hip-hop"
        case .acidLine: "Acid"
        case .breaker: "Breaks"
        case .dreamwash: "Ambient"
        case .hearts: "Melodic"
        }
    }

    func makeSample() -> Sample {
        var builder = TrackSynth.Builder(bpm: bpm, bars: 8, swing: self == .lowRider ? 0.28 : 0)
        switch self {
        case .nightDrive: Self.nightDrive(&builder)
        case .lowRider: Self.lowRider(&builder)
        case .acidLine: Self.acidLine(&builder)
        case .breaker: Self.breaker(&builder)
        case .dreamwash: Self.dreamwash(&builder)
        case .hearts: Self.hearts(&builder)
        }
        return Sample(name: title, frames: SampleProcessing.normalize(builder.out), bpm: bpm, kind: .track)
    }

    // MARK: Arrangements

    /// Four-on-the-floor house in A minor with off-beat stabs.
    private static func nightDrive(_ b: inout TrackSynth.Builder) {
        b.drum("x...x...x...x...", gain: 1.0) { TrackSynth.kick() }
        b.drum("....x.......x...", gain: 0.55) { TrackSynth.clap() }
        b.drum("..x...x...x...x.", gain: 0.9) { TrackSynth.hat(open: true) }
        b.drum("x.x.x.x.x.x.x.x.", gain: 0.5) { TrackSynth.hat(open: false) }
        // Am, F, C, G: two bars each.
        let roots = [33, 29, 36, 31]
        for (bar, root) in roots.enumerated() {
            for repeatBar in 0..<2 {
                let start = (bar * 2 + repeatBar) * 16
                for (step, length) in [(0, 1.5), (3, 1.0), (6, 1.5), (10, 1.0), (14, 1.0)] {
                    b.place(TrackSynth.sub(TrackSynth.hz(root), seconds: b.seconds(length)), at: start + step, gain: 0.55)
                }
                b.place(TrackSynth.sub(TrackSynth.hz(root + 12), seconds: b.seconds(0.75)), at: start + 12, gain: 0.4)
            }
        }
        let chords = [[57, 60, 64, 67], [53, 57, 60, 65], [55, 60, 64, 67], [55, 59, 62, 67]]
        for (index, chord) in chords.enumerated() {
            let stab = TrackSynth.saws(chord.map(TrackSynth.hz), seconds: b.seconds(1.5), cutoff: 2600, resonance: 0.3, attack: 0.004, release: 0.05, decay: 0.12)
            for repeatBar in 0..<2 {
                let start = (index * 2 + repeatBar) * 16
                for step in [2, 6, 10, 13] {
                    b.place(stab, at: start + step, gain: 0.5)
                }
            }
        }
    }

    /// Swung boom-bap in E minor with electric piano.
    private static func lowRider(_ b: inout TrackSynth.Builder) {
        b.drum("x..x..x...x.x...", gain: 1.0) { TrackSynth.kick(decay: 7, punch: 90) }
        b.drum("....x.......x...", gain: 0.8) { TrackSynth.snare() }
        b.drum("x.x.x.x.x.x.x.x.", gain: 0.45) { TrackSynth.hat(open: false) }
        b.drum("..............x.", gain: 0.5) { TrackSynth.hat(open: true) }
        b.notes([(0, 28, 3), (6, 31, 2), (10, 28, 2), (13, 26, 3)], every: 16, gain: 0.6) { hz, seconds in
            TrackSynth.sub(hz, seconds: seconds)
        }
        // Em7, Cmaj7, Am7, B7: two bars each.
        b.chords([[52, 55, 59, 62], [48, 52, 55, 59], [45, 48, 52, 55], [47, 51, 54, 57]], length: 32, gain: 0.5) { hz, seconds in
            TrackSynth.keys(hz, seconds: min(seconds, 2.2))
        }
    }

    /// A squelching 303 line over a minimal kick.
    private static func acidLine(_ b: inout TrackSynth.Builder) {
        b.drum("x...x...x...x...", gain: 1.0) { TrackSynth.kick(decay: 11, punch: 130) }
        b.drum("..x...x...x...x.", gain: 0.6) { TrackSynth.hat(open: false) }
        b.drum("......x.......x.", gain: 0.5) { TrackSynth.hat(open: true, seed: 8) }
        b.drum("....x.......x...", gain: 0.35) { TrackSynth.clap(seed: 4) }
        // (step, semitones above E1, accent) — the classic up-and-down.
        let line: [(Int, Int, Bool)] = [
            (0, 0, true), (2, 0, false), (3, 12, false), (5, 0, false), (6, 7, true), (8, 0, false),
            (9, 12, false), (11, 3, true), (12, 0, false), (14, 10, false), (15, 12, true),
        ]
        var cache: [String: [Float]] = [:]
        for bar in 0..<b.bars {
            // Modulate up a fourth for the last two bars.
            let base = bar >= 6 ? 33 : 28
            for (step, offset, accent) in line {
                let midi = base + offset
                let key = "\(midi)-\(accent)"
                let sound = cache[key] ?? TrackSynth.acid(TrackSynth.hz(midi), seconds: b.seconds(accent ? 1.6 : 0.9), accent: accent)
                cache[key] = sound
                b.place(sound, at: bar * 16 + step, gain: accent ? 0.75 : 0.55)
            }
        }
    }

    /// Fast breakbeat with a growling bass underneath.
    private static func breaker(_ b: inout TrackSynth.Builder) {
        b.drum("x.x.......x.....x.x.......x..x..", gain: 1.0) { TrackSynth.kick(decay: 12, punch: 120) }
        b.drum("....x..x....x.......x..x....x...", gain: 0.85) { TrackSynth.snare(seed: 13) }
        b.drum("x.x.x.x.x.x.x.x.", gain: 0.4) { TrackSynth.hat(open: false, seed: 6) }
        b.drum("..............x...............x.", gain: 0.45) { TrackSynth.hat(open: true, seed: 3) }
        b.drum("x.x.x.x.x.x.x.x.", gain: 0.2) { TrackSynth.shaker() }
        b.notes([(0, 29, 12), (12, 27, 4)], every: 16, gain: 0.5) { hz, seconds in
            TrackSynth.reese(hz, seconds: seconds)
        }
    }

    /// Slow, drumless pads for layering over anything.
    private static func dreamwash(_ b: inout TrackSynth.Builder) {
        b.chords([[48, 52, 55, 59], [45, 48, 52, 55], [41, 45, 48, 52], [43, 47, 50, 55]], length: 32, gain: 0.5) { hz, seconds in
            TrackSynth.saws(hz, seconds: seconds, detune: 0.009, cutoff: 900, resonance: 0.15, attack: 0.9, release: 1.2)
        }
        b.chords([[72, 76, 79], [69, 72, 76], [65, 69, 72], [67, 71, 74]], length: 32, gain: 0.18) { hz, seconds in
            TrackSynth.saws(hz, seconds: seconds, detune: 0.004, cutoff: 1800, resonance: 0.1, attack: 1.6, release: 1.4)
        }
        b.drum("x...............", gain: 0.35) { TrackSynth.kick(decay: 5, punch: 60) }
        // Sparse high plucks drifting across the top.
        b.notes([(4, 84, 4), (11, 88, 4), (22, 91, 4), (29, 86, 4)], every: 32, gain: 0.25) { hz, seconds in
            TrackSynth.pluck(hz, seconds: seconds, brightness: 0.4995)
        }
    }

    /// A rolling plucked arpeggio over a gentle kick and shaker.
    private static func hearts(_ b: inout TrackSynth.Builder) {
        b.drum("x...x...x...x...", gain: 0.75) { TrackSynth.kick(decay: 8, punch: 80) }
        b.drum("..x...x...x...x.", gain: 0.5) { TrackSynth.shaker(seed: 2) }
        b.drum("....x.......x...", gain: 0.3) { TrackSynth.clap(seed: 12) }
        // C, G, Am, F: each chord arpeggiated up and down for two bars.
        let chords = [[60, 64, 67, 72], [55, 59, 62, 67], [57, 60, 64, 69], [53, 57, 60, 65]]
        let order = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3]
        for (index, chord) in chords.enumerated() {
            var cache: [Int: [Float]] = [:]
            for repeatBar in 0..<2 {
                let start = (index * 2 + repeatBar) * 16
                for step in 0..<16 {
                    let midi = chord[order[step]] + (repeatBar == 1 && step >= 8 ? 12 : 0)
                    let sound = cache[midi] ?? TrackSynth.pluck(TrackSynth.hz(midi), seconds: b.seconds(3))
                    cache[midi] = sound
                    b.place(sound, at: start + step, gain: 0.5)
                }
            }
        }
        for (index, root) in [36, 31, 33, 29].enumerated() {
            for repeatBar in 0..<2 {
                let start = (index * 2 + repeatBar) * 16
                b.place(TrackSynth.sub(TrackSynth.hz(root), seconds: b.seconds(7)), at: start, gain: 0.45)
                b.place(TrackSynth.sub(TrackSynth.hz(root), seconds: b.seconds(7)), at: start + 8, gain: 0.45)
            }
        }
    }
}
