import GuitarTunerKit
import SwiftUI

/// Last few seconds of tuning deviation — turns a jittery needle into a trend the
/// player can actually read ("the string is settling onto pitch").
public struct TuningHistoryView: View {
    public var samples: [TunerController.HistorySample]
    public var toleranceCents: Double
    public var rangeCents: Double

    public init(samples: [TunerController.HistorySample], toleranceCents: Double = 5, rangeCents: Double = 50) {
        self.samples = samples
        self.toleranceCents = toleranceCents
        self.rangeCents = rangeCents
    }

    public var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let halfHeight = size.height / 2
            let count = max(samples.count, 2)
            let stepX = size.width / CGFloat(count - 1)

            // Tolerance band.
            let bandHeight = CGFloat(toleranceCents / rangeCents) * halfHeight * 2
            let band = CGRect(x: 0, y: midY - bandHeight / 2, width: size.width, height: bandHeight)
            context.fill(Path(band), with: .color(TunerTheme.inTune.opacity(0.14)))

            // Centre line.
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: midY))
            axis.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(axis, with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            guard samples.count > 1 else { return }

            var path = Path()
            var lastPoint = CGPoint.zero
            var lastCents = 0.0
            for (index, sample) in samples.enumerated() {
                let clamped = min(max(sample.cents, -rangeCents), rangeCents)
                let y = midY - CGFloat(clamped / rangeCents) * halfHeight
                let x = CGFloat(index) * stepX
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
                lastPoint = point
                lastCents = clamped
            }

            let tone = abs(lastCents) <= toleranceCents ? TunerTheme.inTune : TunerTheme.color(for: lastCents < 0 ? .flat : .sharp)
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [tone.opacity(0.35), tone]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            let marker = Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6))
            context.fill(marker, with: .color(tone))
        }
        .frame(height: 64)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
