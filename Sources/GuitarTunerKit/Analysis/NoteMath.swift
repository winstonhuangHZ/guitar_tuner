import Foundation

/// The twelve equal-tempered pitch classes, spelled with sharps by default.
public enum NoteName: Int, CaseIterable, Sendable, Codable {
    case c = 0
    case cSharp = 1
    case d = 2
    case dSharp = 3
    case e = 4
    case f = 5
    case fSharp = 6
    case g = 7
    case gSharp = 8
    case a = 9
    case aSharp = 10
    case b = 11

    public var sharpName: String {
        switch self {
        case .c: "C"
        case .cSharp: "C♯"
        case .d: "D"
        case .dSharp: "D♯"
        case .e: "E"
        case .f: "F"
        case .fSharp: "F♯"
        case .g: "G"
        case .gSharp: "G♯"
        case .a: "A"
        case .aSharp: "A♯"
        case .b: "B"
        }
    }

    public var flatName: String {
        switch self {
        case .c: "C"
        case .cSharp: "D♭"
        case .d: "D"
        case .dSharp: "E♭"
        case .e: "E"
        case .f: "F"
        case .fSharp: "G♭"
        case .g: "G"
        case .gSharp: "A♭"
        case .a: "A"
        case .aSharp: "B♭"
        case .b: "B"
        }
    }
}

public enum AccidentalStyle: Sendable, Codable {
    case sharp
    case flat
}

/// A pitch in scientific pitch notation (`A4` = MIDI 69 = 440 Hz by default).
public struct Note: Hashable, Sendable, Codable, Identifiable {
    public let midiNumber: Int

    public init(midiNumber: Int) {
        self.midiNumber = midiNumber
    }

    public var id: Int { midiNumber }

    public var name: NoteName {
        let index = ((midiNumber % 12) + 12) % 12
        return NoteName(rawValue: index) ?? .c
    }

    /// Octave number in scientific pitch notation; MIDI 0 is `C-1`.
    public var octave: Int {
        Int(floor(Double(midiNumber) / 12.0)) - 1
    }

    public func description(style: AccidentalStyle = .sharp) -> String {
        let symbol = style == .sharp ? name.sharpName : name.flatName
        return "\(symbol)\(octave)"
    }
}

/// Conversions between frequency, MIDI note numbers and cents.
public enum NoteMath {
    public static let semitonesPerOctave = 12.0
    public static let midiNumberForA4 = 69
    public static let defaultReferencePitch = 440.0

    /// Frequency of a (possibly fractional) MIDI note number.
    public static func frequency(midiNumber: Double, referencePitch: Double = defaultReferencePitch) -> Double {
        guard referencePitch > 0, midiNumber.isFinite else { return 0 }
        return referencePitch * pow(2.0, (midiNumber - Double(midiNumberForA4)) / semitonesPerOctave)
    }

    public static func frequency(of note: Note, referencePitch: Double = defaultReferencePitch) -> Double {
        frequency(midiNumber: Double(note.midiNumber), referencePitch: referencePitch)
    }

    /// Fractional MIDI note number for a frequency. `nil` for non-positive input.
    public static func midiNumber(forFrequency frequency: Double, referencePitch: Double = defaultReferencePitch) -> Double? {
        guard frequency > 0, frequency.isFinite, referencePitch > 0 else { return nil }
        return Double(midiNumberForA4) + semitonesPerOctave * log2(frequency / referencePitch)
    }

    /// Signed distance in cents from `frequency` to `target` (positive = sharper than target).
    public static func cents(from frequency: Double, to target: Double) -> Double {
        guard frequency > 0, target > 0 else { return 0 }
        return 1200.0 * log2(frequency / target)
    }

    /// Nearest equal-tempered note and the deviation from it.
    public static func nearestNote(
        forFrequency frequency: Double,
        referencePitch: Double = defaultReferencePitch
    ) -> (note: Note, cents: Double)? {
        guard let exact = midiNumber(forFrequency: frequency, referencePitch: referencePitch) else { return nil }
        let rounded = exact.rounded()
        let note = Note(midiNumber: Int(rounded))
        let cents = (exact - rounded) * 100.0
        return (note, cents)
    }

    /// The note whose pitch is `cents` away from `note` — used to label target strings.
    public static func detuned(_ cents: Double, from note: Note, referencePitch: Double = defaultReferencePitch) -> Double {
        frequency(of: note, referencePitch: referencePitch) * pow(2.0, cents / 1200.0)
    }
}
