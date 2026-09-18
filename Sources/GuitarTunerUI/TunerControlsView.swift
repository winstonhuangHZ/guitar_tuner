import GuitarTunerKit
import SwiftUI

/// Settings card: input mode, tuning preset, reference pitch and in-tune window.
public struct TunerControlsView: View {
    @Bindable public var controller: TunerController

    public init(controller: TunerController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            inputSection
            presetSection
            referencePitchSection
            toleranceSection
            filterReadout
        }
    }

    // MARK: - Input mode

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input").tunerSectionTitle()
            Picker("Input mode", selection: $controller.inputMode) {
                ForEach(AudioInputMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(controller.inputMode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Preset

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tuning").tunerSectionTitle()
            Menu {
                ForEach(TuningPreset.groups, id: \.instrument) { group in
                    Section(group.instrument) {
                        ForEach(group.presets) { preset in
                            Button {
                                controller.preset = preset
                            } label: {
                                if controller.preset.id == preset.id {
                                    Label(preset.name, systemImage: "checkmark")
                                } else {
                                    Text(preset.name)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tuningfork")
                        .foregroundStyle(TunerTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(controller.preset.name)
                            .font(.system(.body, design: .rounded).weight(.medium))
                        Text(presetDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var presetDetail: String {
        let preset = controller.preset
        if preset.isChromatic { return "Tracks the nearest semitone" }
        let names = preset.strings.map(\.noteName).joined(separator: " · ")
        return "\(preset.instrument) — \(names)"
    }

    // MARK: - Reference pitch

    private var referencePitchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reference pitch").tunerSectionTitle()
                Spacer()
                Text(TunerFormat.referencePitch(controller.referencePitch))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if controller.referencePitch != NoteMath.defaultReferencePitch {
                    Button("440") { controller.referencePitch = NoteMath.defaultReferencePitch }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(TunerTheme.accent)
                }
            }
            Slider(value: $controller.referencePitch, in: 415...466, step: 1)
                .tint(TunerTheme.accent)
        }
    }

    // MARK: - Tolerance

    private var toleranceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("In-tune window").tunerSectionTitle()
                Spacer()
                Text(String(format: "±%.0f ¢", controller.inTuneToleranceCents))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $controller.inTuneToleranceCents, in: 1...15, step: 1)
                .tint(TunerTheme.inTune)
        }
    }

    // MARK: - Filter readout

    private var filterReadout: some View {
        let profile = controller.activeProfile
        let highPass = profile.highPassFrequency.map { String(format: "%.0f Hz", $0) } ?? "off"
        let lowPass = profile.lowPassFrequency.map { String(format: "%.0f Hz", $0) } ?? "off"
        return VStack(alignment: .leading, spacing: 4) {
            Divider().opacity(0.3)
            Text(
                "Filters — high-pass \(highPass), low-pass \(lowPass) · detector "
                    + "\(Int(profile.minFrequency))–\(Int(profile.maxFrequency)) Hz"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
