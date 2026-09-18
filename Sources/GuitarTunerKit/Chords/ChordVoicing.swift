import Foundation

/// One playable shape: which fret each string is pressed at (or muted).
public struct ChordVoicing: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let root: NoteName
    public let quality: ChordQuality
    /// Open-string notes of the instrument, lowest string first — same order as the
    /// tuner's `TuningPreset.strings`.
    public let tuning: TuningPreset
    /// Fret per string in tuning order; `nil` means the string is not played.
    public let frets: [Int?]
    /// First fret shown by the diagram, for shapes that live up the neck.
    public let baseFret: Int

    public init(
        id: String,
        root: NoteName,
        quality: ChordQuality,
        tuning: TuningPreset = .standardGuitar,
        frets: [Int?],
        baseFret: Int = 1
    ) {
        self.id = id
        self.root = root
        self.quality = quality
        self.tuning = tuning
        self.frets = frets
        self.baseFret = baseFret
    }

    /// e.g. `Cmaj7`, `F♯m`.
    public var name: String { root.sharpName + quality.symbol }

    public var detailedName: String { "\(name) · \(quality.displayName)" }

    /// Notes this shape sounds, lowest string first; muted strings are dropped.
    public var notes: [Note] {
        zip(tuning.strings, frets).compactMap { string, fret in
            guard let fret else { return nil }
            return Note(midiNumber: string.midiNumber + fret)
        }
    }

    /// Pitch classes the shape can produce, ignoring octaves and doublings.
    public var pitchClasses: Set<Int> {
        Set(notes.map { (($0.midiNumber % 12) + 12) % 12 })
    }

    /// Pitch classes the *chord* implies, whether or not this particular shape uses them.
    public var chordPitchClasses: Set<Int> {
        quality.pitchClasses(abovePitchClass: root.rawValue)
    }

    /// Does the shape sound every tone that *defines* the quality — root, third, seventh,
    /// sixth, ninth, sus…? The perfect fifth is allowed to be missing, which is standard
    /// practice for guitar voicings (open C6 and open C7 both omit it).
    public var hasAllDefiningTones: Bool {
        let defining = quality.intervals
            .filter { $0 % 12 != 7 }
            .map { ((root.rawValue + $0) % 12 + 12) % 12 }
        return Set(defining).isSubset(of: pitchClasses)
    }

    /// Highest fret used, for diagram layout.
    public var highestFret: Int {
        frets.compactMap { $0 }.max() ?? 0
    }

    /// Number of strings actually played.
    public var soundingStringCount: Int {
        frets.compactMap { $0 }.count
    }

    public func note(forStringIndex index: Int) -> Note? {
        guard index >= 0, index < min(tuning.strings.count, frets.count),
              let fret = frets[index] else { return nil }
        return Note(midiNumber: tuning.strings[index].midiNumber + fret)
    }
}
