import Foundation
import GuitarTunerKit

func runTuningPresetChecks(_ runner: CheckRunner) {
    runner.group("Tuning presets")

    let standard = TuningPreset.standardGuitar
    runner.equal(standard.strings.map(\.noteName), ["E2", "A2", "D3", "G3", "B3", "E4"], "standard tuning")
    runner.equal(
        standard.strings.map(\.label),
        ["6th string", "5th string", "4th string", "3rd string", "2nd string", "1st string"],
        "string labels"
    )

    let ids = TuningPreset.all.map(\.id)
    runner.equal(Set(ids).count, ids.count, "preset ids are unique")
    runner.equal(TuningPreset.preset(id: "guitar-standard")?.name, "Standard E", "preset lookup by id")

    runner.expect(TuningPreset.chromatic.isChromatic, "chromatic preset has no strings")
    runner.isNil(TuningPreset.chromatic.frequencyRange(), "chromatic preset has no range")
    runner.expect(!standard.isChromatic, "standard guitar is not chromatic")

    // String ids stay sequential from the lowest string upwards.
    for preset in TuningPreset.all where !preset.isChromatic {
        runner.equal(
            preset.strings.map(\.id),
            Array(0..<preset.strings.count),
            "\(preset.name) string ids"
        )
    }

    let range = standard.frequencyRange()
    runner.near(range?.lowerBound ?? .nan, NoteMath.frequency(of: Note(midiNumber: 40)), accuracy: 0.001, "range low")
    runner.near(range?.upperBound ?? .nan, NoteMath.frequency(of: Note(midiNumber: 64)), accuracy: 0.001, "range high")

    // Deviation sign convention: sharp is positive.
    let lowE = standard.strings[0]
    let sharp = lowE.frequency() * CheckSignals.ratio(forCents: 12)
    runner.near(lowE.centsDeviation(for: sharp), 12, accuracy: 0.001, "12 cents sharp")
    runner.near(lowE.centsDeviation(for: lowE.frequency()), 0, accuracy: 1e-9, "in tune")

    // Drop D lowers only the 6th string.
    runner.equal(TuningPreset.dropD.strings.map(\.noteName), ["D2", "A2", "D3", "G3", "B3", "E4"], "drop D")
    // Bass presets descend below the guitar's range.
    runner.equal(TuningPreset.bassFiveString.strings.first?.noteName, "B0", "5-string bass low B")
    runner.equal(TuningPreset.ukulele.strings.map(\.noteName), ["G4", "C4", "E4", "A4"], "ukulele GCEA")

    let groups = TuningPreset.groups
    runner.equal(groups.count, Set(TuningPreset.all.map(\.instrument)).count, "preset groups")
    runner.equal(groups.reduce(0) { $0 + $1.presets.count }, TuningPreset.all.count, "all presets are grouped")

    // MARK: Preset library

    runner.greater(TuningPreset.all.count, 30, "preset library size")

    for preset in TuningPreset.all {
        runner.expect(!preset.name.isEmpty, "\(preset.id) has a name")
        runner.expect(!preset.instrument.isEmpty, "\(preset.id) has an instrument group")
        runner.expect(
            preset.strings.allSatisfy { $0.frequency() > 0 },
            "\(preset.name) has valid target frequencies"
        )
        guard !preset.isChromatic else { continue }
        runner.expect(!preset.noteSummary.isEmpty, "\(preset.name) has a note summary")
        runner.expect(preset.strings.count >= 4, "\(preset.name) has at least four strings")
    }

    // Famous non-standard tunings, checked against their textbook pitches.
    runner.equal(TuningPreset.dropD.strings.map(\.noteName), ["D2", "A2", "D3", "G3", "B3", "E4"], "Drop D")
    runner.equal(
        TuningPreset.doubleDropD.strings.map(\.noteName),
        ["D2", "A2", "D3", "G3", "B3", "D4"],
        "Double Drop D"
    )
    runner.equal(TuningPreset.dropC.strings.map(\.noteName), ["C2", "G2", "C3", "F3", "A3", "D4"], "Drop C")
    runner.equal(TuningPreset.openG.strings.map(\.noteName), ["D2", "G2", "D3", "G3", "B3", "D4"], "Open G")
    runner.equal(TuningPreset.openD.strings.map(\.noteName), ["D2", "A2", "D3", "F♯3", "A3", "D4"], "Open D")
    runner.equal(TuningPreset.openE.strings.map(\.noteName), ["E2", "B2", "E3", "G♯3", "B3", "E4"], "Open E")
    runner.equal(TuningPreset.openC.strings.map(\.noteName), ["C2", "G2", "C3", "G3", "C4", "E4"], "Open C")
    runner.equal(TuningPreset.dadgad.strings.map(\.noteName), ["D2", "A2", "D3", "G3", "A3", "D4"], "DADGAD")
    runner.equal(TuningPreset.daddad.strings.map(\.noteName), ["D2", "A2", "D3", "D3", "A3", "D4"], "DADDAD")
    runner.equal(TuningPreset.allFourths.strings.map(\.noteName), ["E2", "A2", "D3", "G3", "C4", "F4"], "All Fourths")
    runner.equal(
        TuningPreset.halfStepDown.strings.map(\.noteName),
        ["D♯2", "G♯2", "C♯3", "F♯3", "A♯3", "D♯4"],
        "E♭ standard"
    )
    runner.equal(
        TuningPreset.dStandard.strings.map(\.noteName),
        ["D2", "G2", "C3", "F3", "A3", "D4"],
        "D standard"
    )

    // Extended range instruments.
    runner.equal(TuningPreset.sevenStringStandard.strings.count, 7, "7-string has seven strings")
    runner.equal(TuningPreset.sevenStringStandard.strings.first?.noteName, "B1", "7-string low B")
    runner.equal(TuningPreset.sevenStringStandard.strings.first?.label, "7th string", "7-string label")
    runner.equal(TuningPreset.eightStringStandard.strings.count, 8, "8-string has eight strings")
    runner.equal(TuningPreset.eightStringStandard.strings.first?.noteName, "F♯1", "8-string low F♯")
    runner.equal(TuningPreset.eightStringStandard.strings.first?.label, "8th string", "8-string label")
    runner.equal(TuningPreset.bassSixString.strings.map(\.noteName), ["B0", "E1", "A1", "D2", "G2", "C3"], "6-string bass")
    runner.equal(TuningPreset.bassDropD.strings.map(\.noteName), ["D1", "A1", "D2", "G2"], "Drop D bass")

    // Re-entrant and non-guitar instruments: the range must come from the actual
    // frequencies, not from the order the strings are listed in.
    let ukuleleRange = TuningPreset.ukulele.frequencyRange()
    runner.near(
        ukuleleRange?.lowerBound ?? .nan,
        NoteMath.frequency(of: Note(midiNumber: 60)),
        accuracy: 0.01,
        "re-entrant ukulele low note is C4, not the first string"
    )
    runner.near(
        ukuleleRange?.upperBound ?? .nan,
        NoteMath.frequency(of: Note(midiNumber: 69)),
        accuracy: 0.01,
        "re-entrant ukulele high note is A4"
    )
    runner.equal(TuningPreset.ukuleleLowG.strings.first?.noteName, "G3", "Low G ukulele")
    runner.equal(TuningPreset.baritoneUkulele.strings.map(\.noteName), ["D3", "G3", "B3", "E4"], "Baritone ukulele")
    runner.equal(TuningPreset.mandolin.strings.map(\.noteName), ["G3", "D4", "A4", "E5"], "Mandolin GDAE")
    runner.equal(
        TuningPreset.banjoFiveString.strings.map(\.noteName),
        ["G4", "D3", "G3", "B3", "D4"],
        "5-string banjo open G (drone string first)"
    )
    runner.equal(TuningPreset.lapSteelC6.strings.map(\.noteName), ["C3", "E3", "G3", "A3", "C4", "E4"], "Lap steel C6")
    runner.equal(TuningPreset.tenorGuitar.strings.map(\.noteName), ["C3", "G3", "D4", "A4"], "Tenor guitar CGDA")

    // Nashville tuning is high-strung: the 3rd string is no longer the lowest of the
    // upper three, so the range has to be computed, not assumed.
    let nashvilleRange = TuningPreset.nashville.frequencyRange()
    runner.near(
        nashvilleRange?.lowerBound ?? .nan,
        NoteMath.frequency(of: Note(midiNumber: 52)),
        accuracy: 0.01,
        "Nashville lowest target is E3"
    )
}
