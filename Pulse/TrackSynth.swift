import Foundation

/// A small synth and drum kit for building the bundled tracks and demo sounds.
enum TrackSynth {
    static let rate = Sample.sampleRate

    // MARK: Sequencing

    /// Lays sounds onto a timeline of sixteenth-note steps.
    struct Builder {
        var bpm: Double
        var bars: Int
        /// Delay applied to every off-beat sixteenth, as a fraction of a step.
        var swing: Double = 0
        var out: [Float]

        init(bpm: Double, bars: Int, swing: Double = 0) {
            self.bpm = bpm
            self.bars = bars
            self.swing = swing
            out = [Float](repeating: 0, count: Int(Double(bars * 16) * 60 / bpm / 4 * TrackSynth.rate))
        }

        var stepSeconds: Double { 60 / bpm / 4 }
        var totalSteps: Int { bars * 16 }

        func seconds(_ steps: Double) -> Double { steps * stepSeconds }

        mutating func place(_ sound: [Float], at step: Int, gain: Float = 1) {
            let shifted = Double(step) + (step % 2 == 1 ? swing : 0)
            TrackSynth.mix(sound, into: &out, at: Int(shifted * stepSeconds * TrackSynth.rate), gain: gain)
        }

        /// Repeats a pattern across the whole track. `x` hits, `X` hits harder, anything else rests.
        mutating func drum(_ pattern: String, gain: Float = 1, _ make: () -> [Float]) {
            let symbols = Array(pattern)
            let sound = make()
            for step in 0..<totalSteps {
                switch symbols[step % symbols.count] {
                case "x": place(sound, at: step, gain: gain)
                case "X": place(sound, at: step, gain: gain * 1.35)
                default: break
                }
            }
        }

        /// Plays notes given as (step, midi note, length in steps), repeating every `every` steps.
        mutating func notes(
            _ notes: [(step: Int, midi: Int, length: Double)],
            every period: Int,
            gain: Float = 1,
            voice: (Double, Double) -> [Float]
        ) {
            var cache: [String: [Float]] = [:]
            for start in stride(from: 0, to: totalSteps, by: period) {
                for note in notes where start + note.step < totalSteps {
                    let key = "\(note.midi)-\(note.length)"
                    let sound = cache[key] ?? voice(TrackSynth.hz(note.midi), seconds(note.length))
                    cache[key] = sound
                    place(sound, at: start + note.step, gain: gain)
                }
            }
        }

        /// Plays a chord progression: each entry holds for `length` steps.
        mutating func chords(_ chords: [[Int]], length: Int, gain: Float = 1, voice: ([Double], Double) -> [Float]) {
            var step = 0
            var index = 0
            while step < totalSteps {
                let sound = voice(chords[index % chords.count].map(TrackSynth.hz), seconds(Double(length)))
                place(sound, at: step, gain: gain)
                step += length
                index += 1
            }
        }
    }

