import SwiftUI

/// The hinge readout: an arc that tracks the fold, and chips for what folding bends.
struct FoldPanel: View {
    @Bindable var engine: SamplerEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                HingeGauge(fold: engine.foldAmount, angle: engine.hinge?.angle, isLive: engine.isHingeBending)
                    .frame(width: 64, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    if let statusDetail {
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.smooth(duration: 0.2), value: statusTitle)

                Spacer(minLength: 0)

                if !engine.isHingeBending {
                    Slider(value: $engine.manualFold, in: 0...1) {
                        Text("Fold")
                    }
                    .frame(maxWidth: 160)
                }
            }

            CenteredGrid(minimumItemWidth: 52, spacing: 6) {
                ForEach(FoldTarget.allCases) { target in
                    targetToggle(target)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var statusTitle: String {
        guard let hinge = engine.hinge else {
            return "Fold \(engine.foldAmount.formatted(.percent.precision(.fractionLength(0))))"
        }
        switch hinge.status {
        case .closed: return "Closed"
        case .fullyOpen: return "Flat"
        case .partiallyOpen: return "\(Int(hinge.angle.degrees.rounded()))°"
        }
    }

    /// A hint for getting started; nothing while bending, since the buttons already show what's on.
    private var statusDetail: String? {
        guard let hinge = engine.hinge else { return "Slide, or fold the phone" }
        switch hinge.status {
        case .closed: return "Open the phone to play"
        case .fullyOpen: return "Fold the phone to bend"
        case .partiallyOpen: return nil
        }
    }

    private func targetToggle(_ target: FoldTarget) -> some View {
        let isOn = Binding(
            get: { engine.foldTargets.contains(target) },
            set: { enabled in
                if enabled {
                    engine.foldTargets.insert(target)
                } else {
                    engine.foldTargets.remove(target)
                }
            }
        )
        return Toggle(isOn: isOn) {
            VStack(spacing: 2) {
                Image(systemName: target.systemImage)
                    .font(.footnote)
                Text(target.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value(for: target))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
                    .opacity(isOn.wrappedValue ? 0.9 : 0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isOn.wrappedValue ? Color.accentColor : .gray)
        .accessibilityHint(target.summary)
    }

    private func value(for target: FoldTarget) -> String {
        let shape = engine.shape
        return switch target {
        case .pitch: shape.pitchDescription
        case .stretch: shape.rateDescription
        case .texture: shape.textureDescription
        case .filter: shape.cutoffDescription
        case .scrub: engine.grainPosition.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
        }
    }
}

/// A half-circle that closes as the device folds, like a hinge seen end-on.
private struct HingeGauge: View {
    var fold: Double
    var angle: Angle?
    var isLive: Bool

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width / 2, size.height) - 3
            let center = CGPoint(x: size.width / 2, y: size.height - 2)

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            context.stroke(track, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            var fill = Path()
            fill.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 - fold * 180), clockwise: false)
            context.stroke(fill, with: .color(isLive ? .cyan : .accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Two leaves of the phone meeting at the hinge.
            let leaf = radius - 4
            var leaves = Path()
            leaves.move(to: CGPoint(x: center.x - leaf, y: center.y))
            leaves.addLine(to: center)
            let openAngle = Double.pi * (1 - fold)
            leaves.addLine(to: CGPoint(x: center.x + leaf * cos(openAngle) * -1, y: center.y - leaf * sin(openAngle)))
            context.stroke(leaves, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Equal-width cells that wrap into rows, with a short last row centered instead of left-aligned.
private struct CenteredGrid: Layout {
    var minimumItemWidth: CGFloat
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(subviews.count) * (minimumItemWidth + spacing) - spacing
        let rows = rows(for: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let itemWidth = itemWidth(for: bounds.width, count: subviews.count)
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            let rowWidth = CGFloat(row.indices.count) * (itemWidth + spacing) - spacing
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for index in row.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: itemWidth, height: row.height)
                )
                x += itemWidth + spacing
            }
            y += row.height + spacing
        }
    }

    private func columns(for width: CGFloat, count: Int) -> Int {
        max(1, min(count, Int((width + spacing) / (minimumItemWidth + spacing))))
    }

    private func itemWidth(for width: CGFloat, count: Int) -> CGFloat {
        let columns = CGFloat(columns(for: width, count: count))
        return (width - spacing * (columns - 1)) / columns
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: Range<Int>, height: CGFloat)] {
        let columns = columns(for: width, count: subviews.count)
        let itemWidth = itemWidth(for: width, count: subviews.count)
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            let indices = start..<min(start + columns, subviews.count)
            let height = indices
                .map { subviews[$0].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }
                .max() ?? 0
            return (indices, height)
        }
    }
}
