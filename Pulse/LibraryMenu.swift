import SwiftUI

/// Every sound the app has: bundled tracks, demo sounds, recordings, and imports.
struct LibraryMenu<Label: View>: View {
    var engine: SamplerEngine
    var onChoose: (Sample) -> Void
    var onImport: () -> Void
    var label: () -> Label

    init(engine: SamplerEngine, onChoose: @escaping (Sample) -> Void, onImport: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.engine = engine
        self.onChoose = onChoose
        self.onImport = onImport
        self.label = label
    }

    var body: some View {
        Menu {
            Button("Import Audio…", systemImage: "square.and.arrow.down") {
                onImport()
            }
            section("Tracks", kind: .track)
            section("Recordings", kind: .recording)
            section("Imports", kind: .imported)
            section("Sounds", kind: .sound)
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .disabled(engine.isRecording)
    }

    @ViewBuilder
    private func section(_ title: String, kind: Sample.Kind) -> some View {
        let samples = engine.library.filter { $0.kind == kind }
        if !samples.isEmpty {
            Section(title) {
                ForEach(samples) { sample in
                    Button {
                        onChoose(sample)
                    } label: {
                        if let bpm = sample.bpm {
                            Text("\(sample.name)  ·  \(Int(bpm)) BPM")
                        } else {
                            Text(sample.name)
                        }
                    }
                }
            }
        }
    }
}

extension LibraryMenu where Label == SwiftUI.Label<Text, Image> {
    init(engine: SamplerEngine, title: String, systemImage: String = "tray.and.arrow.down", onChoose: @escaping (Sample) -> Void, onImport: @escaping () -> Void) {
        self.init(engine: engine, onChoose: onChoose, onImport: onImport) {
            SwiftUI.Label(title, systemImage: systemImage)
        }
    }
}
