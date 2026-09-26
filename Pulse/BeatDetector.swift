import Foundation

/// Finds a sample's tempo and beat grid from where its energy jumps.
///
/// Onsets are rises in log energy. The tempo is the lag at which those rises
/// repeat most strongly, and the first downbeat is the phase of that period
/// that lands on the loudest hits.
enum BeatDetector {
    struct Grid {
        var bpm: Double
        /// Seconds from the start of the sample to its first downbeat.
        var firstBeat: Double
    }

    static let minBPM = 60.0
    static let maxBPM = 200.0
    /// Samples per step of the onset envelope.
    private static let hop = 256
    /// How clearly the beat has to repeat before the result is trusted.
    private static let minimumConfidence: Float = 0.1

    /// How much hats and snares count next to kicks. Kicks sit on the beat;
    /// hats fill the off-beats and would otherwise blur it.
    private static let highBandWeight: Float = 0.4

    static func analyze(_ frames: [Float], sampleRate: Double) -> Grid? {
        let stepsPerSecond = sampleRate / Double(hop)
        let onset = onsetEnvelope(frames, sampleRate: sampleRate)
        guard Double(onset.count) >= stepsPerSecond * 2 else { return nil }
        guard let period = beatPeriod(of: onset, stepsPerSecond: stepsPerSecond) else { return nil }
        let first = firstDownbeat(of: onset, period: period)
        return Grid(bpm: 60 * stepsPerSecond / period, firstBeat: first / stepsPerSecond)
    }

