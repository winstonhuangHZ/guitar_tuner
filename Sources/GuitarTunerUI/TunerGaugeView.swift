import GuitarTunerKit
import SwiftUI

/// The tuning dial: an arc scale from -50 to +50 cents, an in-tune window, and a needle
/// that animates towards the measured deviation.
public struct TunerGaugeView: View {
    public var reading: TunerReading
    public var target: PitchTarget?
    public var toleranceCents: Double
    public var isActive: Bool
    /// Cents covered by the half scale.
    public var rangeCents: Double
    /// Sweep of the needle from -rangeCents to +rangeCents, in degrees.
    public var sweepDegrees: Double

    public init(
        reading: TunerReading,
        target: PitchTarget? = nil,
        toleranceCents: Double = 5,
        isActive: Bool = true,
        rangeCents: Double = 50,
        sweepDegrees: Double = 118
    ) {
        self.reading = reading
        self.target = target
        self.toleranceCents = toleranceCents
        self.isActive = isActive
        self.rangeCents = rangeCents
        self.sweepDegrees = sweepDegrees
    }

    private var direction: TunerReading.Direction {
        isActive ? reading.direction : .idle
    }

    private var tone: Color { TunerTheme.color(for: direction) }

    private var needleAngle: Double {
        reading.needleCents(limit: rangeCents) / rangeCents * sweepDegrees
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2 - 8

            ZStack {
                Canvas { context, _ in
                    drawScale(in: context, center: center, radius: radius)
                }
                spoke(radius: radius)
                readout(radius: radius)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Scale

    private func drawScale(in context: GraphicsContext, center: CGPoint, radius: Double) {
        let topAngle = -90.0
        let startAngle = topAngle - sweepDegrees
        let endAngle = topAngle + sweepDegrees

        // Track.
        let track = arcPath(center: center, radius: radius, from: startAngle, to: endAngle)
        context.stroke(
            track,
            with: .color(TunerTheme.track),
            style: StrokeStyle(lineWidth: radius * 0.075, lineCap: .round)
        )

        // In-tune window.
        let zone = arcPath(
            center: center,
            radius: radius,
            from: angle(forCents: -toleranceCents),
            to: angle(forCents: toleranceCents)
        )
        context.stroke(
            zone,
            with: .color(TunerTheme.inTune.opacity(direction == .inTune ? 0.95 : 0.30)),
            style: StrokeStyle(lineWidth: radius * 0.075, lineCap: .butt)
        )

        // Ticks and labels every 5 / 10 cents.
        for step in stride(from: -Int(rangeCents), through: Int(rangeCents), by: 5) {
            let isMajor = step % 10 == 0
            let tickAngle = angle(forCents: Double(step))
            let outer = point(angle: tickAngle, radius: radius - radius * 0.055, center: center)
            let inner = point(
                angle: tickAngle,
                radius: radius - radius * (isMajor ? 0.145 : 0.105),
                center: center
            )
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            context.stroke(
                tick,
                with: .color(Color.black.opacity(isMajor ? 0.42 : 0.15)),
                style: StrokeStyle(lineWidth: isMajor ? 2 : 1, lineCap: .round)
            )

            if isMajor {
                let labelPoint = point(angle: tickAngle, radius: radius - radius * 0.235, center: center)
                let label = Text("\(abs(step))")
                    .font(.system(size: max(9, radius * 0.075), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(step == 0 ? 0.70 : 0.32))
                context.draw(label, at: labelPoint, anchor: .center)
            }
        }
    }

    // MARK: - Needle

    private func spoke(radius: Double) -> some View {
        let length = radius * 0.33
        let inset = radius * 0.585

        return ZStack {
            NeedleShape()
                .fill(
                    LinearGradient(
                        colors: [tone, tone.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: radius * 0.115, height: length)
                .offset(y: -(inset + length / 2))
                .shadow(color: tone.opacity(direction == .inTune ? 0.85 : 0.45), radius: radius * 0.06)
        }
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(needleAngle))
        .animation(.interpolatingSpring(stiffness: 120, damping: 14), value: needleAngle)
        .opacity(isActive && reading.isSignalPresent ? 1 : 0.35)
    }

    // MARK: - Readout

    private func readout(radius: Double) -> some View {
        let noteName = reading.note?.description() ?? target?.note.description() ?? "—"
        let hasSignal = reading.isSignalPresent

        return VStack(spacing: radius * 0.02) {
            Text(noteName)
                .font(.system(size: radius * 0.46, weight: .semibold, design: .rounded))
                .foregroundStyle(hasSignal ? Color.primary : Color.black.opacity(0.22))
                .contentTransition(.numericText())
                .monospacedDigit()

            Text(targetLabel)
                .font(.system(size: radius * 0.085, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(TunerFormat.cents(hasSignal ? reading.cents : nil))
                .font(.system(size: radius * 0.115, weight: .semibold, design: .rounded))
                .foregroundStyle(hasSignal ? tone : Color.black.opacity(0.2))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(hasSignal ? TunerFormat.frequency(reading.frequency) : "play a string")
                .font(.system(size: radius * 0.08, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(width: radius * 1.02)
        .offset(y: radius * 0.06)
        .animation(.easeOut(duration: 0.18), value: reading.isSignalPresent)
    }

    private var targetLabel: String {
        if reading.isInTune, reading.isSignalPresent { return "in tune" }
        if let target { return target.detailedLabel }
        return "—"
    }

    // MARK: - Geometry helpers

    private func angle(forCents cents: Double) -> Double {
        -90 + (cents / rangeCents) * sweepDegrees
    }

    private func point(angle degrees: Double, radius: Double, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }

    /// Sampled arc path: explicit points avoid any confusion about arc direction in a
    /// flipped coordinate system.
    private func arcPath(center: CGPoint, radius: Double, from: Double, to: Double) -> Path {
        var path = Path()
        let steps = 64
        for step in 0...steps {
            let angle = from + (to - from) * Double(step) / Double(steps)
            let current = point(angle: angle, radius: radius, center: center)
            if step == 0 {
                path.move(to: current)
            } else {
                path.addLine(to: current)
            }
        }
        return path
    }
}

/// Tapered pointer used for the needle.
public struct NeedleShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY - height * 0.22))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - height * 0.22),
            control: CGPoint(x: rect.midX, y: rect.maxY + height * 0.1)
        )
        path.closeSubpath()
        return path
    }
}
