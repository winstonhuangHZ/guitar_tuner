import Foundation

/// One string (or one chromatic pitch) that the tuner can lock onto.
public struct InstrumentString: Hashable, Sendable, Codable, Identifiable {
    /// Position inside its preset, `0` = first entry of the preset.
    public let id: Int
    public let midiNumber: Int
    /// Human label such as "6th string"; empty for chromatic entries.
    public let label: String

    public init(id: Int = 0, midiNumber: Int, label: String = "") {
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
        // Re-index so `InstrumentString.id` always addresses the string inside this preset.
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

    /// Lowest / highest target frequency. Computed from the actual targets rather than
    /// assuming order — re-entrant tunings (ukulele, 5-string banjo, Nashville) are not
    /// sorted by pitch.
    public func frequencyRange(referencePitch: Double = NoteMath.defaultReferencePitch) -> ClosedRange<Double>? {
        let frequencies = strings
            .map { $0.frequency(referencePitch: referencePitch) }
            .filter { $0 > 0 }
        guard let lowest = frequencies.min(), let highest = frequencies.max() else { return nil }
        return lowest...highest
    }

    /// e.g. `E2 · A2 · D3 · G3 · B3 · E4`.
    public var noteSummary: String {
        strings.map(\.noteName).joined(separator: " · ")
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

    // MARK: Guitar — standard and drop tunings

    static let standardGuitar = guitar("guitar-standard", "Standard E", [40, 45, 50, 55, 59, 64])
    static let dropD = guitar("guitar-drop-d", "Drop D", [38, 45, 50, 55, 59, 64])
    static let doubleDropD = guitar("guitar-double-drop-d", "Double Drop D", [38, 45, 50, 55, 59, 62])
    static let dropCSharp = guitar("guitar-drop-c-sharp", "Drop C♯", [37, 44, 49, 54, 58, 63])
    static let dropC = guitar("guitar-drop-c", "Drop C", [36, 43, 48, 53, 57, 62])
    static let dropB = guitar("guitar-drop-b", "Drop B", [35, 42, 47, 52, 56, 61])
    static let dropA = guitar("guitar-drop-a", "Drop A", [33, 40, 45, 50, 54, 59])

    // MARK: Guitar — open and altered tunings

    static let openD = guitar("guitar-open-d", "Open D", [38, 45, 50, 54, 57, 62])
    static let openG = guitar("guitar-open-g", "Open G", [38, 43, 50, 55, 59, 62])
    static let openE = guitar("guitar-open-e", "Open E", [40, 47, 52, 56, 59, 64])
    static let openA = guitar("guitar-open-a", "Open A", [40, 45, 49, 52, 57, 61])
    static let openC = guitar("guitar-open-c", "Open C", [36, 43, 48, 55, 60, 64])
    static let dadgad = guitar("guitar-dadgad", "DADGAD", [38, 45, 50, 55, 57, 62])
    static let daddad = guitar("guitar-daddad", "DADDAD", [38, 45, 50, 50, 57, 62])
    static let allFourths = guitar("guitar-all-fourths", "All Fourths", [40, 45, 50, 55, 60, 65])
    static let nashville = guitar("guitar-nashville", "Nashville (high-strung)", [52, 57, 62, 55, 59, 64])

    // MARK: Guitar — transposed down

    static let halfStepDown = guitar("guitar-eb-standard", "E♭ Standard (½ step down)", [39, 44, 49, 54, 58, 63])
    static let dStandard = guitar("guitar-d-standard", "D Standard (whole step down)", [38, 43, 48, 53, 57, 62])
    static let cStandard = guitar("guitar-c-standard", "C Standard", [36, 41, 46, 51, 55, 60])
    static let baritoneB = guitar("guitar-baritone-b", "Baritone (B standard)", [35, 40, 45, 50, 54, 59])

    // MARK: Extended range

    static let sevenStringStandard = numbered("guitar-7-string-b", "7-string B Standard", [35, 40, 45, 50, 55, 59, 64], lowestPosition: 7, instrument: "Extended range")
    static let sevenStringDropA = numbered("guitar-7-string-drop-a", "7-string Drop A", [33, 40, 45, 50, 55, 59, 64], lowestPosition: 7, instrument: "Extended range")
    static let eightStringStandard = numbered("guitar-8-string-f-sharp", "8-string F♯ Standard", [30, 35, 40, 45, 50, 55, 59, 64], lowestPosition: 8, instrument: "Extended range")

    // MARK: Bass

    static let bassFourString = numbered("bass-4", "Bass 4-string", [28, 33, 38, 43], lowestPosition: 4, instrument: "Bass")
    static let bassDropD = numbered("bass-drop-d", "Bass Drop D", [26, 33, 38, 43], lowestPosition: 4, instrument: "Bass")
    static let bassFiveString = numbered("bass-5", "Bass 5-string", [23, 28, 33, 38, 43], lowestPosition: 5, instrument: "Bass")
    static let bassSixString = numbered("bass-6", "Bass 6-string", [23, 28, 33, 38, 43, 48], lowestPosition: 6, instrument: "Bass")

    // MARK: Ukulele

    static let ukulele = labeled(
        "ukulele-c",
        "Ukulele C (re-entrant)",
        instrument: "Ukulele",
        strings: [(67, "G string"), (60, "C string"), (64, "E string"), (69, "A string")]
    )

    static let ukuleleLowG = labeled(
        "ukulele-low-g",
        "Ukulele Low G",
        instrument: "Ukulele",
        strings: [(55, "G string (low)"), (60, "C string"), (64, "E string"), (69, "A string")]
    )

    static let baritoneUkulele = labeled(
        "ukulele-baritone",
        "Baritone Ukulele (DGBE)",
        instrument: "Ukulele",
        strings: [(50, "D string"), (55, "G string"), (59, "B string"), (64, "E string")]
    )

    // MARK: Other instruments

    static let mandolin = labeled(
        "mandolin-gdae",
        "Mandolin (GDAE)",
        instrument: "Other",
        strings: [(55, "G course"), (62, "D course"), (69, "A course"), (76, "E course")]
    )

    static let banjoFiveString = labeled(
        "banjo-open-g",
        "5-string Banjo (Open G)",
        instrument: "Other",
        strings: [(67, "5th string (drone)"), (50, "4th string"), (55, "3rd string"), (59, "2nd string"), (62, "1st string")]
    )

    static let lapSteelC6 = labeled(
        "lap-steel-c6",
        "Lap Steel C6",
        instrument: "Other",
        strings: [(48, "6th string"), (52, "5th string"), (55, "4th string"), (57, "3rd string"), (60, "2nd string"), (64, "1st string")]
    )

    static let tenorGuitar = labeled(
        "tenor-guitar-cgda",
        "Tenor Guitar (CGDA)",
        instrument: "Other",
        strings: [(48, "4th string"), (55, "3rd string"), (62, "2nd string"), (69, "1st string")]
    )

    /// Everything offered in the preset picker, grouped by instrument.
    static let all: [TuningPreset] = [
        .chromatic,
        // Guitar
        .standardGuitar,
        .dropD,
        .doubleDropD,
        .dropCSharp,
        .dropC,
        .dropB,
        .dropA,
        .openD,
        .openG,
        .openE,
        .openA,
        .openC,
        .dadgad,
        .daddad,
        .allFourths,
        .nashville,
        .halfStepDown,
        .dStandard,
        .cStandard,
        .baritoneB,
        // Extended range
        .sevenStringStandard,
        .sevenStringDropA,
        .eightStringStandard,
        // Bass
        .bassFourString,
        .bassDropD,
        .bassFiveString,
        .bassSixString,
        // Ukulele
        .ukulele,
        .ukuleleLowG,
        .baritoneUkulele,
        // Other
        .mandolin,
        .banjoFiveString,
        .lapSteelC6,
        .tenorGuitar,
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

// MARK: - Preset construction helpers

private func guitar(_ id: String, _ name: String, _ midiNumbers: [Int]) -> TuningPreset {
    numbered(id, name, midiNumbers, lowestPosition: midiNumbers.count, instrument: "Guitar")
}

/// Labels strings the way players do: the lowest string of a 6-string is the "6th",
/// of a 7-string the "7th", and so on.
private func numbered(
    _ id: String,
    _ name: String,
    _ midiNumbers: [Int],
    lowestPosition: Int,
    instrument: String
) -> TuningPreset {
    let strings = midiNumbers.enumerated().map { index, midi in
        InstrumentString(midiNumber: midi, label: "\(ordinal(lowestPosition - index)) string")
    }
    return TuningPreset(id: id, name: name, instrument: instrument, strings: strings)
}

private func labeled(
    _ id: String,
    _ name: String,
    instrument: String,
    strings: [(midiNumber: Int, label: String)]
) -> TuningPreset {
    TuningPreset(
        id: id,
        name: name,
        instrument: instrument,
        strings: strings.map { InstrumentString(midiNumber: $0.midiNumber, label: $0.label) }
    )
}

private func ordinal(_ value: Int) -> String {
    let suffix: String = switch (value % 10, value % 100) {
    case (1, 11), (2, 12), (3, 13): "th"
    case (1, _): "st"
    case (2, _): "nd"
    case (3, _): "rd"
    default: "th"
    }
    return "\(value)\(suffix)"
}
