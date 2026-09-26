import AVFoundation
import Observation
import SwiftUI

/// Owns the sample, the pads, and the audio graph that turns fold gestures into sound.
@MainActor
@Observable
final class SamplerEngine {
    // MARK: Sample and pads

    private(set) var sample: Sample
    private(set) var pads: [Pad] = []
    /// Increments each time a pad fires, so its view can flash.
    private(set) var padHits = Array(repeating: 0, count: Pad.count)

    /// The part of the sample the pads use, as fractions of its length.
    var trim: ClosedRange<Double> = 0...1 {
        didSet { rebuildPads() }
    }

    var isReversed = false {
        didSet { rebuildPads() }
    }

    var padMode: PadMode {
        didSet {
            UserDefaults.standard.set(padMode.rawValue, forKey: Keys.padMode)
            stopAllVoices()
            rebuildPads()
        }
    }

    var scale: PadScale {
        didSet {
            UserDefaults.standard.set(scale.rawValue, forKey: Keys.scale)
            rebuildPads()
        }
    }

    // MARK: Folding

    var foldTargets: Set<FoldTarget> {
        didSet {
            UserDefaults.standard.set(foldTargets.map(\.rawValue), forKey: Keys.foldTargets)
            applyShape()
        }
    }

    /// Fold amount set on screen, used whenever the hinge isn't bending the sound.
    var manualFold: Double = 0 {
        didSet { applyShape() }
    }

    private(set) var hinge: HingeReading?
    private var hingeFold: Double = 0
    /// Hinge angle when fully open, learned from the device, used as the neutral point.
    private var openAngle = Angle.degrees(180)

    /// Whether the physical hinge is currently driving the fold amount.
    var isHingeBending: Bool {
        hinge?.status == .partiallyOpen
    }

    /// How folded the instrument is, from 0 (flat) to 1 (fully bent).
    var foldAmount: Double {
        isHingeBending ? hingeFold : manualFold
    }

    var shape: SoundShape {
        SoundShape(fold: foldAmount, targets: foldTargets)
    }

    // MARK: Freezing

    /// Whether the grain cloud is held on, independent of touch or fold.
    var isFrozen = false {
        didSet { updateGrains() }
    }

    /// Where a finger on the waveform is holding the sound, as a fraction of the sample.
    private(set) var touchPosition: Double?

    /// Where the grain cloud currently sits, if it's audible.
    var grainPosition: Double? {
        isGrainAudible ? Double(grainCloud.position.load(ordering: .relaxed)) : nil
    }

    private var isGrainAudible: Bool {
        isFrozen || touchPosition != nil || (foldTargets.contains(.scrub) && foldAmount > 0.01)
    }

    // MARK: DJ deck

    let deckA: Deck
    let deckB: Deck
    /// Every sound loaded so far, so either deck can pick one up.
    private(set) var library: [Sample]

    private var hasChosenDeckB = false

    /// Shows the DJ deck in every pose, not just laptop pose.
    var prefersDeck: Bool {
        didSet { UserDefaults.standard.set(prefersDeck, forKey: Keys.prefersDeck) }
    }

    /// Whether both turntables are on screen for this layout.
    func showsDeck(in layout: StageLayout) -> Bool {
        prefersDeck || (layout.isSplit && layout.isWide)
    }

    /// Set by the stage as it lays out, so the toolbar can drop the transport
    /// controls each turntable already carries.
    var isDeckShowing = false

    // MARK: Recording

    private(set) var isRecording = false
    var alert: SamplerAlert?
    private var recordingCount = 0
    private var autoStopTask: Task<Void, Never>?

    var livePeaks: [Float] { recordingBuffer.livePeaks }
    var recordingElapsed: Double { recordingBuffer.elapsed }
    var outputLevel: Float { levelMeter.current }

    // MARK: Audio graph

    private let engine = AVAudioEngine()
    private let submix = AVAudioMixerNode()
    private let distortion = AVAudioUnitDistortion()
    private let filter = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()
    private let voices = (0..<10).map { _ in Voice() }
    private let grainCloud = GrainCloud()
    private var grainNode: AVAudioSourceNode?
    private var deckNodes: [AVAudioSourceNode] = []
    private var nextVoice = 0
    private var padBuffers: [AVAudioPCMBuffer] = []
    private let format = AVAudioFormat(standardFormatWithSampleRate: Sample.sampleRate, channels: 1)!
    private let recordingBuffer = RecordingBuffer()
    private let levelMeter = LevelMeter()
    private var isInputConfigured = false

