import Foundation

/// Everything the app remembers between launches.
public struct TunerSettings: Sendable, Equatable, Codable {
    public var inputMode: AudioInputMode
    public var presetID: String
    public var referencePitch: Double
    public var inTuneToleranceCents: Double
    /// Capo position in frets; every target moves up with it.
    public var capoFret: Int
    /// Locked string index, `nil` for automatic target tracking.
    public var lockedStringID: Int?
    public var inputDeviceID: String?
    public var metronomePatternID: String
    public var metronomeTempo: Double
    public var metronomeAccentsEnabled: Bool
    public var metronomeVolume: Double
    public var practiceVoicingID: String?
    public var progressionID: String?
    /// Key the progression is played in.
    public var progressionKeyID: String
    public var recordsTuningHistory: Bool

    public init(
        inputMode: AudioInputMode = .microphone,
        presetID: String = TuningPreset.standardGuitar.id,
        referencePitch: Double = NoteMath.defaultReferencePitch,
        inTuneToleranceCents: Double = 5,
        capoFret: Int = 0,
        lockedStringID: Int? = nil,
        inputDeviceID: String? = nil,
        metronomePatternID: String = MetronomePattern.commonTime.id,
        metronomeTempo: Double = 90,
        metronomeAccentsEnabled: Bool = true,
        metronomeVolume: Double = 0.7,
        practiceVoicingID: String? = "C",
        progressionID: String? = ProgressionTemplate.twelveBarBlues.id,
        progressionKeyID: String = ProgressionKey.cMajor.id,
        recordsTuningHistory: Bool = true
    ) {
        self.inputMode = inputMode
        self.presetID = presetID
        self.referencePitch = referencePitch
        self.inTuneToleranceCents = inTuneToleranceCents
        self.capoFret = capoFret
        self.lockedStringID = lockedStringID
        self.inputDeviceID = inputDeviceID
        self.metronomePatternID = metronomePatternID
        self.metronomeTempo = metronomeTempo
        self.metronomeAccentsEnabled = metronomeAccentsEnabled
        self.metronomeVolume = metronomeVolume
        self.practiceVoicingID = practiceVoicingID
        self.progressionID = progressionID
        self.progressionKeyID = progressionKeyID
        self.recordsTuningHistory = recordsTuningHistory
    }

    /// Settings that apply when nothing has been saved yet.
    public static let `default` = TunerSettings()

    /// The stored preset, falling back to standard tuning if the library changed.
    public var preset: TuningPreset {
        TuningPreset.preset(id: presetID) ?? .standardGuitar
    }

    public var stringSelection: StringSelection {
        lockedStringID.map { StringSelection.locked($0) } ?? .automatic
    }

    /// Clamps anything that came from disk, an older version, or a hand-edited file.
    public func sanitized() -> TunerSettings {
        var copy = self
        copy.referencePitch = min(max(referencePitch, 415), 466)
        copy.inTuneToleranceCents = min(max(inTuneToleranceCents, 1), 25)
        copy.capoFret = min(max(capoFret, 0), TuningPreset.maximumCapoFret)
        copy.metronomeTempo = min(max(metronomeTempo, MetronomePattern.minimumTempo), MetronomePattern.maximumTempo)
        copy.metronomeVolume = min(max(metronomeVolume, 0), 1)
        if MetronomePattern.pattern(id: metronomePatternID) == nil {
            copy.metronomePatternID = MetronomePattern.commonTime.id
        }
        if let id = progressionID, ProgressionTemplate.template(id: id) == nil {
            copy.progressionID = ProgressionTemplate.all.first?.id
        }
        if ProgressionKey.key(id: progressionKeyID) == nil {
            copy.progressionKeyID = ProgressionKey.cMajor.id
        }
        if let id = practiceVoicingID, ChordLibrary.voicing(id: id) == nil {
            copy.practiceVoicingID = ChordLibrary.guitar.first?.id
        }
        if let id = lockedStringID, !copy.preset.strings.indices.contains(id) {
            copy.lockedStringID = nil
        }
        return copy
    }
}

/// Small JSON wrapper over `UserDefaults`. The defaults are injectable so checks can use a
/// scratch suite instead of the real one.
public struct SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "guitarTuner.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TunerSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(TunerSettings.self, from: data) else {
            return .default
        }
        return decoded.sanitized()
    }

    public func save(_ settings: TunerSettings) {
        guard let data = try? JSONEncoder().encode(settings.sanitized()) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
