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
/// single hard-coded threshold. Ambient noise pushes the floor up quickly; the floor
/// only creeps back down while a real signal is present, which keeps the gate stable
/// during sustained notes.
public struct NoiseFloorEstimator: Sendable, Equatable {
    public var initialFloor: Double
    public var minimumFloor: Double
    public var maximumFloor: Double
    public var multiplier: Double
    /// How fast the floor follows the room while the gate is closed.
    public var attackRate: Double
    /// How fast the floor drifts back down while a signal is present.
    public var releaseRate: Double

    public private(set) var floor: Double

    public init(
        initialFloor: Double = 0.0015,
        minimumFloor: Double = 0.00002,
        maximumFloor: Double = 0.06,
        multiplier: Double = 3.0,
        attackRate: Double = 0.05,
        releaseRate: Double = 0.0008
    ) {
        self.initialFloor = initialFloor
        self.minimumFloor = minimumFloor
        self.maximumFloor = maximumFloor
        self.multiplier = multiplier
        self.attackRate = attackRate
        self.releaseRate = releaseRate
        self.floor = initialFloor
    }

    /// Current RMS gate: adaptive floor scaled by `multiplier`.
    public var gate: Double {
        min(max(floor * multiplier, minimumFloor), maximumFloor)
    }

    /// Feeds one frame of measured RMS back into the estimator.
    public mutating func update(rms: Double, isSignalPresent: Bool) {
        guard rms.isFinite, rms >= 0 else { return }
        let rate = isSignalPresent ? releaseRate : attackRate
        floor += (rms - floor) * rate
        floor = min(max(floor, minimumFloor), maximumFloor)
    }

    public mutating func reset() {
        floor = initialFloor
    }
}
