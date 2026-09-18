import Foundation

/// How the signal reaches the tuner. The two modes exist because a microphone hears
/// the room while a pickup hears the instrument directly, and those two signals need
/// opposite treatment before pitch detection.
public enum AudioInputMode: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Built-in / external microphone: band-pass the input to reject rumble, HVAC noise
    /// and speech, keeping roughly 70 Hz - 1 kHz.
    case microphone
    /// Instrument cable or clip-on pickup: low-pass the input so the very strong upper
    /// harmonics of a plucked string cannot out-vote the fundamental.
    case pickup

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .pickup: "Pickup"
        }
    }

    public var summary: String {
        switch self {
        case .microphone: "Room noise rejected with a 70 Hz – 1 kHz band-pass."
        case .pickup: "Upper harmonics tamed with a low-pass so the fundamental wins."
        }
    }

    public var symbolName: String {
        switch self {
        case .microphone: "mic.fill"
        case .pickup: "cable.connector"
        }
    }

    /// Baseline filter settings. `AnalysisProfile` widens these when the selected
    /// tuning would otherwise sit outside the pass-band (low bass, high ukulele…).
    public var filter: FilterConfiguration {
        switch self {
        case .microphone:
            FilterConfiguration(highPassFrequency: 70, lowPassFrequency: 1000)
        case .pickup:
            FilterConfiguration(highPassFrequency: 60, lowPassFrequency: 400)
        }
    }

    public struct FilterConfiguration: Sendable, Equatable {
        public var highPassFrequency: Double?
        public var lowPassFrequency: Double?
        /// Bandwidth in octaves for the AVAudioUnitEQ bands.
        public var bandwidth: Double

        public init(highPassFrequency: Double?, lowPassFrequency: Double?, bandwidth: Double = 0.7) {
            self.highPassFrequency = highPassFrequency
            self.lowPassFrequency = lowPassFrequency
            self.bandwidth = bandwidth
        }
    }
}

/// The concrete filter + detector settings derived from the input mode and the
/// currently selected tuning.
///
/// Keeping this in the kit (instead of inside the view) means the DSP behaviour is
/// unit-testable without touching AVFoundation.
public struct AnalysisProfile: Sendable, Equatable {
    public var highPassFrequency: Double?
    public var lowPassFrequency: Double?
    public var filterBandwidth: Double
    public var minFrequency: Double
    public var maxFrequency: Double

    public init(
        highPassFrequency: Double?,
        lowPassFrequency: Double?,
        filterBandwidth: Double = 0.7,
        minFrequency: Double,
        maxFrequency: Double
    ) {
        self.highPassFrequency = highPassFrequency
        self.lowPassFrequency = lowPassFrequency
        self.filterBandwidth = filterBandwidth
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
    }

    /// Lowest fundamental the detector has to cover. An 8-string in F♯ standard sits at
    /// 23 Hz, and the window sizing in the pipeline follows this down.
    public static let absoluteMinFrequency = 20.0
    /// Highest fundamental the detector will report.
    public static let absoluteMaxFrequency = 1600.0

    public static func make(inputMode: AudioInputMode, selection: TuningSelection) -> AnalysisProfile {
        let baseFilter = inputMode.filter
        let range = selection.preset.frequencyRange(referencePitch: selection.referencePitch)

        // Detector search range. A little headroom below the lowest string keeps
        // slightly flat strings inside the range; the top end leaves room for the
        // harmonics the pickup delivers.
        var minFrequency = 55.0
        var maxFrequency = 1400.0
        if let range {
            minFrequency = max(Self.absoluteMinFrequency, min(minFrequency, range.lowerBound * 0.7))
            maxFrequency = min(Self.absoluteMaxFrequency, max(1000, range.upperBound * 4))
        }

        var highPass = baseFilter.highPassFrequency
        var lowPass = baseFilter.lowPassFrequency

        if let range {
            // Never high-pass away the fundamental of the lowest string.
            if let configured = highPass {
                highPass = min(configured, max(range.lowerBound * 0.75, 25))
            }
            // Never low-pass away the fundamental of the highest string; the pickup
            // mode cutoff opens up for ukulele / high tunings.
            if let configured = lowPass {
                let ceiling = inputMode == .pickup ? 1200.0 : 1400.0
                lowPass = min(max(configured, range.upperBound * 1.25), ceiling)
            }
        }

        return AnalysisProfile(
            highPassFrequency: highPass,
            lowPassFrequency: lowPass,
            filterBandwidth: baseFilter.bandwidth,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency
        )
    }
}
