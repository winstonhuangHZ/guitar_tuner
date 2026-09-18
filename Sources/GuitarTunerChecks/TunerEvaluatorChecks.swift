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

    // Hysteresis: at the boundary between G3 and B3 the tuner keeps the string it was on.
    var hysteresis = TunerEvaluator()
    let g = evaluate(200, evaluator: &hysteresis)
    runner.equal(g.target?.id, "string-3", "G3 is matched first")
    let boundary = evaluate(220.5, evaluator: &hysteresis)
    runner.equal(boundary.target?.id, "string-3", "hysteresis keeps G3 near the boundary")
    let moved = evaluate(225, evaluator: &hysteresis)
    runner.equal(moved.target?.id, "string-4", "a clear move switches to B3")

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
