import Foundation
import GuitarTunerKit

/// A synthetic pluck: a short noisy pick attack followed by a decaying harmonic tone,
/// with a quiet room between notes.
private struct PluckSequence {
    var samples: [Float] = []
    /// Sample ranges where the string is actually ringing (the attack plus the body).
    var soundingRanges: [Range<Int>] = []
    var sampleRate: Double = 48_000

    init(
        fundamental: Double,
        plucks: Int,
        sampleRate: Double = 48_000,
        attackSeconds: Double = 0.05,
        ringSeconds: Double = 1.0,
        gapSeconds: Double = 0.35,
        attackAmplitude: Double = 0.19,
        bodyAmplitude: Double = 0.16,
        roomAmplitude: Double = 0.0006,
        seed: UInt64 = 20_260_918
    ) {
        self.sampleRate = sampleRate
        var random = CheckSignals.Random(seed: seed)
        let attackCount = Int(attackSeconds * sampleRate)
        let ringCount = Int(ringSeconds * sampleRate)
        let gapCount = Int(gapSeconds * sampleRate)
        let decay = 3.0

        for _ in 0..<plucks {
            let start = samples.count

            // Pick attack: broadband, no stable pitch — exactly the kind of frame the
            // detector reports as "loud but no frequency".
            for _ in 0..<attackCount {
                samples.append(Float(attackAmplitude * random.nextBipolar()))
            }

            // Body: harmonic tone decaying towards the room level.
            let step = 2 * Double.pi * fundamental / sampleRate
            for index in 0..<ringCount {
                let time = Double(index) / sampleRate
                let envelope = exp(-time * decay)
                var value = 0.0
                for (offset, weight) in [1.0, 0.75, 0.45, 0.28, 0.16].enumerated() {
                    value += weight * sin(step * Double(offset + 1) * Double(index))
                }
                samples.append(Float(bodyAmplitude * envelope * value / 2.6))
            }

            soundingRanges.append(start..<(start + attackCount + ringCount))

            // Room tone between notes.
            for _ in 0..<gapCount {
                samples.append(Float(roomAmplitude * random.nextBipolar()))
            }
        }
    }
}

/// Runs the real pipeline pieces (detector + adaptive gate + stabiliser) over the
/// sequence, exactly the way `AnalysisPipeline` does, and reports what came out.
private struct GateSimulation {
    struct Result {
        var detectedFrames: [Int] = []
        var frequencies: [Double] = []
        var gateAtEnd: Double = 0
        var floorAtEnd: Double = 0
        var firstPluckDetected = false
        var lastPluckDetected = false
        var soundingFrameCount = 0
        var gateAfterFirstPluck: Double = 0
    }

    static func run(
        sequence: PluckSequence,
        plucks: Int,
        configuration: PitchDetectionConfiguration = .default
    ) -> Result {
        var result = Result()
        var detector = PitchDetector(configuration: configuration)
        var stabilizer = PitchStabilizer()
        var estimator = NoiseFloorEstimator()

        let windowSize = configuration.analysisWindowSize
        let hop = Int(configuration.analysisWindowSize / 2) // 20 Hz-ish at 48 kHz
        var frame = [Float](repeating: 0, count: windowSize)
        var frameIndex = 0
        var offset = windowSize
        let soundingRanges = sequence.soundingRanges

        while offset <= sequence.samples.count {
            let start = offset - windowSize
            for index in 0..<windowSize { frame[index] = sequence.samples[start + index] }

            // Mirrors AnalysisPipeline: easier to keep a note than to start one.
            let clarity = stabilizer.isTracking
                ? configuration.retentionClarity
                : configuration.minimumClarity
            let analysis = detector.analyze(
                samples: frame,
                sampleRate: sequence.sampleRate,
                gate: estimator.gate,
                minimumClarity: clarity
            )
            estimator.update(rms: analysis.rms, isSignalPresent: analysis.frequency != nil)
            let stabilized = stabilizer.process(analysis, at: Double(frameIndex) * 0.05)

            let sounding = soundingRanges.contains { $0.contains(offset - 1) }
            if sounding { result.soundingFrameCount += 1 }

            if let frequency = stabilized.frequency {
                result.detectedFrames.append(frameIndex)
                result.frequencies.append(frequency)
                if frameIndex < 40, !result.firstPluckDetected { result.firstPluckDetected = true }
            }

            // Which pluck does this frame belong to?
            let pluckIndex = soundingRanges.firstIndex { $0.contains(offset - 1) }
            if let pluckIndex, pluckIndex == plucks - 1, stabilized.frequency != nil {
                result.lastPluckDetected = true
            }
            if let pluckIndex, pluckIndex == 0, frameIndex > 4 { result.gateAfterFirstPluck = estimator.gate }

            offset += hop
            frameIndex += 1
        }

        result.gateAtEnd = estimator.gate
        result.floorAtEnd = estimator.floor
        return result
    }
}

func runAdaptiveGateChecks(_ runner: CheckRunner) {
    runner.group("Adaptive gate")

    // MARK: A loud transient must never raise the gate

    var estimator = NoiseFloorEstimator()
    let restingGate = estimator.gate
    // Simulate the pick attack: loud, broadband, no pitch.
    for _ in 0..<30 {
        estimator.update(rms: 0.12, isSignalPresent: false)
    }
    runner.less(
        estimator.gate,
        restingGate * 4,
        "a loud unpitched attack does not inflate the gate (\(String(format: "%.5f", estimator.gate)) vs quiet \(String(format: "%.5f", restingGate)))"
    )

    // MARK: A steady louder room is still tracked

    estimator = NoiseFloorEstimator()
    for _ in 0..<600 {
        estimator.update(rms: 0.004, isSignalPresent: false)
    }
    runner.greater(
        estimator.gate,
        restingGate * 2,
        "a steady louder room raises the gate over time (\(String(format: "%.5f", estimator.gate)))"
    )
    runner.less(
        estimator.gate,
        estimator.maximumFloor * 1.01,
        "the gate respects its ceiling"
    )

    // MARK: The gate falls back down with the room

    for _ in 0..<200 {
        estimator.update(rms: 0.0004, isSignalPresent: false)
    }
    runner.less(estimator.floor, 0.001, "the floor follows the room down again")

    // MARK: Repeated plucks keep working

    let plucks = 8
    let sequence = PluckSequence(fundamental: 82.4069, plucks: plucks)
    let simulation = GateSimulation.run(sequence: sequence, plucks: plucks)

    runner.expect(simulation.firstPluckDetected, "the first pluck is detected")
    runner.expect(
        simulation.lastPluckDetected,
        "the last of \(plucks) plucks is still detected (gate \(String(format: "%.5f", simulation.gateAtEnd)) vs floor \(String(format: "%.5f", simulation.floorAtEnd)))"
    )
    runner.less(
        simulation.gateAtEnd,
        0.01,
        "the gate stays well below playing level after \(plucks) plucks (gate \(String(format: "%.5f", simulation.gateAtEnd)))"
    )

    let coverage = Double(simulation.detectedFrames.count) / Double(max(simulation.soundingFrameCount, 1))
    runner.greater(coverage, 0.85, "most of the ringing time produces a reading (coverage \(String(format: "%.2f", coverage)))")

    let offPitch = simulation.frequencies.filter { abs(NoteMath.cents(from: $0, to: 82.4069)) > 40 }
    runner.equal(offPitch.count, 0, "every reading stays within 40 cents of the string")
}
