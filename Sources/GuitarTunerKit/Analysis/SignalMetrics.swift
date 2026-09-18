import Foundation

#if canImport(Accelerate)
import Accelerate
#endif

/// Small vector helpers used by the DSP core. Accelerate is used when available so the
/// per-frame cost stays comfortably inside a background analysis loop.
enum VectorMath {
    @inline(__always)
    static func dot(_ samples: [Float], _ lhsOffset: Int, _ rhsOffset: Int, count: Int) -> Float {
        guard count > 0 else { return 0 }
        return samples.withUnsafeBufferPointer { buffer -> Float in
            guard let base = buffer.baseAddress else { return 0 }
            return dot(base + lhsOffset, base + rhsOffset, count: count)
        }
    }

    @inline(__always)
    static func dot(_ lhs: UnsafePointer<Float>, _ rhs: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        #if canImport(Accelerate)
        var result: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &result, vDSP_Length(count))
        return result
        #else
        var result: Float = 0
        for index in 0..<count {
            result += lhs[index] * rhs[index]
        }
        return result
        #endif
    }
}

/// Level measurements shared by the detector and the level meter UI.
public enum SignalMetrics {
    /// Root-mean-square amplitude of a sample window (0...1 for full-scale floats).
    public static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares: Float = samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return VectorMath.dot(base, base, count: buffer.count)
        }
        return Double((sumOfSquares / Float(samples.count)).squareRoot())
    }

    /// Level in dBFS; `-infinity` for digital silence.
    public static func decibels(fromRMS rms: Double) -> Double {
        guard rms > 0 else { return -.infinity }
        return 20.0 * log10(rms)
    }

    /// Maps RMS onto a 0...1 meter value with a logarithmic (dBFS) response.
    public static func normalizedLevel(
        rms: Double,
        floorDecibels: Double = -60,
        ceilingDecibels: Double = -3
    ) -> Double {
        let decibels = decibels(fromRMS: rms)
        guard decibels.isFinite else { return 0 }
        let span = ceilingDecibels - floorDecibels
        guard span > 0 else { return 0 }
        return min(max((decibels - floorDecibels) / span, 0), 1)
    }
}

/// Tracks the ambient noise floor so the RMS gate follows the room instead of using a
/// single hard-coded threshold.
///
/// The rule that makes this safe for a tuner: **only levels close to the quietest recent
/// level may raise the floor.** A plucked string is loud, and its attack is broadband and
/// often unpitched, so a naive "follow the RMS while no pitch is detected" estimator
/// climbs to the note level within a second or two — the gate then sits above the
/// instrument and the tuner goes deaf after a few strums. Keeping the rise anchored to
/// the quiet level means notes can only ever *lower* the estimate (through their decay
/// tails and the gaps between them), which is exactly the information we want.
public struct NoiseFloorEstimator: Sendable, Equatable {
    public var initialFloor: Double
    public var minimumFloor: Double
    public var maximumFloor: Double
    /// Gate = floor x multiplier.
    public var multiplier: Double
    /// A frame may only raise the floor while it is quieter than the ambient estimate
    /// times this factor (~9.5 dB at the default).
    public var ambientHeadroom: Double
    /// How fast the floor follows the room *down*.
    public var descentRate: Double
    /// How fast the floor creeps *up* towards a steadily louder room.
    public var ascentRate: Double
    /// How quickly the tracked quiet level forgets one unusually quiet moment.
    public var quietDriftRate: Double

    public private(set) var floor: Double
    /// Quietest recent frame — the ambient estimate the floor is allowed to approach.
    public private(set) var quietLevel: Double

    public init(
        initialFloor: Double = 0.001,
        minimumFloor: Double = 0.0005,
        maximumFloor: Double = 0.05,
        multiplier: Double = 3.0,
        ambientHeadroom: Double = 3.0,
        descentRate: Double = 0.25,
        ascentRate: Double = 0.02,
        quietDriftRate: Double = 0.002
    ) {
        self.initialFloor = initialFloor
        self.minimumFloor = minimumFloor
        self.maximumFloor = maximumFloor
        self.multiplier = multiplier
        self.ambientHeadroom = ambientHeadroom
        self.descentRate = descentRate
        self.ascentRate = ascentRate
        self.quietDriftRate = quietDriftRate
        self.floor = initialFloor
        self.quietLevel = initialFloor
    }

    /// Current RMS gate: adaptive floor scaled by `multiplier`.
    public var gate: Double {
        min(max(floor * multiplier, minimumFloor), maximumFloor)
    }

    /// Feeds one frame of measured RMS back into the estimator.
    public mutating func update(rms: Double, isSignalPresent: Bool) {
        guard rms.isFinite, rms >= 0 else { return }

        if rms < quietLevel {
            quietLevel = rms
        } else {
            quietLevel += (rms - quietLevel) * quietDriftRate
        }

        if rms < floor {
            // The room got quieter (or a note decayed into the noise): follow it down
            // promptly so quiet playing still registers.
            floor += (rms - floor) * descentRate
        } else if !isSignalPresent, rms <= quietLevel * ambientHeadroom {
            // Steady, near-ambient level: this is the room getting louder.
            floor += (rms - floor) * ascentRate
        }
        // Anything else is a note (or a transient): it must not raise the gate.

        floor = min(max(floor, minimumFloor), maximumFloor)
        quietLevel = min(max(quietLevel, minimumFloor), maximumFloor)
    }

    public mutating func reset() {
        floor = initialFloor
        quietLevel = initialFloor
    }
}
