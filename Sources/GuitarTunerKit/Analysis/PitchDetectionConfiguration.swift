import Foundation

/// Tunables for the autocorrelation (NSDF / MPM) pitch detector.
public struct PitchDetectionConfiguration: Sendable, Equatable {
    /// Lowest fundamental the detector will report. 55 Hz covers drop tunings on bass.
    public var minFrequency: Double
    /// Highest fundamental the detector will report. Above this the input is treated
    /// as noise, which keeps pick squeal from dragging the needle around.
    public var maxFrequency: Double
    /// Analysis window in samples. 4096 @ 48 kHz is ~85 ms, i.e. ~7 cycles of low E.
    public var analysisWindowSize: Int
    /// Absolute RMS gate, used before the adaptive noise floor has settled.
    public var minimumRMS: Double
    /// Fraction of the best NSDF peak required to accept a lag as periodic.
    public var peakSelectionRatio: Double
    /// Minimum NSDF value at the chosen lag; below this the frame is "unclear".
    public var minimumClarity: Double
    /// Lower threshold used *while already tracking* the same note. Starting a reading
    /// needs `minimumClarity`, keeping one needs only this, so a decaying string stays on
    /// the dial instead of vanishing the moment its clarity dips.
    public var retentionClarity: Double
    /// Below this many samples the detector refuses to run.
    public var minimumSampleCount: Int

    public init(
        minFrequency: Double = 55,
        maxFrequency: Double = 1400,
        analysisWindowSize: Int = 4096,
        minimumRMS: Double = 0.0035,
        peakSelectionRatio: Double = 0.85,
        minimumClarity: Double = 0.5,
        retentionClarity: Double = 0.3,
        minimumSampleCount: Int = 512
    ) {
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.analysisWindowSize = analysisWindowSize
        self.minimumRMS = minimumRMS
        self.peakSelectionRatio = peakSelectionRatio
        self.minimumClarity = minimumClarity
        self.retentionClarity = retentionClarity
        self.minimumSampleCount = minimumSampleCount
    }

    public static let `default` = PitchDetectionConfiguration()
}

/// One frame of analysis: level information is always produced, a frequency only when
/// the frame is both loud enough and periodic enough.
public struct PitchAnalysis: Sendable, Equatable {
    /// RMS of the analysed window.
    public var rms: Double
    /// RMS mapped to a 0...1 meter value.
    public var level: Double
    /// RMS gate that was applied to this frame.
    public var gate: Double
    /// Estimated fundamental, `nil` when gated or when no clear period was found.
    public var frequency: Double?
    /// Normalised autocorrelation peak height (0...1) at the chosen lag.
    public var clarity: Double
    /// Chosen lag in samples (fractional after parabolic interpolation).
    public var lag: Double?
    /// True when the frame was rejected purely because it sat under the RMS gate.
    public var isGated: Bool

    public init(
        rms: Double = 0,
        level: Double = 0,
        gate: Double = 0,
        frequency: Double? = nil,
        clarity: Double = 0,
        lag: Double? = nil,
        isGated: Bool = false
    ) {
        self.rms = rms
        self.level = level
        self.gate = gate
        self.frequency = frequency
        self.clarity = clarity
        self.lag = lag
        self.isGated = isGated
    }

    public static let silent = PitchAnalysis()
}
