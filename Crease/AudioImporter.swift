import AVFoundation

/// Reads an audio file from Files into a sample the decks can play.
enum AudioImporter {
    /// Longest import kept, in seconds.
    static let maxDuration: Double = 90

    static func load(_ url: URL) throws -> Sample {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(min(file.length, Int64(format.sampleRate * maxDuration)))
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer, frameCount: frameCount)

        let mono = monoMix(buffer)
        let resampled = SampleProcessing.resample(mono, from: format.sampleRate, to: Sample.sampleRate)
        let name = url.deletingPathExtension().lastPathComponent
        return Sample(name: name, frames: SampleProcessing.normalize(resampled), bpm: nil, kind: .imported)
    }

    private static func monoMix(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let data = buffer.floatChannelData, channels > 0 else { return [] }
        var out = [Float](repeating: 0, count: frames)
        let gain = 1 / Float(channels)
        for channel in 0..<channels {
            let source = data[channel]
            for i in 0..<frames {
                out[i] += source[i] * gain
            }
        }
        return out
    }
}
