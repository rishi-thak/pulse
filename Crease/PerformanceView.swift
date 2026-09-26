import SwiftUI

/// The playing surface: the fold panel above a 4×4 grid of pads.
struct PerformanceView: View {
    var engine: SamplerEngine

    var body: some View {
        GeometryReader { proxy in
            let layout = StageLayout(size: proxy.size, isSplit: engine.isHingeBending)
            let controls = Group {
                if engine.prefersDeck || (layout.isSplit && layout.isWide) {
                    // Laptop pose, or the deck asked for outright: two turntables on the flat half.
                    DeckView(engine: engine)
                } else if layout.isSplit && layout.isWide {
                    // Folded into a wide half: pads beside the hinge panel so both stay big.
                    HStack(alignment: .center, spacing: 16) {
                        PadGridView(engine: engine)
                        FoldPanel(engine: engine)
                            .frame(maxWidth: 380)
                    }
                } else {
                    VStack(spacing: 12) {
                        FoldPanel(engine: engine)
                        PadGridView(engine: engine)
                    }
                }
            }
            .padding(StageLayout.margin)
            .frame(width: layout.controlsSize.width, height: layout.controlsSize.height, alignment: .bottom)

            if layout.isWide {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controls
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
    }
}
