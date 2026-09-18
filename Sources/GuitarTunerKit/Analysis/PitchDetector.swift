import Foundation

/// Autocorrelation pitch detector built on the normalised square difference function
/// (NSDF) with McLeod peak picking.
///
/// Why NSDF instead of a plain autocorrelation: dividing the correlation by the summed
/// energy of both windows normalises the result to 0...1, which makes a single clarity
/// threshold meaningful across dynamics and gives the UI an honest confidence value.
///
/// Why MPM peak picking instead of "take the tallest peak": the tallest NSDF peak is
/// often at 2x or 3x the true period. MPM takes the *first* peak that reaches
/// `peakSelectionRatio` of the tallest peak, which removes most octave errors on
/// guitar, where the 2nd harmonic is frequently stronger than the fundamental.
public struct PitchDetector: Sendable {
    public var configuration: PitchDetectionConfiguration

    private var window: [Float] = []
    private var cumulativeEnergy: [Float] = []
    private var nsdf: [Float] = []
    private var peaks: [(index: Int, value: Float)] = []

    public init(configuration: PitchDetectionConfiguration = .default) {
        self.configuration = configuration
    }

    /// Analyses the *most recent* samples. `gate` is the RMS threshold to apply; pass
    /// `nil` to use `configuration.minimumRMS`.
    public mutating func analyze(samples: [Float], sampleRate: Double, gate: Double? = nil) -> PitchAnalysis {
        let config = configuration
        let effectiveGate = max(gate ?? config.minimumRMS, 0)

        guard sampleRate > 0, samples.count >= config.minimumSampleCount else {
            return .silent
        }

        let windowSize = min(samples.count, max(config.analysisWindowSize, config.minimumSampleCount))
        let windowStart = samples.count - windowSize
        prepareWindow(samples: samples, start: windowStart, size: windowSize)

        let rms = rootMeanSquare()
        let level = SignalMetrics.normalizedLevel(rms: rms)
        var analysis = PitchAnalysis(rms: rms, level: level, gate: effectiveGate)

        guard rms >= effectiveGate else {
            analysis.isGated = true
            return analysis
        }

        guard let estimate = estimatePeriod(sampleRate: sampleRate) else {
            return analysis
        }

        analysis.frequency = estimate.frequency
        analysis.clarity = estimate.clarity
        analysis.lag = estimate.lag
        return analysis
    }

    // MARK: - Window preparation

    private mutating func prepareWindow(samples: [Float], start: Int, size: Int) {
        if window.count != size {
            window = [Float](repeating: 0, count: size)
        }
        samples.withUnsafeBufferPointer { source in
            window.withUnsafeMutableBufferPointer { destination in
                guard let sourceBase = source.baseAddress, let destinationBase = destination.baseAddress else { return }
                destinationBase.update(from: sourceBase + start, count: size)
            }
        }

        // Remove DC offset: a floating input can carry a constant bias that would
        // otherwise dominate the very first autocorrelation lags.
        var sum: Float = 0
        for value in window { sum += value }
        let mean = sum / Float(size)
        if mean != 0 {
            for index in window.indices { window[index] -= mean }
        }
    }

    private func rootMeanSquare() -> Double {
        guard !window.isEmpty else { return 0 }
        let sumOfSquares = VectorMath.dot(window, 0, 0, count: window.count)
        return Double((sumOfSquares / Float(window.count)).squareRoot())
    }

    // MARK: - NSDF

    private mutating func estimatePeriod(sampleRate: Double) -> (frequency: Double, clarity: Double, lag: Double)? {
        let config = configuration
        let count = window.count

        let minLag = max(2, Int((sampleRate / config.maxFrequency).rounded(.down)))
        let maxLag = min(Int((sampleRate / config.minFrequency).rounded(.up)), count / 2 - 1)
        guard maxLag > minLag + 2 else { return nil }

        // Every lag correlates the same number of samples so the NSDF stays comparable.
        let correlationLength = count - maxLag
        guard correlationLength >= 64 else { return nil }

        buildCumulativeEnergy()

        if nsdf.count != maxLag + 1 {
            nsdf = [Float](repeating: 0, count: maxLag + 1)
        }

        window.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            nsdf.withUnsafeMutableBufferPointer { output in
                guard let outputBase = output.baseAddress else { return }
                for lag in 0...maxLag {
                    let correlation = VectorMath.dot(base, base + lag, count: correlationLength)
                    let energy = cumulativeEnergy[correlationLength] + (cumulativeEnergy[lag + correlationLength] - cumulativeEnergy[lag])
                    outputBase[lag] = energy > 1e-12 ? (2 * correlation) / energy : 0
                }
            }
        }

