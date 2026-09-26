import Foundation

/// Full songs shipped in the app bundle, decoded at launch.
enum Song: String, CaseIterable, Identifiable {
    case thisRhythm = "This Rhythm"
    case loveSongs = "Love Songs"

    var id: Self { self }

    var title: String {
        switch self {
        case .thisRhythm: "Prospa – This Rhythm"
        case .loveSongs: "Prospa & Kosmo Kint – Love Songs"
        }
    }

    func makeSample() throws -> Sample {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "flac") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try AudioImporter.load(url, name: title, kind: .track, limit: nil)
    }
}
