import GuitarTunerKit
import SwiftUI

/// Input level with the live RMS gate drawn on top, plus the detector's clarity.
///
/// Showing the gate matters: if the meter never reaches the marker, the tuner is
/// deliberately ignoring the signal, and the player knows to play louder or move closer.
public struct LevelMeterView: View {
    public var level: Double
    public var rms: Double
    public var gate: Double
    public var clarity: Double
    public var isSignalPresent: Bool

    public init(level: Double, rms: Double, gate: Double, clarity: Double, isSignalPresent: Bool) {
        self.level = level
        self.rms = rms
        self.gate = gate
        self.clarity = clarity
        self.isSignalPresent = isSignalPresent
    }

    private var gatePosition: Double {
        min(max(SignalMetrics.normalizedLevel(rms: gate), 0), 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input level").tunerSectionTitle()
                Spacer()
                Text(TunerFormat.decibels(rms: rms))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSignalPresent ? .primary : .secondary)
                if isSignalPresent {
                    Text("· clarity \(Int((clarity * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(clarity >= 0.75 ? TunerTheme.inTune : .secondary)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TunerTheme.track)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TunerTheme.accent, TunerTheme.inTune, TunerTheme.sharp],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(level, 1)) * width)
                        .animation(.linear(duration: 0.08), value: level)

                    // RMS gate marker.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 2, height: 16)
                        .offset(x: gatePosition * width - 1)
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            HStack {
                Text("gate \(TunerFormat.decibels(rms: gate))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-60 dB")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
