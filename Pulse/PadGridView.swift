import SwiftUI

/// Sixteen pads laid out like a hardware sampler, with pad 1 at the bottom left.
struct PadGridView: View {
    var engine: SamplerEngine

    private let columns = 4

    var body: some View {
        let rows = Pad.count / columns
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach((0..<rows).reversed(), id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if engine.pads.indices.contains(index) {
                            PadView(
                                pad: engine.pads[index],
                                hits: engine.padHits[index]
                            ) {
                                engine.trigger(index)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
