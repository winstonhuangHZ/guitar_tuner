import Foundation

/// Deterministic signal generators: a failing check is always a detector problem and
/// never a flaky seed.
enum CheckSignals {
    /// SplitMix64 — small, fast, reproducible.
    struct Random {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53)
        }

        /// Uniform in -1...1.
        mutating func nextBipolar() -> Double {
            nextUnit() * 2 - 1
        }
    }

    static func sine(
        frequency: Double,
        sampleRate: Double,
        count: Int,
        amplitude: Double = 0.3,
        phase: Double = 0
    ) -> [Float] {
        let step = 2 * Double.pi * frequency / sampleRate
        return (0..<count).map { index in
            Float(amplitude * sin(step * Double(index) + phase))
        }
    }

    /// Sum of a fundamental plus weighted harmonics — the shape of a plucked string.
    static func harmonicTone(
        fundamental: Double,
        amplitude: Double = 0.3,
        harmonics: [Double],
        sampleRate: Double,
        count: Int,
        decay: Double = 0
    ) -> [Float] {
        let total = max(harmonics.reduce(0, +), 1e-9)
        let step = 2 * Double.pi * fundamental / sampleRate
        return (0..<count).map { index in
            let time = Double(index) / sampleRate
            let envelope = decay > 0 ? exp(-time * decay) : 1
            var value = 0.0
            for (offset, weight) in harmonics.enumerated() {
                let harmonic = Double(offset + 1)
                value += weight / total * sin(step * harmonic * Double(index))
            }
            return Float(amplitude * envelope * value)
        }
    }

    static func whiteNoise(count: Int, amplitude: Double, seed: UInt64) -> [Float] {
        var random = Random(seed: seed)
        return (0..<count).map { _ in Float(amplitude * random.nextBipolar()) }
    }

    static func mix(_ lhs: [Float], _ rhs: [Float], scale: Double = 1) -> [Float] {
        zip(lhs, rhs).map { Float(Double($0) + Double($1) * scale) }
    }

    /// Frequency ratio for a deviation in cents, e.g. `+12 ¢` → 1.006956.
    static func ratio(forCents cents: Double) -> Double {
        pow(2.0, cents / 1200.0)
    }
}
