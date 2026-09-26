import AVFoundation

/// Reads an audio file into a sample the decks can play.
enum AudioImporter {
    /// Longest import kept, in seconds.
    static let maxDuration: Double = 360
    /// Frames decoded per read, so long files never need one huge buffer.
    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Decodes a file, mixes it to mono, resamples it to the engine rate, and
    /// finds its beat grid. `limit` caps the length in seconds; nil keeps it all.
    static func load(_ url: URL, name: String? = nil, kind: Sample.Kind = .imported, limit: Double? = maxDuration) throws -> Sample {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let cap = limit.map { Int64(format.sampleRate * $0) } ?? .max
        let total = min(file.length, cap)
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var mono: [Float] = []
        mono.reserveCapacity(Int(total))
        while file.framePosition < total {
            let remaining = AVAudioFrameCount(min(Int64(chunkFrames), total - file.framePosition))
            try file.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else { break }
            mix(buffer, into: &mono)
        }

        let resampled = SampleProcessing.resample(mono, from: format.sampleRate, to: Sample.sampleRate)
        let frames = SampleProcessing.normalize(resampled)
        let grid = BeatDetector.analyze(frames, sampleRate: Sample.sampleRate)
        return Sample(
            name: name ?? url.deletingPathExtension().lastPathComponent,
            frames: frames,
            bpm: grid?.bpm,
            beatOffset: grid?.firstBeat ?? 0,
            kind: kind
        )
    }

    private static func mix(_ buffer: AVAudioPCMBuffer, into mono: inout [Float]) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let data = buffer.floatChannelData, channels > 0 else { return }
        let gain = 1 / Float(channels)
        let start = mono.count
        mono.append(contentsOf: repeatElement(0, count: frames))
        for channel in 0..<channels {
            let source = data[channel]
            for i in 0..<frames {
                mono[start + i] += source[i] * gain
            }
        }
    }
}
