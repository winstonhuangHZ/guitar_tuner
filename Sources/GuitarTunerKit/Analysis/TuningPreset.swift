import Foundation

/// One string (or one chromatic pitch) that the tuner can lock onto.
public struct InstrumentString: Hashable, Sendable, Codable, Identifiable {
    /// Position inside its preset, `0` = lowest pitched string.
    public let id: Int
    public let midiNumber: Int
    /// Human label such as "6th string"; empty for chromatic entries.
    public let label: String

    public init(id: Int, midiNumber: Int, label: String = "") {
        self.id = id
        self.midiNumber = midiNumber
        self.label = label
    }

    public var note: Note { Note(midiNumber: midiNumber) }

    /// Short name, e.g. `E2`.
    public var noteName: String { note.description() }

    /// e.g. `E2 · 6th string`.
    public var detailedName: String {
        label.isEmpty ? noteName : "\(noteName) · \(label)"
    }

    public func frequency(referencePitch: Double = NoteMath.defaultReferencePitch) -> Double {
        NoteMath.frequency(of: note, referencePitch: referencePitch)
    }

    /// Signed cents between a measured frequency and this string.
    public func centsDeviation(
        for frequency: Double,
        referencePitch: Double = NoteMath.defaultReferencePitch
    ) -> Double {
        NoteMath.cents(from: frequency, to: self.frequency(referencePitch: referencePitch))
    }
}

/// A named tuning: an ordered list of target strings, or a chromatic preset.
public struct TuningPreset: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let instrument: String
    public let strings: [InstrumentString]

    public init(id: String, name: String, instrument: String, strings: [InstrumentString]) {
        self.id = id
        self.name = name
        self.instrument = instrument
        // Presets are defined low string -> high string; keep indexing stable.
        self.strings = strings.enumerated().map { index, string in
            InstrumentString(id: index, midiNumber: string.midiNumber, label: string.label)
        }
    }

    /// Chromatic presets have no fixed strings: the tuner tracks the nearest semitone.
    public var isChromatic: Bool { strings.isEmpty }

    public func string(id: Int?) -> InstrumentString? {
        guard let id else { return nil }
        return strings.first { $0.id == id }
    }

    /// Lowest / highest target frequency, used to bound the pitch search range.
    public func frequencyRange(referencePitch: Double = NoteMath.defaultReferencePitch) -> ClosedRange<Double>? {
        guard let lowest = strings.first, let highest = strings.last else { return nil }
        return lowest.frequency(referencePitch: referencePitch)...highest.frequency(referencePitch: referencePitch)
    }
}

// MARK: - Built-in presets

public extension TuningPreset {
    static let chromatic = TuningPreset(
        id: "chromatic",
        name: "Chromatic",
        instrument: "General",
        strings: []
    )

    static let standardGuitar = TuningPreset(
        id: "guitar-standard",
        name: "Standard E",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 40, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 45, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 50, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 55, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 59, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 64, label: "1st string"),
        ]
    )

    static let dropD = TuningPreset(
        id: "guitar-drop-d",
        name: "Drop D",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 38, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 45, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 50, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 55, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 59, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 64, label: "1st string"),
        ]
    )

    static let halfStepDown = TuningPreset(
        id: "guitar-eb-standard",
        name: "E♭ Standard",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 39, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 44, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 49, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 54, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 58, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 63, label: "1st string"),
        ]
    )

    static let openG = TuningPreset(
        id: "guitar-open-g",
        name: "Open G",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 38, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 43, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 50, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 55, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 59, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 62, label: "1st string"),
        ]
    )

    static let openD = TuningPreset(
        id: "guitar-open-d",
        name: "Open D",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 38, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 45, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 50, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 54, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 57, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 62, label: "1st string"),
        ]
    )

    static let dadgad = TuningPreset(
        id: "guitar-dadgad",
        name: "DADGAD",
        instrument: "Guitar",
        strings: [
            InstrumentString(id: 0, midiNumber: 38, label: "6th string"),
            InstrumentString(id: 0, midiNumber: 45, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 50, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 55, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 57, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 62, label: "1st string"),
        ]
    )

    static let bassFourString = TuningPreset(
        id: "bass-4",
        name: "Bass 4-string",
        instrument: "Bass",
        strings: [
            InstrumentString(id: 0, midiNumber: 28, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 33, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 38, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 43, label: "1st string"),
        ]
    )

    static let bassFiveString = TuningPreset(
        id: "bass-5",
        name: "Bass 5-string",
        instrument: "Bass",
        strings: [
            InstrumentString(id: 0, midiNumber: 23, label: "5th string"),
            InstrumentString(id: 0, midiNumber: 28, label: "4th string"),
            InstrumentString(id: 0, midiNumber: 33, label: "3rd string"),
            InstrumentString(id: 0, midiNumber: 38, label: "2nd string"),
            InstrumentString(id: 0, midiNumber: 43, label: "1st string"),
        ]
    )

    static let ukulele = TuningPreset(
        id: "ukulele-standard",
        name: "Ukulele C",
        instrument: "Ukulele",
        strings: [
            InstrumentString(id: 0, midiNumber: 67, label: "G string"),
            InstrumentString(id: 0, midiNumber: 60, label: "C string"),
            InstrumentString(id: 0, midiNumber: 64, label: "E string"),
            InstrumentString(id: 0, midiNumber: 69, label: "A string"),
        ]
    )

    /// Everything offered in the preset picker, grouped by instrument.
    static let all: [TuningPreset] = [
        .chromatic,
        .standardGuitar,
        .dropD,
        .halfStepDown,
        .openG,
        .openD,
        .dadgad,
        .bassFourString,
        .bassFiveString,
        .ukulele,
    ]

    static let groups: [(instrument: String, presets: [TuningPreset])] = {
        var order: [String] = []
        var buckets: [String: [TuningPreset]] = [:]
        for preset in all {
            if buckets[preset.instrument] == nil {
                order.append(preset.instrument)
                buckets[preset.instrument] = []
            }
            buckets[preset.instrument]?.append(preset)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }()

    static func preset(id: String) -> TuningPreset? {
        all.first { $0.id == id }
    }
}
