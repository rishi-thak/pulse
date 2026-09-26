import SwiftUI

/// The second screen: the sample as a sheet of light that recolours and
/// reshapes as you fold, with trim handles at its edges and a finger-hold
/// that freezes the sound.
/// In deck mode a second sheet shows channel 2 beneath channel 1.
struct VisualizerView: View {
    @Bindable var engine: SamplerEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = StageLayout(size: proxy.size, isSplit: engine.isHingeBending)
            let showsDecks = engine.showsDeck(in: layout)
            let full = layout.waveformRect
            let rowGap: CGFloat = 36
            let rowHeight = (full.height - rowGap) / 2
            let rect = showsDecks ? CGRect(x: full.minX, y: full.minY, width: full.width, height: rowHeight) : full
            let rectB = CGRect(x: full.minX, y: full.minY + rowHeight + rowGap, width: full.width, height: rowHeight)

            TimelineView(.animation) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    RibbonView(engine: engine, layer: mainLayer(rect: rect, showsDecks: showsDecks), time: time)
                    if showsDecks {
                        RibbonView(engine: engine, layer: deckLayer(rect: rectB), time: time)
                            .blendMode(.plusLighter)
                    }
                }
            }
            .contentShape(.rect)
            .gesture(scrubGesture(rect: rect))
            .accessibilityElement()
            .accessibilityLabel(showsDecks ? "Waveforms of channel 1 and channel 2" : "Waveform of \(engine.sample.name)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Touch and hold to freeze the sound at that point")

            if !engine.isRecording {
                TrimHandle(edge: .leading, rect: rect, trim: $engine.trim)
                TrimHandle(edge: .trailing, rect: rect, trim: $engine.trim)
            }

            caption(title: showsDecks ? engine.deckA.slot.name : nil, color: Deck.Slot.a.color)
                .frame(maxWidth: max(rect.width, 0), alignment: .leading)
                .offset(x: rect.minX, y: max(rect.minY - 56, 8))
                .allowsHitTesting(false)

            if showsDecks {
                deckCaption
                    .frame(maxWidth: max(rectB.width, 0), alignment: .leading)
                    .offset(x: rectB.minX, y: rectB.minY - 30)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Layers

    /// With the decks showing, this sheet is channel 1 and moves only when it
    /// plays. Otherwise it's the whole instrument and follows the mix.
    private func mainLayer(rect: CGRect, showsDecks: Bool) -> RibbonLayer {
        let recording = engine.isRecording
        return RibbonLayer(
            rect: rect,
            peaks: recording ? livePeaks : engine.sample.peaks,
            hue: recording ? 0.99 : hue(base: Deck.Slot.a.hue),
            trim: engine.trim,
            heads: engine.playheads().flatMap { [Float($0.position), $0.shaderHue] },
            level: showsDecks ? Float(engine.deckA.meter) : engine.outputLevel,
            isMoving: showsDecks ? engine.deckA.isAudible : true,
            isRecording: recording,
            drawsBackground: true
        )
    }

    private func deckLayer(rect: CGRect) -> RibbonLayer {
        let deck = engine.deckB
        return RibbonLayer(
            rect: rect,
            peaks: deck.peaks,
            hue: hue(base: Deck.Slot.b.hue),
            trim: 0...1,
            heads: deck.isAudible ? [Float(deck.position), -1] : [],
            level: Float(deck.meter),
            isMoving: deck.isAudible,
            isRecording: false,
            drawsBackground: false
        )
    }

    /// Bending pitch up drifts each sheet's colour along the wheel.
    private func hue(base: Double) -> Float {
        let semitones = engine.shape.pitchCents / 100
        return Float((base - Double(semitones) / 12 * 0.17 + 1).truncatingRemainder(dividingBy: 1))
    }

    /// While recording, fill the sheet from the left as sound arrives.
    private var livePeaks: [Float] {
        let live = engine.livePeaks
        let count = Sample.peakCount
        let recorded = engine.recordingElapsed / RecordingBuffer.maxDuration
        guard !live.isEmpty, recorded > 0 else { return Array(repeating: 0, count: count) }
        return (0..<count).map { index in
            let fraction = Double(index) / Double(count)
            guard fraction < recorded else { return 0 }
            return live[min(live.count - 1, Int(fraction / recorded * Double(live.count)))]
        }
    }

    // MARK: Gestures

    private func scrubGesture(rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard rect.width > 0, !engine.isRecording else { return }
                engine.touchScrub(to: Double((value.location.x - rect.minX) / rect.width))
            }
            .onEnded { _ in
                engine.touchScrub(to: nil)
            }
    }

    // MARK: Captions

    @ViewBuilder
    private func caption(title: String?, color: Color) -> some View {
        if engine.isRecording {
            Label {
                Text("\(engine.recordingElapsed.formatted(.number.precision(.fractionLength(1)))) s of \(Int(RecordingBuffer.maxDuration)) s")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "microphone.fill")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let title {
                        Text(title)
                            .foregroundStyle(color)
                        Text(engine.sample.name)
                            .lineLimit(1)
                    }
                    Text(durationText)
                        .monospacedDigit()
                    if engine.grainPosition != nil {
                        Label("Frozen", systemImage: "snowflake")
                            .foregroundStyle(.cyan)
                            .transition(.opacity)
                    }
                }
                .font(.subheadline.weight(.semibold))
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .animation(.smooth(duration: 0.25), value: engine.grainPosition != nil)
        }
    }

    private var deckCaption: some View {
        HStack(spacing: 8) {
            Text(engine.deckB.slot.name)
                .foregroundStyle(Deck.Slot.b.color)
            Text(engine.deckB.sampleName)
                .lineLimit(1)
            if let bpm = engine.deckB.effectiveBPM {
                Text("\(Int(bpm.rounded())) BPM")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private var hintText: String {
        var parts = ["Hold to freeze", "drag the edges to trim"]
        if engine.isReversed { parts.insert("Reversed", at: 0) }
        return parts.joined(separator: " · ")
    }

    private var durationText: String {
        let trimmed = engine.sample.duration * (engine.trim.upperBound - engine.trim.lowerBound)
        return "\(trimmed.formatted(.number.precision(.fractionLength(2)))) s"
    }

    private var accessibilityValue: String {
        engine.isRecording ? "Recording" : "\(durationText), folded \(engine.foldAmount.formatted(.percent.precision(.fractionLength(0))))"
    }
}

/// Everything one sheet needs beyond the shared fold state.
private struct RibbonLayer {
    var rect: CGRect
    var peaks: [Float]
    var hue: Float
    var trim: ClosedRange<Double>
    /// Pairs of position and hue for each playhead beam.
    var heads: [Float]
    /// This sheet's own loudness, which swells its body.
    var level: Float
    /// Whether the sheet's ripple animates; a silent channel holds still.
    var isMoving: Bool
    var isRecording: Bool
    var drawsBackground: Bool
}

/// Feeds one sheet's data and the engine's fold state into the ribbon shader.
private struct RibbonView: View {
    var engine: SamplerEngine
    var layer: RibbonLayer
    var time: Double

    var body: some View {
        let shape = engine.shape
        let rect = layer.rect
        Rectangle()
            .fill(.black)
            .colorEffect(ShaderLibrary.ribbon(
                .boundingRect,
                .float4(Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY)),
                .float(Float(time.truncatingRemainder(dividingBy: 3600))),
                .float(Float(engine.foldAmount)),
                .float(layer.level),
                .float(engine.outputLevel),
                .float(layer.isMoving ? 1 : 0),
                .float(layer.hue),
                .float(shape.rate),
                .float(shape.texture),
                .float(filterAmount(for: shape)),
                .float2(Float(layer.trim.lowerBound), Float(layer.trim.upperBound)),
                .float(layer.isRecording ? 1 : 0),
                .float(layer.drawsBackground ? 1 : 0),
                .floatArray(layer.peaks),
                // The shader needs at least one entry to bind.
                .floatArray(layer.heads.isEmpty ? [-1, -1] : layer.heads)
            ))
    }

    private func filterAmount(for shape: SoundShape) -> Float {
        log(SoundShape.maxCutoff / shape.cutoff) / log(SoundShape.maxCutoff / SoundShape.minCutoff)
    }
}

/// A draggable edge that trims where the sample starts or ends.
private struct TrimHandle: View {
    var edge: HorizontalEdge
    var rect: CGRect
    @Binding var trim: ClosedRange<Double>

    private let minimumLength = 0.04

    var body: some View {
        let fraction = edge == .leading ? trim.lowerBound : trim.upperBound
        Capsule()
            .fill(.white)
            .frame(width: 4, height: max(rect.height * 0.8, 24))
            .shadow(color: .black.opacity(0.4), radius: 4)
            .frame(width: 44, height: max(rect.height, 44))
            .contentShape(.rect)
            .position(x: rect.minX + rect.width * fraction, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard rect.width > 0 else { return }
                        set(Double((value.location.x - rect.minX) / rect.width))
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(edge == .leading ? "Sample start" : "Sample end")
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 0.02 : -0.02
                set(fraction + delta)
            }
    }

    private func set(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        switch edge {
        case .leading:
            trim = min(clamped, trim.upperBound - minimumLength)...trim.upperBound
        case .trailing:
            trim = trim.lowerBound...max(clamped, trim.lowerBound + minimumLength)
        }
    }
}
