import Foundation
import GuitarTunerKit

private func stabilizedPitch(_ frequency: Double, clarity: Double = 0.95) -> StabilizedPitch {
    let rms = 0.05
    let analysis = PitchAnalysis(
        rms: rms,
        level: SignalMetrics.normalizedLevel(rms: rms),
        gate: 0.003,
        frequency: frequency,
        clarity: clarity,
        lag: nil,
        isGated: false
    )
    return StabilizedPitch(
        frequency: frequency,
        rawFrequency: frequency,
        clarity: clarity,
        analysis: analysis,
        isHeld: false
    )
}

private func evaluate(
    _ frequency: Double,
    selection: TuningSelection = .default,
    clarity: Double = 0.95,
    evaluator: inout TunerEvaluator
) -> TunerReading {
    evaluator.evaluate(stabilizedPitch(frequency, clarity: clarity), selection: selection, timestamp: 0)
}

func runTunerEvaluatorChecks(_ runner: CheckRunner) {
    runner.group("Tuner evaluation")

    var evaluator = TunerEvaluator()

    let lowE = evaluate(82.4069, evaluator: &evaluator)
    runner.equal(lowE.target?.note.description(), "E2", "auto mode picks the low E string")
    runner.near(lowE.cents ?? .nan, 0, accuracy: 0.01, "in-tune deviation")
    runner.expect(lowE.isInTune, "exact pitch counts as in tune")

    let sharp = evaluate(82.4069 * CheckSignals.ratio(forCents: 12), evaluator: &evaluator)
    runner.near(sharp.cents ?? .nan, 12, accuracy: 0.05, "sharp deviation")
    runner.equal(sharp.direction, .sharp, "sharp direction")
    runner.expect(!sharp.isInTune, "12 cents sharp is not in tune")

    let flat = evaluate(110.0 * CheckSignals.ratio(forCents: -8), evaluator: &evaluator)
    runner.near(flat.cents ?? .nan, -8, accuracy: 0.05, "flat deviation")
    runner.equal(flat.direction, .flat, "flat direction")

    // A tighter window changes the verdict, not the measurement.
    var tight = TuningSelection.default
    tight.inTuneToleranceCents = 3
    let notQuite = evaluate(110.0 * CheckSignals.ratio(forCents: 4), selection: tight, evaluator: &evaluator)
    runner.expect(!notQuite.isInTune, "4 cents out is not in tune with a ±3 window")

    // Low clarity can never claim "in tune", however perfect the number.
    let noisy = evaluate(110.0, clarity: 0.2, evaluator: &evaluator)
    runner.near(noisy.cents ?? .nan, 0, accuracy: 0.01, "noisy deviation is still measured")
    runner.expect(!noisy.isInTune, "low clarity is never in tune")

    // Locked strings ignore closer neighbours — that is the point of locking one.
    var locked = TuningSelection.default
    locked.stringSelection = .locked(5) // 1st string, E4
    let wrongString = evaluate(110.0, selection: locked, evaluator: &evaluator)
    runner.equal(wrongString.target?.noteName, "E4", "locked string is used")
    runner.less(wrongString.cents ?? 0, -1800, "110 Hz against E4 is far flat")

    var lockedSecond = TuningSelection.default
    lockedSecond.stringSelection = .locked(1) // A2
    let asLocked = evaluate(146.83, selection: lockedSecond, evaluator: &evaluator)
    runner.equal(asLocked.target?.id, "string-1", "locked A2 stays selected")
    runner.greater(asLocked.cents ?? 0, 0, "146.83 Hz reads sharp against A2")

    // Chromatic mode tracks the nearest semitone instead of a preset string.
    var chromatic = TuningSelection.default
    chromatic.preset = .chromatic
    let chromaticReading = evaluate(445, selection: chromatic, evaluator: &evaluator)
    runner.equal(chromaticReading.target?.note.description(), "A4", "chromatic nearest semitone")
    runner.near(chromaticReading.cents ?? .nan, 19.56, accuracy: 0.05, "chromatic deviation")
    runner.equal(chromaticReading.target?.kind, PitchTarget.Kind.chromatic, "chromatic target kind")

    // Hysteresis: near the boundary between two strings the tuner keeps the string it was
    // on. The A2/D3 boundary is used because the 220 Hz region is ambiguous with the 2nd
    // harmonic of the A string, which is a different behaviour (see the harmonic checks).
    var hysteresis = TunerEvaluator()
    let a = evaluate(112, evaluator: &hysteresis)
    runner.equal(a.target?.id, "string-1", "A2 is matched first")
    let boundary = evaluate(127.5, evaluator: &hysteresis)
    runner.equal(boundary.target?.id, "string-1", "hysteresis keeps A2 near the boundary")
    let moved = evaluate(140, evaluator: &hysteresis)
    runner.equal(moved.target?.id, "string-2", "a clear move switches to D3")

    // Reference pitch moves every target.
    var selection442 = TuningSelection.default
    selection442.referencePitch = 442
    let at442 = evaluate(
        NoteMath.frequency(of: Note(midiNumber: 40), referencePitch: 442),
        selection: selection442,
        evaluator: &evaluator
    )
    runner.near(at442.cents ?? .nan, 0, accuracy: 0.01, "reference pitch is applied")

    // Losing the signal clears the target.
    _ = evaluate(110, evaluator: &evaluator)
    let silent = evaluator.evaluate(
        StabilizedPitch(frequency: nil, rawFrequency: nil, clarity: 0, analysis: .silent, isHeld: false),
        selection: .default,
        timestamp: 1
    )
    runner.isNil(silent.target, "no signal clears the target")
    runner.isNil(silent.cents, "no signal clears the deviation")
    runner.equal(silent.direction, .idle, "idle direction")

    // The needle input is clamped to the gauge range.
    let waySharp = evaluate(82.4069 * CheckSignals.ratio(forCents: 240), evaluator: &evaluator)
    runner.greater(waySharp.cents ?? 0, 200, "240 cents sharp is measured")
    runner.near(waySharp.needleCents(limit: 50), 50, accuracy: 0.001, "needle is clamped")
}

