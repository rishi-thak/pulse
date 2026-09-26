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
    }

    func load(_ sample: Sample) {
        sampleName = sample.name
        peaks = sample.peaks
        duration = sample.duration
        bpm = sample.bpm
        turntable.setSample(sample.frames)
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
