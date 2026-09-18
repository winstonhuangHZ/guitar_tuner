import Foundation
import GuitarTunerKit

func runSignalMetricsChecks(_ runner: CheckRunner) {
    runner.group("Signal metrics")

    let samples = CheckSignals.sine(frequency: 200, sampleRate: 48_000, count: 4800, amplitude: 0.5)
    // RMS of a sine is amplitude / sqrt(2).
    runner.near(SignalMetrics.rms(samples), 0.5 / 2.0.squareRoot(), accuracy: 0.01, "sine RMS")
    runner.near(SignalMetrics.decibels(fromRMS: 1.0), 0, accuracy: 1e-9, "0 dBFS")
    runner.near(SignalMetrics.decibels(fromRMS: 0.5), -6.02, accuracy: 0.01, "half scale")
    runner.expect(!SignalMetrics.decibels(fromRMS: 0).isFinite, "silence is -inf dBFS")
    runner.near(SignalMetrics.normalizedLevel(rms: 1.0), 1, accuracy: 1e-9, "level ceiling")
    runner.near(SignalMetrics.normalizedLevel(rms: 0), 0, accuracy: 1e-9, "level floor")
    runner.near(SignalMetrics.normalizedLevel(rms: 0.001), 0, accuracy: 1e-9, "very quiet level")

    // The adaptive floor rises towards the room and falls back slowly.
    var estimator = NoiseFloorEstimator()
    let startGate = estimator.gate
    for _ in 0..<40 {
        estimator.update(rms: 0.02, isSignalPresent: false)
    }
    runner.greater(estimator.gate, startGate * 10, "gate follows ambient noise")
    runner.lessOrEqual(estimator.floor, estimator.maximumFloor, "floor is bounded")

    let raised = estimator.floor
    for _ in 0..<200 {
        estimator.update(rms: 0.001, isSignalPresent: true)
    }
    runner.less(estimator.floor, raised, "floor drifts back down")

    for _ in 0..<200 {
        estimator.update(rms: 5.0, isSignalPresent: false)
    }
    runner.lessOrEqual(estimator.floor, estimator.maximumFloor, "floor clamps at the ceiling")

    estimator.reset()
    runner.near(estimator.floor, estimator.initialFloor, accuracy: 1e-12, "reset restores the initial floor")
}