/// A low string whose fundamental is weak is the classic failure of every tuner: the
/// detector locks onto the 2nd harmonic, and the harmonic is close enough to some *other*
/// string that the app confidently names the wrong one. On a guitar the low E is 82.4 Hz,
/// its 2nd harmonic is 164.8 Hz (E3), and 164.8 Hz sits only 200 cents from the D3 string.
func runHarmonicFoldChecks(_ runner: CheckRunner) {
    runner.group("Harmonic lock")

    var evaluator = TunerEvaluator()
    let lowE = 82.4069
    let aString = 110.0

    // The 2nd harmonic of the low E must be read as the low E, not as D3.
    let secondHarmonic = evaluate(lowE * 2, evaluator: &evaluator)
    runner.equal(secondHarmonic.target?.noteName, "E2", "the 2nd harmonic of E2 is read as the 6th string")
    runner.near(secondHarmonic.cents ?? .nan, 0, accuracy: 0.05, "and it reads in tune")
    runner.equal(secondHarmonic.harmonicDivisor, 2, "the reading is flagged as a 2nd harmonic")

    // Same story on the A string.
    let aSecond = evaluate(aString * 2, evaluator: &evaluator)
    runner.equal(aSecond.target?.noteName, "A2", "the 2nd harmonic of A2 is read as the 5th string")
    runner.equal(aSecond.harmonicDivisor, 2, "flagged as a harmonic")

    // 247.2 Hz is genuinely ambiguous: it is both the open B string and the 3rd harmonic of
    // low E, and no amount of signal processing can tell those apart. Auto mode reports the
    // exact match; locking the string is the way to say which one is meant.
    let thirdHarmonic = evaluate(lowE * 3, evaluator: &evaluator)
    runner.equal(
        thirdHarmonic.target?.noteName,
        "B3",
        "the 3rd harmonic is indistinguishable from the open B string"
    )
    runner.isNil(thirdHarmonic.harmonicDivisor, "and is not folded")

    var lockedSixth = TuningSelection.default
    lockedSixth.stringSelection = .locked(0)
    let lockedThird = evaluate(lowE * 3, selection: lockedSixth, evaluator: &evaluator)
    runner.equal(lockedThird.target?.noteName, "E2", "with the 6th string locked it belongs to E2")
    runner.equal(lockedThird.harmonicDivisor, 3, "flagged as a 3rd harmonic")

    // A genuinely played D3 is still D3: the direct interpretation is in tune, so nothing
    // is folded.
    let realD = evaluate(146.8324, evaluator: &evaluator)
    runner.equal(realD.target?.noteName, "D3", "a real D3 is still D3")
    runner.isNil(realD.harmonicDivisor, "and it is not flagged as a harmonic")

    // A real, slightly sharp low E is not folded either.
    let realSharpE = evaluate(lowE * CheckSignals.ratio(forCents: 12), evaluator: &evaluator)
    runner.equal(realSharpE.target?.noteName, "E2", "a 12 cent sharp E2 is E2")
    runner.near(realSharpE.cents ?? .nan, 12, accuracy: 0.05, "and keeps its deviation")
    runner.isNil(realSharpE.harmonicDivisor, "no harmonic flag for a fundamental")

    // Folding only happens when it actually lands on a string: a note halfway between
    // strings must not be disguised as a harmonic.
    let betweenStrings = evaluate(174.6, evaluator: &evaluator)
    runner.isNil(
        betweenStrings.harmonicDivisor,
        "F3 is not folded into a harmonic (\(betweenStrings.target?.noteName ?? "—") \(String(format: "%+.0f", betweenStrings.cents ?? 0))¢)"
    )

    // Locking a string makes the fold unconditional: the tuner knows which string the
    // player is on, so a harmonic reading belongs to that string.
    var locked = TuningSelection.default
    locked.stringSelection = .locked(0)
    let lockedHarmonic = evaluate(lowE * 2, selection: locked, evaluator: &evaluator)
    runner.equal(lockedHarmonic.target?.noteName, "E2", "with the 6th string locked the harmonic reads as E2")
    runner.near(lockedHarmonic.cents ?? .nan, 0, accuracy: 0.05, "locked harmonic reads in tune")

    // A string that is genuinely far off still reports its real deviation.
    let wayFlat = evaluate(lowE * CheckSignals.ratio(forCents: -120), evaluator: &evaluator)
    runner.equal(wayFlat.target?.noteName, "E2", "a 120 cent flat E2 is still the 6th string")
    runner.near(wayFlat.cents ?? .nan, -120, accuracy: 0.1, "with its real deviation")
    runner.isNil(wayFlat.harmonicDivisor, "a detuned fundamental is not a harmonic")
}