    private enum Keys {
        static let padMode = "padMode"
        static let scale = "scale"
        static let foldTargets = "foldTargets"
        static let prefersDeck = "prefersDeck"
    }

    init() {
        let defaults = UserDefaults.standard
        padMode = defaults.string(forKey: Keys.padMode).flatMap(PadMode.init) ?? .slices
        scale = defaults.string(forKey: Keys.scale).flatMap(PadScale.init) ?? .minorPentatonic
        foldTargets = Set((defaults.stringArray(forKey: Keys.foldTargets) ?? [FoldTarget.pitch.rawValue, FoldTarget.scrub.rawValue])
            .compactMap(FoldTarget.init))
        let beat = DemoSound.beat.makeSample()
        let voice = DemoSound.voice.makeSample()
        sample = beat
        prefersDeck = defaults.bool(forKey: Keys.prefersDeck)
        library = [beat, voice, DemoSound.pluck.makeSample()]
        deckA = Deck(slot: .a, sample: beat)
        deckB = Deck(slot: .b, sample: voice)
        generateTracks()

        configureSession()
        buildGraph()
        grainCloud.setSample(sample.frames)
        rebuildPads()
        applyShape()
        startEngine()
    }

    // MARK: Playing

    func trigger(_ index: Int) {
        guard pads.indices.contains(index), !padBuffers.isEmpty else { return }
        startEngine()

        // Retriggering a pad chokes its previous voice, like a hardware sampler.
        for voice in voices where voice.padIndex == index {
            voice.stop()
        }

        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()

        let pad = pads[index]
        let buffer = padMode == .keys ? padBuffers[0] : padBuffers[index]
        voice.padIndex = index
        voice.baseCents = padMode == .keys ? Float(pad.semitones * 100) : 0
        voice.frameCount = buffer.frameLength
        voice.region = pad.region
        voice.isReversed = isReversed
        voice.apply(shape)
        voice.player.scheduleBuffer(buffer, at: nil)
        voice.player.play()
        padHits[index] += 1
    }

    func playheads() -> [Playhead] {
        var result = voices.enumerated().compactMap { offset, voice -> Playhead? in
            guard let padIndex = voice.padIndex, let progress = voice.progress else { return nil }
            return Playhead(id: offset, source: .pad(padIndex), position: position(of: voice, at: progress))
        }
        if let grainPosition {
            result.append(Playhead(id: -2, source: .grain, position: grainPosition))
        }
        // Only deck A plays the sample on screen, so only it gets a beam.
        if deckA.isAudible {
            result.append(Playhead(id: -3, source: .deck(.a), position: deckA.position))
        }
        return result
    }

    private func position(of voice: Voice, at progress: Double) -> Double {
        let region = voice.region
        let travelled = (region.upperBound - region.lowerBound) * progress
        return voice.isReversed ? region.upperBound - travelled : region.lowerBound + travelled
    }

    // MARK: DJ deck

    /// Renders the bundled tracks off the main thread and drops them into the library.
    private func generateTracks() {
        Task.detached(priority: .userInitiated) { [weak self] in
            for track in Track.allCases {
                let rendered = track.makeSample()
                await MainActor.run {
                    guard let self else { return }
                    self.library.append(rendered)
                    // Put the first track on channel 2 unless something else was chosen.
                    if track == Track.allCases.first, !self.hasChosenDeckB {
                        self.deckB.load(rendered)
                    }
                }
            }
        }
    }

    /// The deck on the other side of the mixer.
    func partner(of deck: Deck) -> Deck {
        deck === deckA ? deckB : deckA
    }

    /// Matches this deck's tempo to the other deck, widening its fader range if needed.
    func sync(_ deck: Deck) {
        guard let target = partner(of: deck).effectiveBPM, deck.bpm != nil else { return }
        deck.setBPM(target)
    }

    func canSync(_ deck: Deck) -> Bool {
        deck.bpm != nil && partner(of: deck).bpm != nil
    }

