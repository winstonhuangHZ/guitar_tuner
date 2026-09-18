import Foundation
import GuitarTunerKit

private let checkSampleRate = 48_000.0

private func analyze(
    _ samples: [Float],
    configuration: PitchDetectionConfiguration = .default,
    sampleRate: Double? = nil,
    gate: Double? = nil
) -> PitchAnalysis {
    var detector = PitchDetector(configuration: configuration)
    return detector.analyze(
        samples: samples,
        sampleRate: sampleRate ?? checkSampleRate,
        gate: gate
    )
}

private func cents(_ measured: Double?, from target: Double) -> Double {
    guard let measured else { return .infinity }
    return NoteMath.cents(from: measured, to: target)
}

func runPitchDetectorChecks(_ runner: CheckRunner) {
    runner.group("Pitch detector")

    // MARK: Tuning accuracy

    let lowE = 82.4069
    let lowEResult = analyze(CheckSignals.sine(frequency: lowE, sampleRate: checkSampleRate, count: 4096))
    runner.isNotNil(lowEResult.frequency, "low E is detected")
    runner.less(abs(cents(lowEResult.frequency, from: lowE)), 3, "low E accuracy in cents")
    runner.greater(lowEResult.clarity, 0.9, "low E clarity")

    for midi in [40, 45, 50, 55, 59, 64] {
        let target = NoteMath.frequency(of: Note(midiNumber: midi))
        let samples = CheckSignals.sine(frequency: target, sampleRate: checkSampleRate, count: 4096)
        let result = analyze(samples)
        runner.less(
            abs(cents(result.frequency, from: target)),
            5,
            "MIDI \(midi) (\(target) Hz) accuracy"
        )
    }

    let detuned = lowE * CheckSignals.ratio(forCents: 18)
    let detunedResult = analyze(CheckSignals.sine(frequency: detuned, sampleRate: checkSampleRate, count: 4096))
    runner.near(cents(detunedResult.frequency, from: detuned), 0, accuracy: 3, "18 cents out of tune")

    // MARK: Harmonic content

    let fundamental = 196.0
    let rich = CheckSignals.harmonicTone(
        fundamental: fundamental,
        harmonics: [1.0, 0.6, 0.45, 0.3, 0.2, 0.15],
        sampleRate: checkSampleRate,
        count: 4096
    )
    runner.near(cents(analyze(rich).frequency, from: fundamental), 0, accuracy: 6, "harmonic-rich tone")

    // A neck pickup with the tone rolled off can hand the tuner a 2nd harmonic that is
    // louder than the fundamental; reporting the octave would be a real bug.
    let secondHarmonic = CheckSignals.harmonicTone(
        fundamental: lowE,
        harmonics: [1.0, 2.6, 1.8, 1.1, 0.7],
        sampleRate: checkSampleRate,
        count: 4096
    )
    let harmonicResult = analyze(secondHarmonic)
    runner.near(cents(harmonicResult.frequency, from: lowE), 0, accuracy: 15, "fundamental wins over 2.6x 2nd harmonic")
    runner.expect(
        abs(cents(harmonicResult.frequency, from: lowE * 2)) > 50,
        "no octave error: expected ~\(lowE) Hz, got \(String(describing: harmonicResult.frequency)) Hz"
    )

    // A bright pickup feeds the detector lots of upper harmonics.
    let bright = CheckSignals.harmonicTone(
        fundamental: lowE,
        harmonics: [1.0, 0.35, 0.25, 0.2, 0.95, 0.2, 0.15, 0.85, 0.15, 0.1],
        sampleRate: checkSampleRate,
        count: 4096
    )
    runner.near(cents(analyze(bright).frequency, from: lowE), 0, accuracy: 10, "bright tone with strong upper harmonics")

    // Out-of-band bleed (pick squeal, string noise). In the app the input filters keep
    // most of this out of the detector; what matters here is that it cannot produce an
    // octave error or a wildly wrong answer.
    var pickNoise = CheckSignals.sine(frequency: lowE, sampleRate: checkSampleRate, count: 4096, amplitude: 0.3)
    pickNoise = CheckSignals.mix(
        pickNoise,
        CheckSignals.sine(frequency: 3000, sampleRate: checkSampleRate, count: 4096, amplitude: 0.06)
    )
    let bleedResult = analyze(pickNoise)
    runner.less(
        abs(cents(bleedResult.frequency, from: lowE)),
        40,
        "3 kHz bleed does not drag the pitch far: got \(String(describing: bleedResult.frequency)) Hz"
    )

    let decaying = CheckSignals.harmonicTone(
        fundamental: 146.8324,
        amplitude: 0.5,
        harmonics: [1.0, 0.5, 0.3],
        sampleRate: checkSampleRate,
        count: 4096,
        decay: 4
    )
    runner.near(cents(analyze(decaying, gate: 0.002).frequency, from: 146.8324), 0, accuracy: 8, "decaying note")

    // Other hardware rates.
    let at44 = analyze(
        CheckSignals.sine(frequency: 110, sampleRate: 44_100, count: 4096),
        sampleRate: 44_100
    )
    runner.near(cents(at44.frequency, from: 110), 0, accuracy: 4, "44.1 kHz sample rate")

    // MARK: Gating

    let silence = analyze([Float](repeating: 0, count: 4096))
    runner.isNil(silence.frequency, "silence is gated")
    runner.expect(silence.isGated, "silence is flagged as gated")
    runner.near(silence.rms, 0, accuracy: 1e-12, "silence RMS")

    let quietNoise = analyze(
        CheckSignals.whiteNoise(count: 4096, amplitude: 0.004, seed: 42),
        gate: 0.02
    )
    runner.isNil(quietNoise.frequency, "quiet noise stays under the gate")
    runner.expect(quietNoise.isGated, "quiet noise is flagged as gated")

    let loudNoise = analyze(CheckSignals.whiteNoise(count: 4096, amplitude: 0.3, seed: 7))
    runner.isNil(loudNoise.frequency, "broadband noise never looks periodic")

    let tooShort = analyze(CheckSignals.sine(frequency: 110, sampleRate: checkSampleRate, count: 100))
    runner.isNil(tooShort.frequency, "very short input is ignored")
    runner.near(tooShort.rms, 0, accuracy: 1e-12, "very short input RMS")

    // MARK: Range limits

    var narrow = PitchDetectionConfiguration.default
    narrow.minFrequency = 200
    narrow.maxFrequency = 400
    let outsideRange = analyze(
        CheckSignals.sine(frequency: 110, sampleRate: checkSampleRate, count: 4096),
        configuration: narrow
    )
    runner.isNil(outsideRange.frequency, "110 Hz is rejected by a 200-400 Hz search range")

    var bass = PitchDetectionConfiguration.default
    bass.minFrequency = 30
    bass.analysisWindowSize = 8192
    let bassTarget = NoteMath.frequency(of: Note(midiNumber: 28)) // E1, 41.2 Hz
    let bassTone = CheckSignals.harmonicTone(
        fundamental: bassTarget,
        harmonics: [1.0, 0.7, 0.4, 0.25],
        sampleRate: checkSampleRate,
        count: 8192
    )
    runner.near(
        cents(analyze(bassTone, configuration: bass).frequency, from: bassTarget),
        0,
        accuracy: 12,
        "E1 on a 5-string bass range"
    )

    // MARK: Level reporting

    let quiet = analyze(CheckSignals.sine(frequency: 220, sampleRate: checkSampleRate, count: 4096, amplitude: 0.01))
    let loud = analyze(CheckSignals.sine(frequency: 220, sampleRate: checkSampleRate, count: 4096, amplitude: 0.5))
    runner.less(quiet.level, loud.level, "level follows amplitude")
    runner.greater(loud.level, 0.8, "a loud signal nearly fills the meter")
}
