import Foundation

/// Which target the tuner compares against.
public enum StringSelection: Sendable, Equatable, Hashable {
    /// Track whichever string / semitone is closest to the measured pitch.
    case automatic
    /// Lock onto one string of the preset (`InstrumentString.id`).
    case locked(Int)

    public var lockedStringID: Int? {
        if case let .locked(id) = self { return id }
        return nil
    }
}

/// Everything the analysis needs to know about the player's intent.
public struct TuningSelection: Sendable, Equatable {
    public var preset: TuningPreset
    public var referencePitch: Double
    public var stringSelection: StringSelection
    /// Capo position in frets: every target string moves up by this much.
    public var capoFret: Int
    /// Cents window that counts as "in tune".
    public var inTuneToleranceCents: Double
    /// Clarity below which a reading never counts as in tune.
    public var minimumClarityForInTune: Double

    public init(
        preset: TuningPreset = .standardGuitar,
        referencePitch: Double = NoteMath.defaultReferencePitch,
        stringSelection: StringSelection = .automatic,
        capoFret: Int = 0,
        inTuneToleranceCents: Double = 5,
        minimumClarityForInTune: Double = 0.55
    ) {
        self.preset = preset
        self.referencePitch = referencePitch
        self.stringSelection = stringSelection
        self.capoFret = min(max(capoFret, 0), TuningPreset.maximumCapoFret)
        self.inTuneToleranceCents = inTuneToleranceCents
        self.minimumClarityForInTune = minimumClarityForInTune
    }

    public static let `default` = TuningSelection()
}

/// The pitch a reading is being compared against — either a preset string or the
/// nearest semitone in chromatic mode.
public struct PitchTarget: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case string(InstrumentString)
        case chromatic
    }

    public var id: String
    public var kind: Kind
    public var note: Note
    public var frequency: Double
    /// e.g. `E2 · 6th string`.
    public var detailedLabel: String

    public init(id: String, kind: Kind, note: Note, frequency: Double, detailedLabel: String) {
        self.id = id
        self.kind = kind
        self.note = note
        self.frequency = frequency
        self.detailedLabel = detailedLabel
    }

    public var noteName: String { note.description() }
}

/// One frame of finished tuner output, ready for the UI.
public struct TunerReading: Sendable, Equatable {
    /// Smoothed frequency, `nil` when nothing usable is coming in.
    public var frequency: Double?
    /// Pre-smoothing frequency of the current frame.
    public var rawFrequency: Double?
    /// Autocorrelation peak height of the current frame (0...1).
    public var clarity: Double
    /// Input level mapped to 0...1 for the level meter.
    public var level: Double
    public var rms: Double
    public var gate: Double
    public var note: Note?
    /// Signed cents from `frequency` to `target.frequency`.
    public var cents: Double?
    public var target: PitchTarget?
    public var isInTune: Bool
    /// True while the value is being held after the string decayed.
    public var isHeld: Bool
    public var timestamp: TimeInterval

    public init(
        frequency: Double? = nil,
        rawFrequency: Double? = nil,
        clarity: Double = 0,
        level: Double = 0,
        rms: Double = 0,
        gate: Double = 0,
        note: Note? = nil,
        cents: Double? = nil,
        target: PitchTarget? = nil,
        isInTune: Bool = false,
        isHeld: Bool = false,
        timestamp: TimeInterval = 0
    ) {
        self.frequency = frequency
        self.rawFrequency = rawFrequency
        self.clarity = clarity
        self.level = level
        self.rms = rms
        self.gate = gate
        self.note = note
        self.cents = cents
        self.target = target
        self.isInTune = isInTune
        self.isHeld = isHeld
        self.timestamp = timestamp
    }

    public static let idle = TunerReading()

    public var isSignalPresent: Bool { frequency != nil }

    /// Signed cents clamped to the gauge range.
    public func needleCents(limit: Double = 50) -> Double {
        guard let cents else { return 0 }
        return min(max(cents, -limit), limit)
    }

    public enum Direction: Sendable, Equatable {
        case flat, sharp, inTune, idle
    }

    public var direction: Direction {
        guard let cents else { return .idle }
        if isInTune { return .inTune }
        return cents < 0 ? .flat : .sharp
    }
}
