import GuitarTunerKit
import SwiftUI

/// Colours and shared styling for the tuner UI.
public enum TunerTheme {
    /// Too low.
    public static let flat = Color(red: 0.36, green: 0.71, blue: 1.00)
    /// Too high.
    public static let sharp = Color(red: 1.00, green: 0.58, blue: 0.28)
    /// In tune.
    public static let inTune = Color(red: 0.29, green: 0.87, blue: 0.55)
    /// No signal.
    public static let idle = Color.white.opacity(0.55)
    public static let accent = Color(red: 0.42, green: 0.78, blue: 1.00)

    public static func color(for direction: TunerReading.Direction) -> Color {
        switch direction {
        case .flat: flat
        case .sharp: sharp
        case .inTune: inTune
        case .idle: idle
        }
    }

    @ViewBuilder
    public static var background: some View {
        ZStack {
            Color(red: 0.043, green: 0.051, blue: 0.075)
            RadialGradient(
                colors: [accent.opacity(0.20), accent.opacity(0.04), .clear],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 8,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

public enum TunerFormat {
    public static func frequency(_ hertz: Double?) -> String {
        guard let hertz, hertz.isFinite, hertz > 0 else { return "—" }
        return String(format: "%.2f Hz", hertz)
    }

    public static func cents(_ cents: Double?) -> String {
        guard let cents, cents.isFinite else { return "—" }
        return String(format: "%+.1f ¢", cents)
    }

    public static func decibels(rms: Double) -> String {
        let value = SignalMetrics.decibels(fromRMS: rms)
        guard value.isFinite else { return "−∞ dBFS" }
        return String(format: "%.0f dBFS", value)
    }

    public static func referencePitch(_ hertz: Double) -> String {
        String(format: "A4 = %.0f Hz", hertz)
    }
}

public extension View {
    func tunerCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    func tunerSectionTitle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}
