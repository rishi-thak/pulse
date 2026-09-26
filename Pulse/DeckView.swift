import SwiftUI

/// Two turntables with a mixer between them: the flat half of the phone in laptop pose.
struct DeckView: View {
    @Bindable var engine: SamplerEngine

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height * 1.1
            if isWide {
                HStack(alignment: .center, spacing: 14) {
                    TurntableView(engine: engine, deck: engine.deckA)
                    VStack(spacing: 12) {
                        FoldPanel(engine: engine)
                            .fixedSize(horizontal: false, vertical: true)
                        MixerView(decks: [engine.deckA, engine.deckB], axis: .vertical)
                    }
                    .frame(width: min(max(proxy.size.width * 0.34, 224), 280))
                    TurntableView(engine: engine, deck: engine.deckB)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        TurntableView(engine: engine, deck: engine.deckA)
                        TurntableView(engine: engine, deck: engine.deckB)
                    }
                    MixerView(decks: [engine.deckA, engine.deckB], axis: .horizontal)
                }
            }
        }
    }
}

/// A channel fader per deck, each with its own level meter.
struct MixerView: View {
    var decks: [Deck]
    var axis: Axis

    var body: some View {
        Group {
            if axis == .vertical {
                HStack(spacing: 14) {
                    ForEach(decks, id: \.slot) { deck in
                        ChannelFader(deck: deck, axis: axis)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(decks, id: \.slot) { deck in
                        ChannelFader(deck: deck, axis: axis)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: axis == .vertical ? .infinity : nil)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// One mixer channel: a fader you drag, with the deck's loudness lighting the track behind it.
private struct ChannelFader: View {
    @Bindable var deck: Deck
    var axis: Axis

    var body: some View {
        let color = deck.slot.color
        Group {
            if axis == .vertical {
                VStack(spacing: 6) {
                    Text(deck.slot.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(color)
                    track
                    Text(deck.level, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Text(deck.slot.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(color)
                        .frame(width: 16)
                    track
                        .frame(height: 30)
                    Text(deck.level, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(deck.slot.name) level")
        .accessibilityValue(deck.level.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.05 : -0.05
            deck.level = min(max(deck.level + delta, 0), 1)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let length = axis == .vertical ? size.height : size.width
            let color = deck.slot.color

            TimelineView(.animation(paused: !deck.isAudible)) { _ in
                ZStack(alignment: axis == .vertical ? .bottom : .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                    // The meter glows up the track as the deck plays.
                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.9), color.opacity(0.35)],
                            startPoint: axis == .vertical ? .bottom : .leading,
                            endPoint: axis == .vertical ? .top : .trailing
                        ))
                        .frame(
                            width: axis == .vertical ? nil : length * deck.meter,
                            height: axis == .vertical ? length * deck.meter : nil
                        )
                }
            }
            .overlay(alignment: axis == .vertical ? .bottom : .leading) {
                // The fader cap.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white)
                    .frame(
                        width: axis == .vertical ? size.width + 8 : 14,
                        height: axis == .vertical ? 14 : size.height + 8
                    )
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(
                        x: axis == .vertical ? 0 : (length - 14) * deck.level,
                        y: axis == .vertical ? -(length - 14) * deck.level : 0
                    )
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard length > 0 else { return }
                        let fraction = axis == .vertical
                            ? 1 - value.location.y / length
                            : value.location.x / length
                        deck.level = min(max(Double(fraction), 0), 1)
                    }
            )
        }
        .frame(width: axis == .vertical ? 22 : nil)
        .frame(minHeight: axis == .vertical ? 50 : nil, maxHeight: axis == .vertical ? .infinity : nil)
    }
}
