import SwiftUI

/// A platter you spin to scratch, with transport and a tempo fader beneath it.
struct TurntableView: View {
    var engine: SamplerEngine
    @Bindable var deck: Deck
    @State private var isImporting = false
    @State private var showsEQ = false
    @State private var isSettingBPM = false
    @State private var bpmText = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            Platter(engine: engine, deck: deck)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            hotCueButtons
            transport
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showsEQ) {
            DeckEQView(deck: deck)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                engine.importAudio(from: url, onto: deck)
            }
        }
        .alert("Set Tempo", isPresented: $isSettingBPM) {
            TextField("BPM", text: $bpmText)
                .keyboardType(.decimalPad)
            Button("Set") {
                if let value = Double(bpmText) {
                    deck.setBPM(value)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bpmMessage)
        }
    }

    private var hotCueButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HOT CUES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Button { engine.fireHotCue(index, on: deck) } label: {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(deck.slot.color.opacity(deck.hotCues[index] == nil ? 0.12 : 0.6), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(deck.hotCues[index] == nil ? "Set" : "Jump to") hot cue \(index + 1)")
                    .accessibilityHint("Touch and hold for the clear action")
                    .contextMenu {
                        Button("Clear cue", role: .destructive) { deck.clearCue(index) }
                            .disabled(deck.hotCues[index] == nil)
                    }
                }
            }
        }
    }

    /// Names the other channel and the tempo this one would take on.
    private var matchTitle: String {
        let partner = engine.partner(of: deck)
        if let bpm = partner.effectiveBPM {
            return "Match \(partner.slot.name) · \(Int(bpm.rounded())) BPM"
        }
        return "Match \(partner.slot.name)"
    }

    private var bpmMessage: String {
        if let bpm = deck.bpm {
            return "\(deck.sampleName) is \(Int(bpm.rounded())) BPM. The tempo fader moves to match, widening its range if it has to."
        }
        return "\(deck.sampleName) has no tempo yet. Enter one so it can be synced."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(deck.slot.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(deck.slot.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Button("EQ") { showsEQ = true }
                    .accessibilityLabel("\(deck.slot.name) equalizer")
                LibraryMenu(engine: engine, title: "Load") { chosen in
                    engine.load(chosen, onto: deck)
                } onImport: {
                    isImporting = true
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            HStack(spacing: 6) {
                Text(deck.sampleName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Menu {
                    Button("Set Tempo…", systemImage: "number") {
                        bpmText = deck.effectiveBPM.map { String(Int($0.rounded())) } ?? ""
                        isSettingBPM = true
                    }
                    Button(matchTitle, systemImage: "metronome.fill") {
                        engine.sync(deck)
                    }
                    .disabled(!engine.canSync(deck))
                } label: {
                    if let bpm = deck.effectiveBPM {
                        Text("\(Int(bpm.rounded())) BPM")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else {
                        Text("Set BPM")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(deck.slot.color)
                .fixedSize()
                .accessibilityLabel("Tempo")
                .accessibilityValue(deck.effectiveBPM.map { "\(Int($0.rounded())) beats per minute" } ?? "Unknown")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button("Cue", systemImage: "backward.end.fill") {
                engine.cue(deck)
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)

            Toggle(
                deck.isPlaying ? "Pause" : "Play",
                systemImage: deck.isPlaying ? "pause.fill" : "play.fill",
                isOn: Binding(
                    get: { deck.isPlaying },
                    set: { _ in engine.togglePlay(deck) }
                )
            )
            .toggleStyle(.button)
            .buttonStyle(.glassProminent)
            .tint(deck.slot.color)
            .labelStyle(.iconOnly)

            Slider(value: $deck.tempo, in: -deck.tempoRange.limit...deck.tempoRange.limit) {
                Text("Tempo")
            } minimumValueLabel: {
                Text("−")
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("+")
                    .accessibilityHidden(true)
            }
            .tint(deck.slot.color)
            .accessibilityValue("\(deck.tempo > 0 ? "+" : "")\(Int((deck.tempo * 100).rounded()))%")
        }
        .font(.caption.weight(.semibold))
    }
}

/// The record itself: the sample wrapped around its rim, spinning under a fixed needle.
private struct Platter: View {
    var engine: SamplerEngine
    var deck: Deck

    @State private var lastTouch: (angle: Double, time: Double)?
    @State private var smoothedRate = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            TimelineView(.animation(paused: !deck.isAudible)) { _ in
                Canvas { context, _ in
                    draw(in: &context, center: center, radius: size / 2)
                }
            }
            .contentShape(Circle().size(width: size, height: size).offset(x: center.x - size / 2, y: center.y - size / 2))
            .gesture(scratchGesture(center: center))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(deck.slot.name) platter")
        .accessibilityValue(deck.isPlaying ? "Playing" : "Stopped")
        .accessibilityHint("Drag around the platter to scratch")
    }

    // MARK: Scratching

    /// A full turn of the platter is the whole sample, so angular speed maps
    /// straight onto playback speed.
    private func scratchGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                let now = Date.now.timeIntervalSinceReferenceDate
                if let last = lastTouch {
                    var delta = angle - last.angle
                    if delta > .pi { delta -= 2 * .pi }
                    if delta < -.pi { delta += 2 * .pi }
                    let elapsed = max(now - last.time, 0.004)
                    let rate = delta / (2 * .pi) * deck.duration / elapsed
                    smoothedRate = smoothedRate * 0.4 + min(max(rate, -6), 6) * 0.6
                } else {
                    smoothedRate = 0
                }
                lastTouch = (angle, now)
                engine.scratch(deck, rate: smoothedRate)
            }
            .onEnded { _ in
                lastTouch = nil
                smoothedRate = 0
                engine.endScratch(deck)
            }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let color = deck.slot.color
        let position = deck.position
        let audible = deck.isAudible

        // The disc.
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [Color(white: 0.16), Color(white: 0.05)]),
            center: center, startRadius: 0, endRadius: radius
        ))
        if audible {
            context.stroke(disc, with: .color(color.opacity(0.6)), lineWidth: 2)
        }

        // Grooves.
        for step in stride(from: 0.42, through: 0.66, by: 0.04) {
            let r = radius * step
            let groove = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(groove, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }

        // The sample wrapped around the rim; the point under the needle is what's playing.
        let peaks = deck.peaks
        let inner = radius * 0.7
        let outer = radius * 0.96
        let trim = deck.slot == .a ? engine.trim : 0...1
        let spin = -position * 2 * .pi - .pi / 2
        for (index, peak) in peaks.enumerated() {
            let fraction = Double(index) / Double(peaks.count)
            let theta = spin + fraction * 2 * .pi
            let length = inner + (outer - inner) * CGFloat(peak)
            var bar = Path()
            bar.move(to: CGPoint(x: center.x + inner * cos(theta), y: center.y + inner * sin(theta)))
            bar.addLine(to: CGPoint(x: center.x + length * cos(theta), y: center.y + length * sin(theta)))
            let inTrim = trim.contains(fraction)
            context.stroke(bar, with: .color(color.opacity(inTrim ? 0.85 : 0.2)), lineWidth: max(1, radius / 120))
        }

        // Label.
        let labelRadius = radius * 0.34
        let label = Path(ellipseIn: CGRect(x: center.x - labelRadius, y: center.y - labelRadius, width: labelRadius * 2, height: labelRadius * 2))
        context.fill(label, with: .color(color.opacity(audible ? 0.9 : 0.5)))
        context.draw(
            Text(deck.slot.title).font(.system(size: labelRadius * 0.9, weight: .black, design: .rounded)).foregroundStyle(.black.opacity(0.8)),
            at: center
        )
        let spindle = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
        context.fill(spindle, with: .color(.black))

        // The needle, fixed at the top.
        var needle = Path()
        needle.move(to: CGPoint(x: center.x, y: center.y - outer - 6))
        needle.addLine(to: CGPoint(x: center.x, y: center.y - inner + 4))
        context.stroke(needle, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        context.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
