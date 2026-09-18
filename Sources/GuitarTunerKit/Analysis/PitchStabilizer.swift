import Foundation

public struct PitchStabilizerConfiguration: Sendable, Equatable {
    /// Number of frames in the median filter. Odd values keep the window centred.
    public var medianWindow: Int
    /// How long a reading is held after the string decays below the gate.
    public var holdDuration: TimeInterval
    /// A jump larger than this many cents clears the median window instead of
    /// dragging the needle across the scale when the player switches strings.
    public var resetThresholdCents: Double

    public init(
        medianWindow: Int = 5,
        holdDuration: TimeInterval = 1.5,
        resetThresholdCents: Double = 250
    ) {
        self.medianWindow = max(1, medianWindow | 1)
        self.holdDuration = holdDuration
        self.resetThresholdCents = resetThresholdCents
    }

    public static let `default` = PitchStabilizerConfiguration()
}

/// Median-filters the raw detector output and holds the last stable reading briefly so
/// a decaying string does not make the needle snap back to centre.
public struct PitchStabilizer: Sendable {
    public var configuration: PitchStabilizerConfiguration
    private var history: [Double] = []
    private var lastFrequency: Double?
    private var lastUpdate: TimeInterval?

    public init(configuration: PitchStabilizerConfiguration = .default) {
        self.configuration = configuration
    }

    public var lastStableFrequency: Double? { lastFrequency }

    /// True while a note is being tracked or held — the pipeline uses this to switch the
    /// detector to its lower `retentionClarity` threshold.
    public var isTracking: Bool { lastFrequency != nil }

    public mutating func process(_ analysis: PitchAnalysis, at time: TimeInterval) -> StabilizedPitch {
        guard let frequency = analysis.frequency else {
            return holdOrClear(analysis: analysis, at: time)
        }

        if let last = lastFrequency,
           abs(NoteMath.cents(from: frequency, to: last)) > configuration.resetThresholdCents {
            history.removeAll(keepingCapacity: true)
        }

        history.append(frequency)
        if history.count > configuration.medianWindow {
            history.removeFirst(history.count - configuration.medianWindow)
        }

        lastFrequency = frequency
        lastUpdate = time

        return StabilizedPitch(
            frequency: median(of: history),
            rawFrequency: frequency,
            clarity: analysis.clarity,
            analysis: analysis,
            isHeld: false
        )
    }

    public mutating func reset() {
        history.removeAll(keepingCapacity: true)
        lastFrequency = nil
        lastUpdate = nil
    }

    private mutating func holdOrClear(analysis: PitchAnalysis, at time: TimeInterval) -> StabilizedPitch {
        let held: Double? = {
            guard let lastFrequency, let lastUpdate else { return nil }
            guard time - lastUpdate <= configuration.holdDuration else { return nil }
            // Gated frames (below RMS) still hold; unclear frames hold for half as long.
            if analysis.isGated { return lastFrequency }
            return time - lastUpdate <= configuration.holdDuration / 2 ? lastFrequency : nil
        }()

        if held == nil {
            history.removeAll(keepingCapacity: true)
            lastFrequency = nil
            lastUpdate = nil
        }

        return StabilizedPitch(
            frequency: held,
            rawFrequency: analysis.frequency,
            clarity: held == nil ? 0 : analysis.clarity,
            analysis: analysis,
            isHeld: held != nil
        )
    }

    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// Output of the stabiliser, before it is matched against a tuning preset.
public struct StabilizedPitch: Sendable, Equatable {
    public var frequency: Double?
    public var rawFrequency: Double?
    public var clarity: Double
    public var analysis: PitchAnalysis
    public var isHeld: Bool

    public init(
        frequency: Double?,
        rawFrequency: Double?,
        clarity: Double,
        analysis: PitchAnalysis,
        isHeld: Bool
    ) {
        self.frequency = frequency
        self.rawFrequency = rawFrequency
        self.clarity = clarity
        self.analysis = analysis
        self.isHeld = isHeld
    }
}
