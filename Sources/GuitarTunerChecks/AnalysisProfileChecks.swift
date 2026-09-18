import Foundation
import GuitarTunerKit

func runAnalysisProfileChecks(_ runner: CheckRunner) {
    runner.group("Analysis profile")

    // Microphone mode: 70 Hz - 1 kHz band-pass, pulled down to 61.8 Hz so the low E
    // fundamental sits safely inside the pass-band.
    let microphone = AnalysisProfile.make(inputMode: .microphone, selection: .default)
    runner.near(microphone.highPassFrequency ?? .nan, 61.8, accuracy: 0.1, "microphone high-pass")
    runner.near(microphone.lowPassFrequency ?? .nan, 1000, accuracy: 0.1, "microphone low-pass")

    // Pickup mode: low-pass tames the harmonics, opened above the 1st string.
    let pickup = AnalysisProfile.make(inputMode: .pickup, selection: .default)
    runner.near(pickup.highPassFrequency ?? .nan, 60, accuracy: 0.1, "pickup high-pass")
    runner.near(pickup.lowPassFrequency ?? .nan, 412, accuracy: 0.5, "pickup low-pass")
    runner.less(pickup.lowPassFrequency ?? 0, microphone.lowPassFrequency ?? 0, "pickup filters harder than microphone")

    // Chromatic mode has no tuning to follow, so the raw mode defaults apply.
    var chromatic = TuningSelection.default
    chromatic.preset = .chromatic
    let chromaticMic = AnalysisProfile.make(inputMode: .microphone, selection: chromatic)
    runner.near(chromaticMic.highPassFrequency ?? .nan, 70, accuracy: 0.1, "chromatic high-pass")
    runner.near(chromaticMic.lowPassFrequency ?? .nan, 1000, accuracy: 0.1, "chromatic low-pass")
    let chromaticPickup = AnalysisProfile.make(inputMode: .pickup, selection: chromatic)
    runner.near(chromaticPickup.highPassFrequency ?? .nan, 60, accuracy: 0.1, "chromatic pickup high-pass")
    runner.near(chromaticPickup.lowPassFrequency ?? .nan, 400, accuracy: 0.1, "chromatic pickup low-pass")

    // Bass: 30.9 Hz must survive the high-pass.
    var bass = TuningSelection.default
    bass.preset = .bassFiveString
    let bassProfile = AnalysisProfile.make(inputMode: .microphone, selection: bass)
    runner.less(bassProfile.highPassFrequency ?? 0, 31, "bass high-pass sits below B0")
    runner.lessOrEqual(bassProfile.minFrequency, 31, "detector range reaches B0")

    // Ukulele: the 440 Hz A string must survive the pickup low-pass.
    var ukulele = TuningSelection.default
    ukulele.preset = .ukulele
    let ukuleleProfile = AnalysisProfile.make(inputMode: .pickup, selection: ukulele)
    runner.greater(ukuleleProfile.lowPassFrequency ?? 0, 440, "ukulele A4 stays inside the pass-band")

    // Detector range always leaves headroom around the preset.
    let range = AnalysisProfile.make(inputMode: .microphone, selection: .default)
    runner.lessOrEqual(range.minFrequency, 82.4069, "range covers the low E")
    runner.greater(range.maxFrequency, 329.6276 * 2, "range keeps harmonic headroom")
    runner.greater(range.minFrequency, AnalysisProfile.absoluteMinFrequency - 1, "range respects the absolute floor")
    runner.lessOrEqual(range.maxFrequency, AnalysisProfile.absoluteMaxFrequency, "range respects the absolute ceiling")
}
