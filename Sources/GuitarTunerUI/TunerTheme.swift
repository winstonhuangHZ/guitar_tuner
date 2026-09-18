import GuitarTunerKit
import SwiftUI

/// Light palette.
///
/// A tuner gets used on a music stand in daylight, so the page is white and every accent
/// is a saturated colour that stays legible on it. Views never hard-code `Color.white`
/// for chrome — they use the semantic tokens below, which keeps a future dark appearance
/// a one-file change.
public enum TunerTheme {
    // MARK: Accents

    /// Too low.
    public static let flat = Color(red: 0.11, green: 0.44, blue: 0.90)
    /// Too high.
    public static let sharp = Color(red: 0.87, green: 0.34, blue: 0.05)
    /// In tune.
    public static let inTune = Color(red: 0.04, green: 0.60, blue: 0.34)
    /// No signal.
    public static let idle = Color(white: 0.62)
    public static let accent = Color(red: 0.09, green: 0.44, blue: 0.90)

    // MARK: Surfaces

    /// Page background: white with the faintest grey so white cards still read as cards.
    public static let canvas = Color(red: 0.972, green: 0.975, blue: 0.980)
    public static let surface = Color.white
    /// Unfilled meter / gauge track.
    public static let track = Color.black.opacity(0.07)
    /// Card and control outlines.
    public static let hairline = Color.black.opacity(0.10)
    /// Inset areas (spectrum, history, chips).
    public static let subtleFill = Color.black.opacity(0.035)
    /// Text on top of `accent`.
    public static let onAccent = Color.white
    /// Text and marks drawn directly on the page.
    public static let onCanvas = Color.black

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
        canvas.ignoresSafeArea()
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
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TunerTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(TunerTheme.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    func tunerSectionTitle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
    }

    /// Inset panel used inside a card (spectrum, history, chips).
    func tunerInset(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(TunerTheme.subtleFill)
        )
    }
}
