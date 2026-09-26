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
    let equalizer = AVAudioUnitEQ(numberOfBands: 3)
    var low: Float = 0 { didSet { equalizer.bands[0].gain = low } }
    var mid: Float = 0 { didSet { equalizer.bands[1].gain = mid } }
    var high: Float = 0 { didSet { equalizer.bands[2].gain = high } }
    private var cueStorageKey = ""
    private(set) var hotCues: [Double?] = Array(repeating: nil, count: 4)

    var isPlaying = false {
        didSet { updateMotor() }
    }
    /// Speed offset like a tempo fader: −0.16 is 16% slower, 0.16 is 16% faster.
    var tempo: Double = 0 {
        didSet { updateMotor() }
    }
    var tempoRange: TempoRange = .standard {
        didSet { tempo = min(max(tempo, -tempoRange.limit), tempoRange.limit) }
    }
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

    func load(_ sample: Sample) {
        sampleName = sample.name
        peaks = sample.peaks
        duration = sample.duration
        bpm = sample.bpm
        turntable.setSample(sample.frames)
        restoreCues(for: sample)
    }

    private func restoreCues(for sample: Sample) {
        // Audio identity stays stable across imports and does not collide on filenames.
        let digest = sample.frames.withUnsafeBytes { SHA256.hash(data: $0) }
        cueStorageKey = "hotCues." + digest.map { String(format: "%02x", $0) }.joined()
        let stored = UserDefaults.standard.array(forKey: cueStorageKey) as? [Double]
        if let stored, stored.count == 4 {
            hotCues = stored.map { $0.isFinite && $0 >= 0 && $0 < 1 ? $0 : nil }
        } else {
            hotCues = Array(repeating: nil, count: 4)
        }
    }

    func fireCue(_ index: Int) {
        guard hotCues.indices.contains(index) else { return }
        if let saved = hotCues[index] {
            turntable.cueRequest.store(Float(saved), ordering: .relaxed)
        } else {
            hotCues[index] = min(max(position, 0), 0.999999)
            saveCues()
        }
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

    /// Moves the tempo fader so the track plays at this tempo, widening the
    /// range if it has to. A track with no tempo yet is tagged with it instead.
    func setBPM(_ target: Double) {
        guard target > 0 else { return }
        guard let bpm, bpm > 0 else {
            self.bpm = target
            return
        }
        let wanted = target / bpm - 1
        if let range = TempoRange.fitting(wanted), range.limit > tempoRange.limit {
            tempoRange = range
        }
        tempo = min(max(wanted, -tempoRange.limit), tempoRange.limit)
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
