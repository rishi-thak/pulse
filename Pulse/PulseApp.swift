import SwiftUI

@main
struct PulseApp: App {
    @State private var engine = SamplerEngine()

    var body: some Scene {
        WindowGroup {
            SamplerView(engine: engine)
                .preferredColorScheme(.dark)
        }
    }
}