    static func hz(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    static func mix(_ source: [Float], into destination: inout [Float], at start: Int, gain: Float = 1) {
        guard start < destination.count else { return }
        let count = min(source.count, destination.count - start)
        for i in 0..<count {
            destination[start + i] += source[i] * gain
        }
    }

    // MARK: Envelopes and filters

    static func envelope(_ sound: inout [Float], attack: Double, release: Double) {
        let attackFrames = max(1, Int(attack * rate))
        let releaseFrames = max(1, min(Int(release * rate), sound.count))
        for i in 0..<min(attackFrames, sound.count) {
            sound[i] *= Float(i) / Float(attackFrames)
        }
        for i in 0..<releaseFrames {
            sound[sound.count - 1 - i] *= Float(i) / Float(releaseFrames)
        }
    }

    /// A resonant two-pole low-pass. `cutoff` may vary per sample for sweeps.
    static func lowpass(_ input: [Float], cutoff: (Int) -> Double, resonance: Double) -> [Float] {
        var low: Float = 0
        var band: Float = 0
        let q = Float(1 - resonance * 0.95)
        return input.indices.map { i in
            let f = Float(2 * sin(.pi * min(cutoff(i), rate * 0.45) / rate))
            let high = input[i] - low - q * band
            band += f * high
            low += f * band
            return low
        }
    }

    // MARK: Voices

    static func sine(_ frequency: Double, seconds: Double, attack: Double = 0.005, release: Double = 0.05) -> [Float] {
        let count = Int(seconds * rate)
        var phase = 0.0
        var out = (0..<count).map { _ -> Float in
            phase += 2 * .pi * frequency / rate
            return Float(sin(phase))
        }
        envelope(&out, attack: attack, release: release)
        return out
    }

    /// A deep sine bass with a little punch at the start.
    static func sub(_ frequency: Double, seconds: Double) -> [Float] {
        let count = Int(seconds * rate)
        var phase = 0.0
        var out = (0..<count).map { i -> Float in
            let t = Double(i) / rate
            phase += 2 * .pi * (frequency + 40 * exp(-t * 60)) / rate
            return Float(sin(phase) * 0.9 + sin(phase * 2) * 0.1)
        }
        envelope(&out, attack: 0.004, release: 0.04)
        return out
    }

    /// Detuned saws through a soft low-pass: the workhorse for chords and stabs.
    static func saws(_ frequencies: [Double], seconds: Double, detune: Double = 0.006, cutoff: Double, resonance: Double = 0.2,
                     attack: Double, release: Double, decay: Double? = nil) -> [Float] {
        let count = Int(seconds * rate)
        var phases = frequencies.flatMap { [(f: $0 * (1 - detune), p: 0.0), (f: $0 * (1 + detune), p: 0.37)] }
        var out = [Float](repeating: 0, count: count)
        let gain = 0.5 / Float(max(phases.count, 1))
        for i in 0..<count {
            var value: Float = 0
            for v in phases.indices {
                phases[v].p += phases[v].f / rate
                let p = phases[v].p - floor(phases[v].p)
                value += Float(2 * p - 1)
            }
            out[i] = value * gain
        }
        let filtered = lowpass(out, cutoff: { i in
            guard let decay else { return cutoff }
            return 300 + (cutoff - 300) * exp(-Double(i) / rate / decay)
        }, resonance: resonance)
        var shaped = filtered
        envelope(&shaped, attack: attack, release: release)
        if let decay {
            for i in shaped.indices { shaped[i] *= Float(exp(-Double(i) / rate / (decay * 2))) }
        }
        return shaped
    }

    /// A 303-style note: saw into a resonant filter with its own snappy sweep.
    static func acid(_ frequency: Double, seconds: Double, accent: Bool) -> [Float] {
        let count = Int(seconds * rate)
        var phase = 0.0
        let raw = (0..<count).map { _ -> Float in
            phase += frequency / rate
            phase -= floor(phase)
            return Float(2 * phase - 1) * 0.5
        }
        let peak = accent ? 3200.0 : 1300.0
        var out = lowpass(raw, cutoff: { i in 220 + (peak - 220) * exp(-Double(i) / rate * 14) }, resonance: accent ? 0.86 : 0.78)
        envelope(&out, attack: 0.003, release: 0.02)
        return out
    }

    /// Electric-piano tone: a sine with a couple of soft harmonics and slow tremolo.
    static func keys(_ frequencies: [Double], seconds: Double) -> [Float] {
        let count = Int(seconds * rate)
        var out = [Float](repeating: 0, count: count)
        for frequency in frequencies {
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / rate
                phase += 2 * .pi * frequency / rate
                let tone = sin(phase) + 0.35 * sin(phase * 2) * exp(-t * 3) + 0.12 * sin(phase * 3) * exp(-t * 6)
                out[i] += Float(tone * exp(-t * 1.2) * (0.9 + 0.1 * sin(2 * .pi * 4.5 * t)))
            }
        }
        for i in out.indices { out[i] /= Float(max(frequencies.count, 1)) * 1.4 }
        envelope(&out, attack: 0.004, release: 0.08)
        return out
    }

