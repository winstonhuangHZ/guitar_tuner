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
}
