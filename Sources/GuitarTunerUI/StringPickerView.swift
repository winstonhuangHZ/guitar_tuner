import GuitarTunerKit
import SwiftUI

/// Target selector: "Auto" plus one chip per string of the current preset.
///
/// Locking a string is the reliable way to tune: the needle then only compares against
/// that one string instead of hopping to a neighbour when the pitch drifts.
public struct StringPickerView: View {
    public var preset: TuningPreset
    public var selection: StringSelection
    public var referencePitch: Double
    /// String currently detected by the tuner, highlighted subtly.
    public var detectedStringID: Int?
    public var onSelect: (StringSelection) -> Void

    public init(
        preset: TuningPreset,
        selection: StringSelection,
        referencePitch: Double,
        detectedStringID: Int?,
        onSelect: @escaping (StringSelection) -> Void
    ) {
        self.preset = preset
        self.selection = selection
        self.referencePitch = referencePitch
        self.detectedStringID = detectedStringID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Target").tunerSectionTitle()
                Spacer()
                Text(preset.isChromatic ? "chromatic — nearest semitone" : preset.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(
                        title: "Auto",
                        subtitle: preset.isChromatic ? "note" : "any string",
                        isSelected: selection == .automatic,
                        isDetected: false,
                        action: { onSelect(.automatic) }
                    )

                    ForEach(preset.strings) { string in
                        chip(
                            title: string.noteName,
                            subtitle: String(format: "%.1f", string.frequency(referencePitch: referencePitch)),
                            isSelected: selection == .locked(string.id),
                            isDetected: detectedStringID == string.id,
                            action: { onSelect(.locked(string.id)) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(
        title: String,
        subtitle: String,
        isSelected: Bool,
        isDetected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.black.opacity(0.6) : .secondary)
            }
            .frame(minWidth: 58)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? TunerTheme.accent : Color.white.opacity(isDetected ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDetected ? TunerTheme.inTune.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: isDetected ? 2 : 1
                    )
            )
            .foregroundStyle(isSelected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
