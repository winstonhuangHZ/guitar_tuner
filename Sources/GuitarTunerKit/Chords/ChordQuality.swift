import Foundation

/// Chord qualities the detector can name, expressed as semitone intervals from the root.
///
/// The list is deliberately the set of qualities you actually play on a guitar rather
/// than every theoretical chord: adding a quality that no voicing can produce only gives
/// the detector more ways to be wrong.
public enum ChordQuality: String, CaseIterable, Sendable, Codable, Identifiable {
    case major
    case minor
    case diminished
    case augmented
    case sus2
    case sus4
    case power
    case six
    case minorSix
    case dominantSeventh
    case majorSeventh
    case minorSeventh
    case halfDiminished
    case addNine
    case minorMajorSeventh
    case ninth

    public var id: String { rawValue }

    /// Semitones above the root.
    public var intervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        case .sus2: [0, 2, 7]
        case .sus4: [0, 5, 7]
        case .power: [0, 7]
        case .six: [0, 4, 7, 9]
        case .minorSix: [0, 3, 7, 9]
        case .dominantSeventh: [0, 4, 7, 10]
        case .majorSeventh: [0, 4, 7, 11]
        case .minorSeventh: [0, 3, 7, 10]
        case .halfDiminished: [0, 3, 6, 10]
        case .addNine: [0, 4, 7, 14]
        case .minorMajorSeventh: [0, 3, 7, 11]
        case .ninth: [0, 4, 7, 10, 14]
        }
    }

    /// Chord-symbol suffix, e.g. `m7`.
    public var symbol: String {
        switch self {
        case .major: ""
        case .minor: "m"
        case .diminished: "dim"
        case .augmented: "aug"
        case .sus2: "sus2"
        case .sus4: "sus4"
        case .power: "5"
        case .six: "6"
        case .minorSix: "m6"
        case .dominantSeventh: "7"
        case .majorSeventh: "maj7"
        case .minorSeventh: "m7"
        case .halfDiminished: "m7♭5"
        case .addNine: "add9"
        case .minorMajorSeventh: "m(maj7)"
        case .ninth: "9"
        }
    }

    public var displayName: String {
        switch self {
        case .major: "Major"
        case .minor: "Minor"
        case .diminished: "Diminished"
        case .augmented: "Augmented"
        case .sus2: "Suspended 2nd"
        case .sus4: "Suspended 4th"
        case .power: "Power chord"
        case .six: "Major 6th"
        case .minorSix: "Minor 6th"
        case .dominantSeventh: "Dominant 7th"
        case .majorSeventh: "Major 7th"
        case .minorSeventh: "Minor 7th"
        case .halfDiminished: "Half diminished"
        case .addNine: "Added 9th"
        case .minorMajorSeventh: "Minor major 7th"
        case .ninth: "Dominant 9th"
        }
    }

    /// Pitch classes above the root, folded into 0...11.
    public func pitchClasses(abovePitchClass root: Int) -> Set<Int> {
        Set(intervals.map { ((root + $0) % 12 + 12) % 12 })
    }

    /// How many distinct pitch classes the template expects.
    public var pitchClassCount: Int { Set(intervals.map { $0 % 12 }).count }
}