    /// A Karplus–Strong plucked string.
    static func pluck(_ frequency: Double, seconds: Double, brightness: Float = 0.498) -> [Float] {
        let count = Int(seconds * rate)
        let period = max(2, Int(rate / frequency))
        var generator = SeededGenerator(seed: UInt64(frequency * 10))
        var line = (0..<period).map { _ in Float.random(in: -1...1, using: &generator) }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let index = i % period
            let next = (i + 1) % period
            out[i] = line[index]
            line[index] = (line[index] + line[next]) * brightness
        }
        envelope(&out, attack: 0.001, release: 0.02)
        return out
    }

    /// A wide, growling bass: two saws an octave apart, slowly wobbling filter.
    static func reese(_ frequency: Double, seconds: Double) -> [Float] {
        saws([frequency, frequency * 0.5], seconds: seconds, detune: 0.012, cutoff: 700, resonance: 0.45, attack: 0.01, release: 0.05)
    }

    // MARK: Drums

    static func kick(decay: Double = 9, punch: Double = 110) -> [Float] {
        let length = Int(rate * 0.4)
        var phase = 0.0
        return (0..<length).map { i in
            let t = Double(i) / rate
            let frequency = 45 + punch * exp(-t * 28)
            phase += 2 * .pi * frequency / rate
            return Float(tanh(sin(phase) * 1.6) * exp(-t * decay))
        }
    }

    static func snare(seed: UInt64 = 11) -> [Float] {
        let length = Int(rate * 0.22)
        var generator = SeededGenerator(seed: seed)
        var phase = 0.0
        var low: Float = 0
        return (0..<length).map { i in
            let t = Double(i) / rate
            phase += 2 * .pi * 185 / rate
            let noise = Float.random(in: -1...1, using: &generator)
            low += (noise - low) * 0.35
            let body = Float(sin(phase) * exp(-t * 30)) * 0.6
            let snap = (noise - low * 0.5) * Float(exp(-t * 18)) * 0.5
            return body + snap
        }
    }

    static func clap(seed: UInt64 = 7) -> [Float] {
        let length = Int(rate * 0.22)
        var generator = SeededGenerator(seed: seed)
        var low: Float = 0
        return (0..<length).map { i in
            let t = Double(i) / rate
            let burst = t < 0.03 ? exp(-fmod(t, 0.01) * 300) : exp(-(t - 0.03) * 22)
            let noise = Float.random(in: -1...1, using: &generator)
            low += (noise - low) * 0.25
            return (noise - low) * Float(burst) * 0.6
        }
    }

    static func hat(open: Bool, seed: UInt64 = 5) -> [Float] {
        let length = Int(rate * (open ? 0.2 : 0.05))
        var generator = SeededGenerator(seed: seed)
        var previous: Float = 0
        return (0..<length).map { i in
            let t = Double(i) / rate
            let noise = Float.random(in: -1...1, using: &generator)
            let high = noise - previous
            previous = noise
            return high * Float(exp(-t * (open ? 16 : 70))) * 0.18
        }
    }

    static func shaker(seed: UInt64 = 9) -> [Float] {
        let length = Int(rate * 0.07)
        var generator = SeededGenerator(seed: seed)
        var band: Float = 0
        var low: Float = 0
        return (0..<length).map { i in
            let t = Double(i) / rate
            let noise = Float.random(in: -1...1, using: &generator)
            low += (noise - low) * 0.5
            band += ((noise - low) - band) * 0.6
            return band * Float(exp(-t * 55)) * 0.25
        }
    }
}

/// A small deterministic random generator so generated sounds are identical every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
