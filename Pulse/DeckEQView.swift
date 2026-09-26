import SwiftUI

struct DeckEQView: View {
    @Bindable var deck: Deck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Three-band equalizer") {
                    band("Low", value: $deck.low)
                    band("Mid", value: $deck.mid)
                    band("High", value: $deck.high)
                    Button("Reset EQ") { deck.resetEQ() }
                }
                Section {
                    Text("EQ changes only this channel. Tap an empty hot cue to save the current position, then tap it again to jump back. Touch and hold a cue to clear it.")
                }
            }
            .navigationTitle("\(deck.slot.name) EQ")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func band(_ title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) dB")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: -24...6) { Text(title) }
                .tint(deck.slot.color)
                .accessibilityValue("\(Int(value.wrappedValue)) decibels")
        }
    }
}