    /// Rises in log energy per step, measured in a low band for kicks and a
    /// high band for hats and snares, so drums register under sustained chords.
    private static func onsetEnvelope(_ frames: [Float], sampleRate: Double) -> [Float] {
        let count = frames.count / hop
        guard count > 1 else { return [] }
        let lowCoefficient = Float(1 - exp(-2 * Double.pi * 160 / sampleRate))
        let midCoefficient = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate))
        var lowEnergy = [Float](repeating: 0, count: count)
        var highEnergy = [Float](repeating: 0, count: count)
        var low: Float = 0
        var mid: Float = 0
        frames.withUnsafeBufferPointer { source in
            for step in 0..<count {
                var lowSum: Float = 0
                var highSum: Float = 0
                let start = step * hop
                for i in start..<(start + hop) {
                    let x = source[i]
                    low += lowCoefficient * (x - low)
                    mid += midCoefficient * (x - mid)
                    let high = x - mid
                    lowSum += low * low
                    highSum += high * high
                }
                lowEnergy[step] = log(1 + lowSum / Float(hop) * 400)
                highEnergy[step] = log(1 + highSum / Float(hop) * 4000)
            }
        }
        let lowRises = rises(in: lowEnergy)
        let highRises = rises(in: highEnergy)
        return (0..<count).map { lowRises[$0] + highRises[$0] * highBandWeight }
    }

    /// Positive jumps in a band's energy, standardized so bands compare evenly.
    private static func rises(in energy: [Float]) -> [Float] {
        let count = energy.count
        var out = [Float](repeating: 0, count: count)
        for step in 1..<count {
            out[step] = max(energy[step] - energy[step - 1], 0)
        }
        let mean = out.reduce(0, +) / Float(count)
        let deviation = (out.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(count)).squareRoot()
        guard deviation > 0 else { return [Float](repeating: 0, count: count) }
        return out.map { ($0 - mean) / deviation }
    }

    /// The beat length in steps, or nil when nothing repeats convincingly.
    private static func beatPeriod(of onset: [Float], stepsPerSecond: Double) -> Double? {
        let count = onset.count
        let minLag = Int(stepsPerSecond * 60 / maxBPM)
        let maxLag = min(Int(stepsPerSecond * 60 / minBPM), count / 2)
        guard minLag >= 1, maxLag > minLag else { return nil }

        // Normalized autocorrelation out to four beats at the slowest tempo,
        // so a candidate can be checked against its multiples.
        let lagLimit = min(maxLag * 8, count - 1)
        var zero: Float = 0
        for value in onset { zero += value * value }
        zero /= Float(count)
        guard zero > 0 else { return nil }
        var acf = [Float](repeating: 0, count: lagLimit + 1)
        onset.withUnsafeBufferPointer { o in
            for lag in 1...lagLimit {
                var sum: Float = 0
                for i in lag..<count {
                    sum += o[i] * o[i - lag]
                }
                acf[lag] = sum / Float(count - lag) / zero
            }
        }

        // A beat repeats at two, three, and four beats too, which a half-beat
        // or a bar does not, and tempos near 125 win ties.
        func score(_ lag: Int) -> Float {
            var total: Float = 0
            for multiple in 1...4 where lag * multiple <= lagLimit {
                total += acf[lag * multiple] / Float(multiple)
            }
            let bpm = 60 * stepsPerSecond / Double(lag)
            let preference = exp(-pow(log2(bpm / 125), 2) / 0.9)
            return total * Float(preference)
        }
        // Refines an integer lag to a fractional period using the four-beat peak.
        func refine(_ lag: Int) -> Double {
            let multiple = (1...8).reversed().first { lag * $0 + $0 / 2 <= lagLimit } ?? 1
            let center = lag * multiple
            var peak = center
            for candidate in (center - multiple / 2)...(center + multiple / 2) where candidate > 0 && candidate <= lagLimit && acf[candidate] > acf[peak] {
                peak = candidate
            }
            var refined = Double(peak)
            if peak > 1, peak < lagLimit {
                let left = Double(acf[peak - 1])
                let mid = Double(acf[peak])
                let right = Double(acf[peak + 1])
                let curve = left - 2 * mid + right
                if curve < 0 {
                    refined += 0.5 * (left - right) / curve
                }
            }
            return refined / Double(multiple)
        }

        // Local maxima of the comb score are the candidates.
        var candidates: [(lag: Int, score: Float)] = []
        for lag in minLag...maxLag {
            let here = score(lag)
            let left = lag > minLag ? score(lag - 1) : -.infinity
            let right = lag < maxLag ? score(lag + 1) : -.infinity
            if here >= left, here >= right { candidates.append((lag, here)) }
        }
        candidates.sort { $0.score > $1.score }
        let shortlist = candidates.prefix(6).filter { acf[$0.lag] >= minimumConfidence }
        guard !shortlist.isEmpty else { return nil }

        // A grid on the true beat lands on a hit at every slot; a grid at one
        // and a half beats lands on off-beats half the time. Judge the shortlist
        // by the average onset a grid captures per slot at its best phase.
        let smooth = (0..<count).map { i in
            (onset[max(i - 1, 0)] + onset[i] + onset[min(i + 1, count - 1)]) / 3
        }
        // Judged in short windows with the phase refit in each, so a tiny
        // period error can't walk the grid off the beat over a long song.
        let window = Int(stepsPerSecond * 8)
        func capture(_ period: Double) -> Float {
            var total: Float = 0
            var windows = 0
            var start = 0
            while start < count {
                let end = min(start + window, count)
                var best = -Float.infinity
                var phase = 0.0
                while phase < period {
                    var sum: Float = 0
                    var slots = 0
                    var t = Double(start) + phase
                    while Int(t.rounded()) < end {
                        sum += smooth[Int(t.rounded())]
                        slots += 1
                        t += period
                    }
                    if slots > 0 { best = max(best, sum / Float(slots)) }
                    phase += 0.5
                }
                if best > -.infinity {
                    total += best
                    windows += 1
                }
                start = end
            }
            return windows > 0 ? total / Float(windows) : -.infinity
        }
        var bestPeriod = refine(shortlist[0].lag)
        var bestCapture = -Float.infinity
        for candidate in shortlist {
            let period = refine(candidate.lag)
            let bpm = 60 * stepsPerSecond / period
            let preference = Float(exp(-pow(log2(bpm / 125), 2) / 0.9))
            let value = capture(period) * preference
            if value > bestCapture {
                bestCapture = value
                bestPeriod = period
            }
        }
        return bestPeriod
    }

    /// The step of the first downbeat: the beat phase that lines up with the
    /// most onsets, then whichever of the four beats in a bar hits hardest.
    private static func firstDownbeat(of onset: [Float], period: Double) -> Double {
        let count = onset.count
        // Slightly smoothed, so a hit a step off the grid still counts.
        let smooth = (0..<count).map { i in
            (onset[max(i - 1, 0)] + onset[i] + onset[min(i + 1, count - 1)]) / 3
        }
        func total(from start: Double, every stride: Double) -> Float {
            var sum: Float = 0
            var t = start
            while Int(t.rounded()) < count {
                sum += smooth[Int(t.rounded())]
                t += stride
            }
            return sum
        }

        var bestPhase = 0.0
        var bestSum = -Float.infinity
        for quarter in 0..<max(Int(period * 4), 1) {
            let phase = Double(quarter) / 4
            let sum = total(from: phase, every: period)
            if sum > bestSum {
                bestSum = sum
                bestPhase = phase
            }
        }

        var bestBeat = 0
        bestSum = -Float.infinity
        for beat in 0..<4 {
            let sum = total(from: bestPhase + Double(beat) * period, every: period * 4)
            if sum > bestSum {
                bestSum = sum
                bestBeat = beat
            }
        }
        return bestPhase + Double(bestBeat) * period
    }
}
