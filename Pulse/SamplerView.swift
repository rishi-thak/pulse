import SwiftUI

/// The instrument: pads to perform with, and a visualizer that reshapes as you fold.
struct SamplerView: View {
    @Bindable var engine: SamplerEngine
    @Environment(\.openURL) private var openURL
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            stage
            .background(Color.black, ignoresSafeAreaEdges: .all)
            .navigationTitle(engine.isRecording ? "Recording…" : "Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .modifier(HingeObserver(engine: engine))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                engine.importAudio(from: url, onto: nil)
            }
        }
        .alert(
            engine.alert?.title ?? "",
            isPresented: Binding(
                get: { engine.alert != nil },
                set: { if !$0 { engine.alert = nil } }
            ),
            presenting: engine.alert
        ) { alert in
            if alert.offersSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    /// Pads float over the visualizer; when the device is partially folded,
    /// the arrangement moves the visualizer to the top or leading half and
    /// the pads to the bottom or trailing half.
    @ViewBuilder
    private var stage: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                PerformanceView(engine: engine)
            } secondary: {
                VisualizerView(engine: engine)
            }
            .arrangementViewStyle(.overlay)
        } else {
            ZStack {
                VisualizerView(engine: engine)
                PerformanceView(engine: engine)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The turntables carry their own transport, so this only shows without them.
        if !engine.isDeckShowing {
            ToolbarItem(placement: .primaryAction) {
                Toggle(
                    engine.deckA.isPlaying ? "Pause" : "Play",
                    systemImage: engine.deckA.isPlaying ? "pause.fill" : "play.fill",
                    isOn: Binding(
                        get: { engine.deckA.isPlaying },
                        set: { _ in engine.togglePlay(engine.deckA) }
                    )
                )
                .toggleStyle(.button)
                .buttonStyle(.glassProminent)
                .disabled(engine.isRecording)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle("Freeze", systemImage: "snowflake", isOn: $engine.isFrozen)
                .toggleStyle(.button)
                .buttonStyle(.glassProminent)
                .tint(engine.isFrozen ? .cyan : .gray)
                .disabled(engine.isRecording)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(
                engine.isRecording ? "Stop Recording" : "Record",
                systemImage: engine.isRecording ? "stop.fill" : "microphone.fill"
            ) {
                engine.toggleRecording()
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Toggle("DJ Deck", systemImage: "dial.medium.fill", isOn: $engine.prefersDeck)
                .toggleStyle(.button)

            Menu("Pads", systemImage: engine.padMode.systemImage) {
                Picker("Pad Layout", selection: $engine.padMode) {
                    ForEach(PadMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                if engine.padMode == .keys {
                    Picker("Scale", selection: $engine.scale) {
                        ForEach(PadScale.allCases) { scale in
                            Text(scale.title).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Menu("Sample", systemImage: "waveform") {
                Toggle("Reverse", systemImage: "arrow.uturn.backward", isOn: $engine.isReversed)
                Button("Reset Trim", systemImage: "arrow.left.and.right") {
                    engine.resetTrim()
                }
                .disabled(engine.trim == 0...1)
            }
            .disabled(engine.isRecording)

            LibraryMenu(engine: engine, title: "Library", systemImage: "music.note.list") { chosen in
                engine.load(chosen, onto: engine.deckA)
            } onImport: {
                isImporting = true
            }
        }
    }
}

/// Feeds the device hinge into the engine on systems that report it.
private struct HingeObserver: ViewModifier {
    var engine: SamplerEngine

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                engine.updateHinge(HingeReading(newContext.hinge))
            }
        } else {
            content
        }
    }
}