    func importAudio(from url: URL, onto deck: Deck?) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let imported = try? AudioImporter.load(url)
            await MainActor.run {
                guard let self else { return }
                guard let imported else {
                    self.alert = .importFailed
                    return
                }
                self.library.insert(imported, at: 0)
                self.load(imported, onto: deck ?? self.deckA)
            }
        }
    }

    func togglePlay(_ deck: Deck) {
        deck.isPlaying.toggle()
        if deck.isPlaying { startEngine() }
    }

    func fireHotCue(_ index: Int, on deck: Deck) {
        guard deck.hotCues.indices.contains(index) else { return }
        if deck === deckA, let saved = deck.hotCues[index], !trim.contains(saved) {
            resetTrim()
        }
        deck.fireCue(index)
    }

    func cue(_ deck: Deck) {
        deck.turntable.cueRequest.store(deck.turntable.loopStart.load(ordering: .relaxed), ordering: .relaxed)
    }

    func scratch(_ deck: Deck, rate: Double) {
        startEngine()
        deck.turntable.scratchRate.store(Float(rate), ordering: .relaxed)
        deck.turntable.scratchTimestamp.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
        deck.turntable.isScratching.store(true, ordering: .relaxed)
    }

    func endScratch(_ deck: Deck) {
        deck.turntable.isScratching.store(false, ordering: .relaxed)
    }

    func load(_ librarySample: Sample, onto deck: Deck) {
        if deck === deckA {
            load(librarySample)
        } else {
            hasChosenDeckB = true
            deck.load(librarySample)
        }
        applyDeckRates()
    }

    private func applyDeckRates() {
        let shape = shape
        let bend = pow(2, shape.pitchCents / 1200) * shape.rate
        for deck in [deckA, deckB] {
            deck.drive(bend: bend, direction: deck === deckA && isReversed ? -1 : 1)
        }
    }

    /// Keeps deck A's loop matched to the trim handles.
    private func syncDeckA() {
        deckA.turntable.loopStart.store(Float(trim.lowerBound), ordering: .relaxed)
        deckA.turntable.loopEnd.store(Float(trim.upperBound), ordering: .relaxed)
        applyDeckRates()
    }

    // MARK: Freezing and scrubbing

    /// Holds the sound at a spot in the sample while a finger rests on the waveform.
    func touchScrub(to position: Double?) {
        touchPosition = position.map { min(max($0, trim.lowerBound), trim.upperBound) }
        updateGrains()
    }

    func load(_ demo: DemoSound) {
        padMode = demo.preferredMode
        load(demo.makeSample())
    }

    func resetTrim() {
        trim = 0...1
    }

    // MARK: Hinge

    func updateHinge(_ reading: HingeReading?) {
        hinge = reading
        guard let reading else {
            hingeFold = 0
            applyShape()
            return
        }
        switch reading.status {
        case .fullyOpen:
            openAngle = reading.angle
            hingeFold = 0
        case .closed:
            hingeFold = 0
        case .partiallyOpen:
            // Measure distance from flat so the mapping holds whichever way the angle is reported.
            let bend = abs(openAngle.degrees - reading.angle.degrees)
            hingeFold = min(max((bend - 5) / 85, 0), 1)
        }
        applyShape()
    }

    // MARK: Recording

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        // Keep the app's own sound out of the microphone.
        isFrozen = false
        for deck in [deckA, deckB] where deck.isPlaying {
            togglePlay(deck)
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            alert = .microphoneDenied
            return
        }

        if !isInputConfigured {
            // The input node must join the graph while the engine is stopped.
            engine.stop()
            isInputConfigured = true
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            alert = .noMicrophone
            startEngine()
            return
        }

        recordingBuffer.reset(sampleRate: inputFormat.sampleRate)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: recordingBuffer.makeTapBlock())
        startEngine()
        guard engine.isRunning else {
            input.removeTap(onBus: 0)
            return
        }
        isRecording = true

        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecordingBuffer.maxDuration))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    private func finishRecording() {
        guard isRecording else { return }
        autoStopTask?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false

        let (frames, sourceRate) = recordingBuffer.take()
        let prepared = SampleProcessing.prepare(frames, sourceRate: sourceRate)
        guard Double(prepared.count) > Sample.sampleRate * 0.05 else {
            alert = .tooQuiet
            return
        }
        recordingCount += 1
        let recording = Sample(name: "Recording \(recordingCount)", frames: prepared, kind: .recording)
        library.insert(recording, at: 0)
        load(recording)
    }

    // MARK: Private

    private func load(_ newSample: Sample) {
        stopAllVoices()
        sample = newSample
        grainCloud.setSample(newSample.frames)
        deckA.load(newSample)
        trim = 0...1
        isReversed = false
        rebuildPads()
    }

    private func stopAllVoices() {
        voices.forEach { $0.stop() }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            alert = .audioUnavailable
        }
    }

    private func buildGraph() {
        [submix, distortion, filter, reverb].forEach(engine.attach)
        for voice in voices {
            engine.attach(voice.player)
            engine.attach(voice.timePitch)
            engine.connect(voice.player, to: voice.timePitch, format: format)
            engine.connect(voice.timePitch, to: submix, format: format)
        }
        let grainNode = grainCloud.makeNode(sampleRate: Sample.sampleRate)
        engine.attach(grainNode)
        engine.connect(grainNode, to: submix, format: format)
        self.grainNode = grainNode

        for deck in [deckA, deckB] {
            let node = deck.turntable.makeNode(sampleRate: Sample.sampleRate)
            engine.attach(node)
            engine.attach(deck.equalizer)
            engine.connect(node, to: deck.equalizer, format: format)
            engine.connect(deck.equalizer, to: submix, format: format)
            deckNodes.append(node)
        }

        engine.connect(submix, to: distortion, format: format)
        engine.connect(distortion, to: filter, format: format)
        engine.connect(filter, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        distortion.loadFactoryPreset(.multiDecimated2)
        let band = filter.bands[0]
        band.filterType = .resonantLowPass
        band.bandwidth = 0.6
        band.bypass = false
        reverb.loadFactoryPreset(.mediumHall)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: levelMeter.makeTapBlock())
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            alert = .audioUnavailable
        }
    }

    private func applyShape() {
        let shape = shape
        voices.forEach { $0.apply(shape) }
        distortion.wetDryMix = shape.texture * 65
        reverb.wetDryMix = shape.texture * 40
        filter.bands[0].frequency = shape.cutoff
        updateGrains()
        applyDeckRates()
    }

    /// Points the grain cloud at whatever is steering it: a finger, the fold, or the trim start.
    private func updateGrains() {
        let shape = shape
        let position: Double
        if let touchPosition {
            position = touchPosition
        } else if foldTargets.contains(.scrub) && foldAmount > 0.01 {
            position = trim.lowerBound + foldAmount * (trim.upperBound - trim.lowerBound)
        } else {
            position = trim.lowerBound + 0.001
        }
        grainCloud.position.store(Float(position), ordering: .relaxed)
        grainCloud.rate.store(pow(2, shape.pitchCents / 1200) * (isReversed ? -1 : 1), ordering: .relaxed)
        // Shatter scatters the grains and makes them tiny.
        grainCloud.spread.store(0.012 + shape.texture * 0.2, ordering: .relaxed)
        grainCloud.grainSeconds.store(0.11 - shape.texture * 0.08, ordering: .relaxed)
        grainCloud.gain.store(isGrainAudible ? 0.9 : 0, ordering: .relaxed)
        if isGrainAudible { startEngine() }
    }

    private func rebuildPads() {
        let total = sample.frames.count
        let lower = min(Int(trim.lowerBound * Double(total)), max(total - 1, 0))
        let upper = max(lower + 1, min(Int(trim.upperBound * Double(total)), total))
        let region = sample.frames[lower..<upper]
        let fraction = { (frame: Int) in total > 0 ? Double(frame) / Double(total) : 0 }

        var newPads: [Pad] = []
        var buffers: [AVAudioPCMBuffer] = []

        switch padMode {
        case .slices:
            let sliceLength = max(1, region.count / Pad.count)
            for index in 0..<Pad.count {
                let start = min(region.startIndex + index * sliceLength, region.endIndex - 1)
                let end = index == Pad.count - 1 ? region.endIndex : min(start + sliceLength, region.endIndex)
                let slice = sample.frames[start..<end]
                var peaks = Sample.peaks(of: slice, count: 20)
                if isReversed { peaks.reverse() }
                newPads.append(Pad(
                    index: index,
                    title: "\(index + 1)",
                    accessibilityName: "Slice \(index + 1)",
                    peaks: peaks,
                    semitones: 0,
                    region: fraction(start)...fraction(end)
                ))
                buffers.append(makeBuffer(from: slice))
            }
        case .keys:
            var peaks = Sample.peaks(of: region, count: 20)
            if isReversed { peaks.reverse() }
            for index in 0..<Pad.count {
                let semitones = scale.semitones(forPad: index)
                let title = semitones == 0 ? "0" : semitones > 0 ? "+\(semitones)" : "−\(-semitones)"
                newPads.append(Pad(
                    index: index,
                    title: title,
                    accessibilityName: "\(semitones) semitones",
                    peaks: peaks,
                    semitones: semitones,
                    region: fraction(lower)...fraction(upper)
                ))
            }
            buffers.append(makeBuffer(from: region))
        }

        pads = newPads
        padBuffers = buffers
        updateGrains()
        syncDeckA()
    }

    private func makeBuffer(from frames: ArraySlice<Float>) -> AVAudioPCMBuffer {
        var samples = Array(frames)
        if isReversed { samples.reverse() }
        SampleProcessing.fadeEdges(&samples)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
