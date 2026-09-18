import GuitarTunerKit
import SwiftUI

/// Log-frequency spectrum of the *filtered* input — the same signal the detector sees.
///
/// The fundamental and its first harmonics are marked, which makes the reason for the
/// input filters visible: in Pickup mode the upper bars flatten out, and it is obvious
/// why the detector no longer has to guess between the fundamental and a loud 2nd
/// harmonic.
public struct SpectrumView: View {
    public var snapshot: SpectrumSnapshot
    /// Detected fundamental; markers are drawn for it and its harmonics.
    public var fundamental: Double?
    public var harmonicCount: Int
    public var isActive: Bool
    /// Shown while there is nothing to draw yet.
    public var placeholder: String

    public init(
        snapshot: SpectrumSnapshot,
        fundamental: Double? = nil,
        harmonicCount: Int = 6,
        isActive: Bool = true,
        placeholder: String = "waiting for audio"
    ) {
        self.snapshot = snapshot
        self.fundamental = fundamental
        self.harmonicCount = max(1, harmonicCount)
        self.isActive = isActive
        self.placeholder = placeholder
    }

    private let labelHeight: CGFloat = 16

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: context, size: size)
            }
        }
        .frame(height: 132)
        .tunerInset()
        .opacity(isActive ? 1 : 0.45)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let barHeight = max(0, size.height - labelHeight)
        guard barHeight > 0 else { return }

        let levels = snapshot.levels

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: barHeight))
        baseline.addLine(to: CGPoint(x: size.width, y: barHeight))
        context.stroke(baseline, with: .color(Color.black.opacity(0.10)), lineWidth: 1)

        guard !levels.isEmpty else {
            context.draw(
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.30)),
                at: CGPoint(x: size.width / 2, y: barHeight / 2),
                anchor: .center
            )
            return
        }

        drawBars(in: context, levels: levels, size: size, barHeight: barHeight)
        drawHarmonicMarkers(in: context, size: size, barHeight: barHeight)
        drawFrequencyAxis(in: context, size: size, barHeight: barHeight)
    }

    private func drawBars(in context: GraphicsContext, levels: [Float], size: CGSize, barHeight: CGFloat) {
        let binWidth = size.width / CGFloat(levels.count)
        let barWidth = max(1, binWidth - 1)
        for (index, level) in levels.enumerated() {
            let height = CGFloat(level) * barHeight
            guard height > 0.5 else { continue }
            let rect = CGRect(
                x: CGFloat(index) * binWidth,
                y: barHeight - height,
                width: barWidth,
                height: height
            )
            let opacity = 0.30 + 0.62 * Double(level)
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2)),
                with: .color(TunerTheme.accent.opacity(opacity))
            )
        }
    }

    private func drawHarmonicMarkers(in context: GraphicsContext, size: CGSize, barHeight: CGFloat) {
        guard let fundamental, fundamental > 0 else { return }

        for harmonic in 1...harmonicCount {
            let frequency = fundamental * Double(harmonic)
            guard let position = snapshot.position(forFrequency: frequency) else { continue }
            let x = position * size.width

            var marker = Path()
            marker.move(to: CGPoint(x: x, y: 0))
            marker.addLine(to: CGPoint(x: x, y: barHeight))

            if harmonic == 1 {
                context.stroke(
                    marker,
                    with: .color(TunerTheme.inTune.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1.5)
                )
                let label = Text(TunerFormat.frequency(fundamental))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(TunerTheme.inTune)
                context.draw(
                    label,
                    at: CGPoint(x: min(max(x, 26), size.width - 26), y: 7),
                    anchor: .center
                )
            } else {
                context.stroke(
                    marker,
                    with: .color(Color.black.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
            }
        }
    }

    private func drawFrequencyAxis(in context: GraphicsContext, size: CGSize, barHeight: CGFloat) {
        for frequency in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000] {
            guard let position = snapshot.position(forFrequency: frequency) else { continue }
            let x = position * size.width

            var tick = Path()
            tick.move(to: CGPoint(x: x, y: barHeight))
            tick.addLine(to: CGPoint(x: x, y: barHeight + 4))
            context.stroke(tick, with: .color(Color.black.opacity(0.20)), lineWidth: 1)

            let text = frequency >= 1000
                ? "\(Int(frequency / 1000))k"
                : "\(Int(frequency))"
            context.draw(
                Text(text)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42)),
                at: CGPoint(x: min(max(x, 8), size.width - 8), y: barHeight + 10),
                anchor: .center
            )
        }
    }
}
