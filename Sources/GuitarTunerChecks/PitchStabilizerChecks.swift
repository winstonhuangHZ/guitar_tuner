import Foundation
import GuitarTunerKit

private func pitched(_ frequency: Double, clarity: Double = 0.92, rms: Double = 0.05) -> PitchAnalysis {
    PitchAnalysis(
        rms: rms,
        level: SignalMetrics.normalizedLevel(rms: rms),
        gate: 0.003,
        frequency: frequency,
        clarity: clarity,
        lag: nil,
        isGated: false
    )
}

private func gatedAnalysis(rms: Double = 0.0005) -> PitchAnalysis {
    PitchAnalysis(rms: rms, level: 0, gate: 0.003, frequency: nil, clarity: 0, lag: nil, isGated: true)
}

private func unclear(rms: Double = 0.05) -> PitchAnalysis {
    PitchAnalysis(
        rms: rms,
        level: SignalMetrics.normalizedLevel(rms: rms),
        gate: 0.003,
        frequency: nil,
        clarity: 0.2,
        lag: nil,
        isGated: false
    )
}

func runPitchStabilizerChecks(_ runner: CheckRunner) {
    runner.group("Pitch stabilizer")

    // A single wild frame must not move the needle.
    var stabilizer = PitchStabilizer()
    var smoothed: Double?
    for frequency in [110.0, 110.0, 118.0, 110.0, 110.0] {
        smoothed = stabilizer.process(pitched(frequency), at: 0).frequency
    }
    runner.near(smoothed ?? .nan, 110, accuracy: 0.001, "median rejects a single outlier frame")

    // A real drift has to come through.
    stabilizer = PitchStabilizer()
    for frequency in [108.0, 109.0, 110.0, 111.0, 112.0, 113.0] {
        smoothed = stabilizer.process(pitched(frequency), at: 0).frequency
    }
    runner.near(smoothed ?? .nan, 111, accuracy: 0.001, "slow drift is followed")

    // Switching strings clears the window instead of averaging across two notes.
    stabilizer = PitchStabilizer()
    _ = stabilizer.process(pitched(82.4069), at: 0)
    _ = stabilizer.process(pitched(82.4069), at: 0.05)
    let jumped = stabilizer.process(pitched(329.6276), at: 0.1)
    runner.near(jumped.frequency ?? .nan, 329.6276, accuracy: 0.5, "string change clears the history")

    // Holding a reading through a brief dropout.
    stabilizer = PitchStabilizer()
    _ = stabilizer.process(pitched(146.83), at: 0)
    let held = stabilizer.process(gatedAnalysis(), at: 0.2)
    runner.expect(held.isHeld, "gated frame holds the previous reading")
    runner.near(held.frequency ?? .nan, 146.83, accuracy: 0.001, "held value is the previous pitch")

    let expired = stabilizer.process(gatedAnalysis(), at: 0.5)
    runner.expect(expired.isHeld, "reading is still held at 0.5 s (hold is 1.5 s)")
    let wellExpired = stabilizer.process(gatedAnalysis(), at: 2.0)
    runner.expect(!wellExpired.isHeld, "hold expires eventually")
    runner.isNil(wellExpired.frequency, "reading clears after the hold expires")

    // Unclear frames (loud but not periodic) are trusted for less time.
    stabilizer = PitchStabilizer()
    _ = stabilizer.process(pitched(146.83), at: 0)
    runner.isNotNil(stabilizer.process(unclear(), at: 0.1).frequency, "unclear frame holds briefly")
    runner.isNil(stabilizer.process(unclear(), at: 1.0).frequency, "unclear frame expires sooner than a gated one")

    stabilizer = PitchStabilizer()
    _ = stabilizer.process(pitched(200), at: 0)
    stabilizer.reset()
    runner.isNil(stabilizer.process(gatedAnalysis(), at: 0.05).frequency, "reset clears the held value")
    runner.isNil(stabilizer.lastStableFrequency, "reset clears the last stable value")
}
