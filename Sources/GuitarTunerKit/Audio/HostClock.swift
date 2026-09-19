import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Conversions for host time, so views can line visuals up with scheduled audio without
/// importing AVFoundation themselves.
public enum HostClock {
    /// Current host time, same base as `MetronomeBeat.hostTime`.
    public static var now: UInt64 { mach_absolute_time() }

    /// Seconds elapsed between two host times.
    public static func seconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        #if canImport(AVFoundation)
        return AVAudioTime.seconds(forHostTime: end - start)
        #else
        return Double(end - start) / 1_000_000_000
        #endif
    }
}
