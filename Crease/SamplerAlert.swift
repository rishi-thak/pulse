import Foundation

/// Problems worth telling the person about, with how to recover.
enum SamplerAlert: String, Identifiable {
    case microphoneDenied
    case noMicrophone
    case tooQuiet
    case audioUnavailable
    case importFailed

    var id: Self { self }

    var title: String {
        switch self {
        case .microphoneDenied: "Microphone Access Needed"
        case .noMicrophone: "No Microphone Found"
        case .tooQuiet: "Nothing Recorded"
        case .audioUnavailable: "Audio Unavailable"
        case .importFailed: "Couldn't Import"
        }
    }

    var message: String {
        switch self {
        case .microphoneDenied:
            "Allow microphone access for Crease in Settings to record sounds."
        case .noMicrophone:
            "Connect a microphone or try again on a device with one."
        case .tooQuiet:
            "The recording was silent. Move closer to the sound and try again."
        case .audioUnavailable:
            "Crease couldn't start audio. Close other audio apps and try again."
        case .importFailed:
            "That file couldn't be read as audio. Try an MP3, M4A, WAV, or AIFF."
        }
    }

    var offersSettings: Bool {
        self == .microphoneDenied
    }
}
