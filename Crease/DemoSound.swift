import Foundation

/// Short built-in sounds for the pads, so there's something to play before recording.
enum DemoSound: String, CaseIterable, Identifiable {
    case beat
    case voice
    case pluck

    var id: Self { self }

    var title: String {
        switch self {
        case .beat: "Beat"
        case .voice: "Voice"
        case .pluck: "Pluck"
        }
    }

    var systemImage: String {
        switch self {
        case .beat: "metronome"
        case .voice: "person.wave.2"
        case .pluck: "guitars"
        }
    }

    /// The pad layout that suits this sound best.
    var preferredMode: PadMode {
        self == .beat ? .slices : .keys
    }

    func makeSample() -> Sample {
        switch self {
        case .beat:
            var builder = TrackSynth.Builder(bpm: 110, bars: 2)
            builder.drum("x......x..x.....x......x..x.....") { TrackSynth.kick() }
            builder.drum("....x.......x.......x.......x..x", gain: 0.8) { TrackSynth.clap() }
            builder.drum(".x.x.x.x.x.x.x.x", gain: 0.8) { TrackSynth.hat(open: false) }
            builder.drum("......x.........", gain: 0.8) { TrackSynth.hat(open: true) }
            return Sample(name: title, frames: SampleProcessing.normalize(builder.out), bpm: 110)
        case .voice:
            return Sample(name: title, frames: SampleProcessing.normalize(Self.voice()))
        case .pluck:
            return Sample(name: title, frames: SampleProcessing.normalize(TrackSynth.pluck(220, seconds: 1.8)))
        }
    }

    /// A sung "ah" built from harmonics shaped by vowel formants.
    private static func voice() -> [Float] {
        let rate = Sample.sampleRate
        let length = Int(rate * 1.6)
        let base = 196.0 // G3
        let formants: [(frequency: Double, width: Double, gain: Double)] = [
            (800, 90, 1.0), (1150, 110, 0.5), (2900, 160, 0.25),
        ]
        var phase = 0.0
        var out = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let t = Double(i) / rate
            let vibrato = 1 + 0.006 * sin(2 * .pi * 5.2 * t) * min(t / 0.4, 1)
            phase += 2 * .pi * base * vibrato / rate
            var value = 0.0
            for harmonic in 1...24 {
                let frequency = base * Double(harmonic)
                var gain = 0.0
                for formant in formants {
                    let distance = (frequency - formant.frequency) / formant.width
                    gain += formant.gain * exp(-distance * distance)
                }
                value += sin(phase * Double(harmonic)) * (gain + 0.02) / Double(harmonic).squareRoot()
            }
            let envelope = min(t / 0.08, 1) * min((1.6 - t) / 0.3, 1)
            out[i] = Float(value * envelope)
        }
        return out
    }
}
