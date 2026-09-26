import AVFoundation
import CryptoKit
import Observation
import SwiftUI

/// One side of the DJ deck: a turntable, the sample on it, and its transport state.
@MainActor
@Observable
final class Deck {
    enum Slot: String, CaseIterable, Identifiable {
        case a
        case b

        var id: Self { self }

        /// The channel number shown on the platter and mixer.
        var title: String {
            switch self {
            case .a: "1"
            case .b: "2"
            }
        }

        var name: String {
            "Channel \(title)"
        }

        var color: Color {
            switch self {
            case .a: Color(hue: 0.08, saturation: 0.85, brightness: 1)
            case .b: Color(hue: 0.78, saturation: 0.7, brightness: 1)
            }
        }

        /// Hue the shader uses for this deck's playhead beam.
        var hue: Double {
            switch self {
            case .a: 0.08
            case .b: 0.78
            }
        }
    }

    let slot: Slot
    let turntable = Turntable()

    private(set) var sampleName: String
    private(set) var peaks: [Float]
    private(set) var duration: Double
    private(set) var bpm: Double?
    /// Seconds into the sample where its first downbeat falls.
    private(set) var beatOffset: Double
    let equalizer = AVAudioUnitEQ(numberOfBands: 3)
    var low: Float = 0 { didSet { equalizer.bands[0].gain = low } }
    var mid: Float = 0 { didSet { equalizer.bands[1].gain = mid } }
    var high: Float = 0 { didSet { equalizer.bands[2].gain = high } }
    private var cueStorageKey = ""
    private(set) var hotCues: [Double?] = Array(repeating: nil, count: 4)

    var isPlaying = false {
        didSet {
            if isPlaying, !oldValue { playStartedAt = .now }
            updateMotor()
        }
    }
    /// When play was last pressed, so beat sync can tell which deck leads.
    private(set) var playStartedAt: Date?
    /// Speed offset like a tempo fader: −0.16 is 16% slower, 0.16 is 16% faster.
    var tempo: Double = 0 {
        didSet { updateMotor() }
    }
    /// How far the tempo can move either way; four times slower to four times faster.
    private static let tempoLimits = -0.75...3.0
    /// The fold's pitch and stretch bend, applied on top of the fader.
    private var bend: Float = 1
    /// 1 forwards, −1 when the sample is reversed.
    private var direction: Float = 1
    /// Channel fader, from silent to full.
    var level: Double = 1 {
        didSet { turntable.gain.store(Float(level), ordering: .relaxed) }
    }

    init(slot: Slot, sample: Sample) {
        self.slot = slot
        sampleName = sample.name
        peaks = sample.peaks
        duration = sample.duration
        bpm = sample.bpm
        beatOffset = sample.beatOffset
        turntable.setSample(sample.frames)
        restoreCues(for: sample)
        for (index, frequency) in [Float(180), 1000, 8000].enumerated() {
            let band = equalizer.bands[index]
            band.filterType = index == 0 ? .lowShelf : (index == 2 ? .highShelf : .parametric)
            band.frequency = frequency
            band.bandwidth = 1
            band.bypass = false
        }
    }

    /// Drops a new track on the platter at its own tempo.
    func load(_ sample: Sample) {
        sampleName = sample.name
        peaks = sample.peaks
        duration = sample.duration
        bpm = sample.bpm
        beatOffset = sample.beatOffset
        tempo = 0
        turntable.setSample(sample.frames)
        restoreCues(for: sample)
    }

    private func restoreCues(for sample: Sample) {
        // Keyed on the audio itself, so cues survive renames and don't collide on
        // filenames. A stride through the frames identifies a track without
        // hashing every sample of a long song on the main thread.
        var hasher = SHA256()
        withUnsafeBytes(of: sample.frames.count) { hasher.update(bufferPointer: $0) }
        for index in stride(from: 0, to: sample.frames.count, by: 997) {
            withUnsafeBytes(of: sample.frames[index]) { hasher.update(bufferPointer: $0) }
        }
        cueStorageKey = "hotCues." + hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let stored = UserDefaults.standard.array(forKey: cueStorageKey) as? [Double]
        if let stored, stored.count == 4 {
            hotCues = stored.map { $0.isFinite && $0 >= 0 && $0 < 1 ? $0 : nil }
        } else {
            hotCues = Array(repeating: nil, count: 4)
        }
    }

