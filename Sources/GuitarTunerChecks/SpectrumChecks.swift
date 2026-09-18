import Foundation
import GuitarTunerKit

private func level(of snapshot: SpectrumSnapshot, at frequency: Double) -> Double? {
    guard let position = snapshot.position(forFrequency: frequency), !snapshot.levels.isEmpty else {
        return nil
    }
    let index = min(snapshot.levels.count - 1, max(0, Int(position * Double(snapshot.levels.count))))
    return Double(snapshot.levels[index])
}

func runSpectrumChecks(_ runner: CheckRunner) {
    runner.group("Spectrum analyser")

    let analyzer = SpectrumAnalyzer()
    let sampleRate = 48_000.0

    runner.equal(analyzer.windowSize, 8192, "default FFT window")
    runner.equal(analyzer.binCount, 96, "default display bin count")

    // MARK: Shape and bounds

    let silence = analyzer.analyze(samples: [Float](repeating: 0, count: 8192), sampleRate: sampleRate)
    runner.equal(silence.levels.count, 96, "silence still produces a full-width frame")
    runner.expect(silence.levels.allSatisfy { $0 == 0 }, "silence has no energy in any bin")
    runner.isNil(silence.peakFrequency, "silence has no peak")

    let tooShort = analyzer.analyze(samples: [Float](repeating: 0, count: 128), sampleRate: sampleRate)
    runner.expect(tooShort.isEmpty, "very short input yields an empty frame")

    // MARK: Frequency accuracy

    let a440 = analyzer.analyze(
        samples: CheckSignals.sine(frequency: 440, sampleRate: sampleRate, count: 8192, amplitude: 0.4),
        sampleRate: sampleRate
    )
    runner.equal(a440.levels.count, 96, "A440 frame size")
    runner.near(a440.peakFrequency ?? .nan, 440, accuracy: 12, "A440 peak frequency")
    runner.expect(a440.levels.allSatisfy { $0 >= 0 && $0 <= 1 }, "levels stay inside 0...1")
    runner.near(Double(a440.levels.max() ?? 0), 1, accuracy: 1e-5, "strongest partial fills the display")
    runner.near(level(of: a440, at: 440) ?? 0, 1, accuracy: 0.05, "bin at 440 Hz is the tall one")

    // A pure tone leaks a little, but 60 dB down it should be invisible at 880 Hz.
    runner.less(level(of: a440, at: 880) ?? 1, 0.25, "no phantom 2nd harmonic for a pure tone")

    let lowE = analyzer.analyze(
        samples: CheckSignals.harmonicTone(
            fundamental: 82.4069,
            amplitude: 0.5,
            harmonics: [1.0, 0.9, 0.6, 0.4, 0.25],
            sampleRate: sampleRate,
            count: 8192
        ),
        sampleRate: sampleRate
    )
    runner.near(lowE.peakFrequency ?? .nan, 82.4069, accuracy: 12, "low E peak frequency")

    // With the 2nd harmonic louder than the fundamental the spectrum must say so —
    // that is exactly the case the pickup filter exists for.
    let secondHarmonic = analyzer.analyze(
        samples: CheckSignals.harmonicTone(
            fundamental: 220,
            amplitude: 0.5,
            harmonics: [1.0, 2.5, 1.2],
            sampleRate: sampleRate,
            count: 8192
        ),
        sampleRate: sampleRate
    )
    runner.near(secondHarmonic.peakFrequency ?? .nan, 440, accuracy: 12, "loud 2nd harmonic becomes the peak")
    runner.greater(level(of: secondHarmonic, at: 440) ?? 0, level(of: secondHarmonic, at: 220) ?? 1, "2nd harmonic bar is taller")

    // MARK: Axis mapping

    runner.near(a440.position(forFrequency: a440.minFrequency) ?? .nan, 0, accuracy: 1e-9, "axis start")
    runner.near(a440.position(forFrequency: a440.maxFrequency) ?? .nan, 1, accuracy: 1e-9, "axis end")
    runner.greater(
        a440.position(forFrequency: 880) ?? 0,
        a440.position(forFrequency: 440) ?? 1,
        "axis is logarithmic and increasing"
    )
    runner.isNil(a440.position(forFrequency: 10), "frequencies below the axis map to nothing")
    runner.isNil(a440.position(forFrequency: 20_000), "frequencies above the axis map to nothing")
    runner.isNil(a440.position(forFrequency: 0), "zero frequency maps to nothing")
    runner.near(a440.minFrequency, 40, accuracy: 1e-9, "default axis start")
    runner.near(a440.maxFrequency, 4000, accuracy: 1e-9, "default axis end")

    // MARK: Range follows the tuning

    let bassAnalyzer = SpectrumAnalyzer()
    bassAnalyzer.setFrequencyRange(min: 20, max: 4000)
    let bassFrame = bassAnalyzer.analyze(
        samples: CheckSignals.sine(frequency: 30.87, sampleRate: sampleRate, count: 8192, amplitude: 0.4),
        sampleRate: sampleRate
    )
    runner.near(bassFrame.minFrequency, 20, accuracy: 1e-9, "bass axis start")
    runner.near(bassFrame.peakFrequency ?? .nan, 30.87, accuracy: 6, "B0 is visible on the bass axis")
    runner.near(level(of: bassFrame, at: 30.87) ?? 0, 1, accuracy: 0.05, "B0 bin carries the peak")

    let ukuleleAnalyzer = SpectrumAnalyzer()
    ukuleleAnalyzer.setFrequencyRange(min: 30, max: 4000)
    let ukuleleFrame = ukuleleAnalyzer.analyze(
        samples: CheckSignals.sine(frequency: 440, sampleRate: sampleRate, count: 8192, amplitude: 0.4),
        sampleRate: sampleRate
    )
    runner.near(ukuleleFrame.peakFrequency ?? .nan, 440, accuracy: 12, "ukulele A string is visible")
    runner.expect(
        ukuleleFrame.position(forFrequency: 440) != nil,
        "A4 has a marker position on the ukulele axis"
    )

    // A range that is nonsensical still has to produce a usable axis.
    let guarded = SpectrumAnalyzer()
    guarded.setFrequencyRange(min: 5000, max: 100)
    runner.greater(guarded.maxFrequency, guarded.minFrequency, "axis guard keeps max above min")
}
