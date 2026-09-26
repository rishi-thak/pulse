import SwiftUI

/// A glass pad that fires the instant it's touched, lighting up and sending a ripple out.
struct PadView: View {
    var pad: Pad
    var hits: Int
    var onTrigger: () -> Void

    @State private var isPressed = false
    @State private var flash = 0.0
    @State private var ripple = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [pad.color.opacity(0.28 + flash * 0.5), pad.color.opacity(0.06 + flash * 0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if ripple > 0 {
                Circle()
                    .stroke(pad.color, lineWidth: 2)
                    .scaleEffect(0.2 + ripple * 1.6)
                    .opacity(1 - ripple)
                    .blendMode(.plusLighter)
            }

            PadThumbnail(peaks: pad.peaks, color: pad.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
        }
        .clipShape(shape)
        .overlay(alignment: .topLeading) {
            Text(pad.title)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.35 + flash * 0.5), pad.color.opacity(0.4 + flash * 0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(color: pad.color.opacity(flash * 0.9), radius: 14 + flash * 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.snappy(duration: 0.12), value: isPressed)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onTrigger()
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .onChange(of: hits) {
            flash = 1
            withAnimation(.smooth(duration: 0.5)) {
                flash = 0
            }
            guard !reduceMotion else { return }
            ripple = 0.01
            withAnimation(.easeOut(duration: 0.45)) {
                ripple = 1
            } completion: {
                ripple = 0
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: hits)
        .accessibilityElement()
        .accessibilityLabel("Pad \(pad.index + 1)")
        .accessibilityValue(pad.accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onTrigger()
        }
    }
}

/// A tiny mirrored waveform of the audio a pad plays.
private struct PadThumbnail: View {
    var peaks: [Float]
    var color: Color

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let step = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let height = max(2, CGFloat(peak) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * step + step * 0.2,
                    y: (size.height - height) / 2,
                    width: step * 0.6,
                    height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: step * 0.3), with: .color(color.opacity(0.8)))
            }
        }
        .accessibilityHidden(true)
    }
}