    /// Jumps to a saved cue, or saves the needle's spot as a new one. New cues
    /// snap to the nearest beat when the tempo is known, so jumping between
    /// them keeps a beat-synced pair in time.
    func fireCue(_ index: Int) {
        guard hotCues.indices.contains(index) else { return }
        if let saved = hotCues[index] {
            turntable.cueRequest.store(Float(saved), ordering: .relaxed)
        } else {
            hotCues[index] = min(max(quantized(position), 0), 0.999999)
            saveCues()
        }
    }

    /// The nearest beat to a position, as a fraction of the sample.
    private func quantized(_ position: Double) -> Double {
        guard let bpm, bpm > 0, duration > 0 else { return position }
        let beatSeconds = 60 / bpm
        let seconds = position * duration
        let beats = ((seconds - beatOffset) / beatSeconds).rounded()
        return (beatOffset + beats * beatSeconds) / duration
    }

    func clearCue(_ index: Int) {
        guard hotCues.indices.contains(index) else { return }
        hotCues[index] = nil
        saveCues()
    }

    private func saveCues() {
        UserDefaults.standard.set(hotCues.map { $0 ?? -1 }, forKey: cueStorageKey)
    }

    func resetEQ() {
        low = 0
        mid = 0
        high = 0
    }

    /// Tempo after the fader, when the track's tempo is known.
    var effectiveBPM: Double? {
        bpm.map { $0 * (1 + tempo) }
    }

    /// Plays the track at this tempo. A track with no tempo yet is tagged with it instead.
    func setBPM(_ target: Double) {
        guard target > 0 else { return }
        guard let bpm, bpm > 0 else {
            self.bpm = target
            return
        }
        let wanted = target / bpm - 1
        tempo = min(max(wanted, Self.tempoLimits.lowerBound), Self.tempoLimits.upperBound)
    }

    // MARK: Beat grid

    /// Seconds per bar in the sample's own time, when the tempo is known.
    private var barSeconds: Double? {
        bpm.map { 240 / $0 }
    }

    /// How far through the current bar the needle is, from 0 to 1.
    var barPhase: Double? {
        guard let barSeconds else { return nil }
        let bars = (position * duration - beatOffset) / barSeconds
        return bars - floor(bars)
    }

    /// The spot nearest the needle that sits at this point in a bar, as a fraction of the sample.
    func position(atBarPhase phase: Double) -> Double? {
        guard let barSeconds, duration > 0 else { return nil }
        let now = position * duration
        let bar = floor((now - beatOffset) / barSeconds)
        let candidates = [bar - 1, bar, bar + 1].map { beatOffset + ($0 + phase) * barSeconds }
        let inside = candidates.filter { $0 >= 0 && $0 < duration }
        guard let nearest = (inside.isEmpty ? candidates : inside).min(by: { abs($0 - now) < abs($1 - now) }) else { return nil }
        return min(max(nearest / duration, 0), 0.9999)
    }

    /// Takes the engine's fold bend and play direction, then respins the motor.
    func drive(bend: Float, direction: Float) {
        self.bend = bend
        self.direction = direction
        updateMotor()
    }

    private func updateMotor() {
        let motor = isPlaying ? Float(1 + tempo) * bend * direction : 0
        turntable.motorRate.store(motor, ordering: .relaxed)
    }

    /// Where the needle is, as a fraction of the sample.
    var position: Double {
        Double(turntable.position.load(ordering: .relaxed))
    }

    var isScratching: Bool {
        turntable.isScratching.load(ordering: .relaxed)
    }

    /// Output loudness for the channel meter.
    var meter: Double {
        Double(turntable.level.load(ordering: .relaxed))
    }

    var isAudible: Bool {
        isPlaying || isScratching
    }
}
