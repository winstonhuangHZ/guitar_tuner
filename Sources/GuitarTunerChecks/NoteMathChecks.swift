import Foundation
import GuitarTunerKit

func runNoteMathChecks(_ runner: CheckRunner) {
    runner.group("NoteMath")

    let a4 = Note(midiNumber: 69)
    runner.near(NoteMath.frequency(of: a4), 440, accuracy: 1e-9, "A4 frequency")
    runner.equal(a4.description(), "A4", "A4 name")
    runner.equal(NoteMath.midiNumber(forFrequency: 440) ?? .nan, 69, "440 Hz is MIDI 69")

    // Textbook values for standard tuning.
    runner.near(NoteMath.frequency(of: Note(midiNumber: 40)), 82.4069, accuracy: 0.001, "low E2")
    runner.near(NoteMath.frequency(of: Note(midiNumber: 45)), 110.0, accuracy: 0.001, "A2")
    runner.near(NoteMath.frequency(of: Note(midiNumber: 50)), 146.8324, accuracy: 0.001, "D3")
    runner.near(NoteMath.frequency(of: Note(midiNumber: 55)), 195.9977, accuracy: 0.001, "G3")
    runner.near(NoteMath.frequency(of: Note(midiNumber: 59)), 246.9417, accuracy: 0.001, "B3")
    runner.near(NoteMath.frequency(of: Note(midiNumber: 64)), 329.6276, accuracy: 0.001, "high E4")

    // Scientific pitch notation.
    runner.equal(Note(midiNumber: 0).description(), "C-1", "MIDI 0 spelling")
    runner.equal(Note(midiNumber: 12).description(), "C0", "MIDI 12 spelling")
    runner.equal(Note(midiNumber: 60).description(), "C4", "MIDI 60 spelling")
    runner.equal(Note(midiNumber: 70).description(style: .flat), "B♭4", "flat spelling")

    // Cents are symmetric around the target.
    runner.near(NoteMath.cents(from: 880, to: 440), 1200, accuracy: 1e-9, "one octave up")
    runner.near(NoteMath.cents(from: 440, to: 440), 0, accuracy: 1e-9, "unison")
    runner.near(NoteMath.cents(from: 440, to: 880), -1200, accuracy: 1e-9, "one octave down")
    runner.near(NoteMath.cents(from: 445, to: 440), 19.56, accuracy: 0.01, "445 Hz vs 440 Hz")

    // Reference pitch scales every target.
    runner.near(NoteMath.frequency(of: Note(midiNumber: 69), referencePitch: 442), 442, accuracy: 1e-9, "A4 at 442")
    runner.near(
        NoteMath.frequency(of: Note(midiNumber: 40), referencePitch: 442),
        82.4069 * 442 / 440,
        accuracy: 0.001,
        "low E at 442"
    )

    let sharp = NoteMath.nearestNote(forFrequency: 445)
    runner.equal(sharp?.note.description(), "A4", "445 Hz nearest note")
    runner.near(sharp?.cents ?? .nan, 19.56, accuracy: 0.02, "445 Hz deviation")

    let flat = NoteMath.nearestNote(forFrequency: 436)
    runner.near(flat?.cents ?? .nan, -15.81, accuracy: 0.02, "436 Hz deviation")

    runner.isNil(NoteMath.midiNumber(forFrequency: 0), "0 Hz is invalid")
    runner.isNil(NoteMath.midiNumber(forFrequency: -100), "negative frequency is invalid")
    runner.isNil(NoteMath.midiNumber(forFrequency: .nan), "NaN frequency is invalid")
    runner.isNil(NoteMath.nearestNote(forFrequency: 0), "no note for 0 Hz")
}