        // NSDF is conceptually 1 at lag 0; enforce it even for a silent-ish window.
        nsdf[0] = 1

        guard let peak = selectPeak(minLag: minLag, maxLag: maxLag) else { return nil }
        guard peak.value >= Float(config.minimumClarity) else { return nil }

        let refinedLag = parabolicLag(around: peak.index, minLag: minLag, maxLag: maxLag)
        guard refinedLag > 0 else { return nil }

        let frequency = sampleRate / refinedLag
        guard frequency >= config.minFrequency, frequency <= config.maxFrequency else { return nil }

        return (frequency, Double(peak.value), refinedLag)
    }

    private mutating func buildCumulativeEnergy() {
        let count = window.count
        if cumulativeEnergy.count != count + 1 {
            cumulativeEnergy = [Float](repeating: 0, count: count + 1)
        }
        var running: Float = 0
        cumulativeEnergy[0] = 0
        for index in 0..<count {
            running += window[index] * window[index]
            cumulativeEnergy[index + 1] = running
        }
    }

    /// McLeod peak picking.
    ///
    /// Peaks are the maxima of *closed* positive regions — a region that is bounded by
    /// negative NSDF values on both sides. Requiring both boundaries matters: a small
    /// non-harmonic component (pick noise, a stray high tone) puts a ripple on the nsdf
    /// whose little bumps would otherwise be mistaken for the period.
    ///
    /// The tallest peak is not the answer either: it is usually 2x or 3x the true period.
    /// MPM therefore reports the first peak, in increasing lag, that reaches
    /// `peakSelectionRatio` of the tallest one — that is the fundamental.
    private mutating func selectPeak(minLag: Int, maxLag: Int) -> (index: Int, value: Float)? {
        peaks.removeAll(keepingCapacity: true)

        var lag = 1
        while lag < maxLag {
            while lag < maxLag, nsdf[lag] < 0 { lag += 1 }
            let regionStart = lag
            while lag < maxLag, nsdf[lag] >= 0 { lag += 1 }
            let regionEnd = lag - 1

            // A region only counts when it is *bounded* by negative values: the lag-0
            // region (still rising out of zero) is not a period estimate, and a region
            // that has not been closed yet is not a full period either.
            guard regionStart > 0, nsdf[regionStart - 1] < 0, lag < maxLag, regionEnd >= regionStart else {
                continue
            }

            let lowerBound = max(regionStart, minLag)
            let upperBound = min(regionEnd, maxLag)
            guard lowerBound <= upperBound else { continue }

            var bestIndex = lowerBound
            for index in lowerBound...upperBound where nsdf[index] > nsdf[bestIndex] {
                bestIndex = index
            }
            guard nsdf[bestIndex] > 0 else { continue }
            peaks.append((bestIndex, nsdf[bestIndex]))
        }

        guard let tallest = peaks.max(by: { $0.value < $1.value }) else { return nil }

        let required = tallest.value * Float(configuration.peakSelectionRatio)
        return peaks.first { $0.value >= required } ?? tallest
    }

    /// Sub-sample refinement of the NSDF peak with a parabola through three samples.
    private func parabolicLag(around index: Int, minLag: Int, maxLag: Int) -> Double {
        guard index > minLag, index < maxLag else { return Double(index) }
        let previous = Double(nsdf[index - 1])
        let current = Double(nsdf[index])
        let next = Double(nsdf[index + 1])
        let denominator = previous - 2 * current + next
        guard abs(denominator) > 1e-9 else { return Double(index) }
        let offset = 0.5 * (previous - next) / denominator
        guard abs(offset) <= 1 else { return Double(index) }
        return Double(index) + offset
    }
}
