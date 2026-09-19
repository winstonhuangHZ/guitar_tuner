import GuitarTunerKit
import SwiftUI

/// Settings: input device, capo, reference pitch, tolerance and the tuning history.
public struct SettingsView: View {
    @Bindable public var controller: TunerController
    @Environment(\.dismiss) private var dismiss

    public init(controller: TunerController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            TunerTheme.background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    inputCard
                    capoCard
                    tuningCard
                    historyCard
                    aboutCard
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Input").tunerSectionTitle()
                Spacer()
                Button("Rescan") { controller.refreshInputDevices() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if controller.availableInputDevices.isEmpty {
                Text("No capture devices found. Using the system default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Input device",
                    selection: Binding(
                        get: { controller.selectedInputDeviceID ?? "" },
                        set: { controller.selectInputDevice(id: $0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("System default").tag("")
                    ForEach(controller.availableInputDevices) { device in
                        Text(device.isDefault ? "\(device.name) (default)" : device.name)
                            .tag(device.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Text("Switching device restarts the audio engine, because the hardware format changes with it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .tunerCard()
    }

    private var capoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capo").tunerSectionTitle()
                Spacer()
                Text(controller.capoFret == 0 ? "none" : "fret \(controller.capoFret)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("−") { controller.capoFret = max(controller.capoFret - 1, 0) }
                    .buttonStyle(.bordered)
                Stepper("", value: Binding(
                    get: { controller.capoFret },
                    set: { controller.capoFret = $0 }
                ), in: 0...TuningPreset.maximumCapoFret)
                .labelsHidden()
                Button("+") { controller.capoFret = min(controller.capoFret + 1, TuningPreset.maximumCapoFret) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Clear") { controller.capoFret = 0 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if controller.capoFret > 0 {
                Text(capoExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tunerCard()
    }

    private var capoExplanation: String {
        let strings = controller.preset.strings(capoFret: controller.capoFret)
        let names = strings.map(\.noteName).joined(separator: " ")
        return "Targets move up with the capo: \(names). Use the shapes you already know and the tuner follows the sound."
    }

    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tuning").tunerSectionTitle()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Reference pitch").font(.callout)
                    Spacer()
                    Text(TunerFormat.referencePitch(controller.referencePitch))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { controller.referencePitch },
                        set: { controller.referencePitch = $0 }
                    ),
                    in: 415...466,
                    step: 1
                )
                .tint(TunerTheme.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("In-tune window").font(.callout)
                    Spacer()
                    Text(String(format: "±%.0f ¢", controller.inTuneToleranceCents))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { controller.inTuneToleranceCents },
                        set: { controller.inTuneToleranceCents = $0 }
                    ),
                    in: 1...15,
                    step: 1
                )
                .tint(TunerTheme.inTune)
            }
        }
        .tunerCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tuning history").tunerSectionTitle()
            Toggle(
                "Remember how each string drifts",
                isOn: Binding(
                    get: { controller.isRecordingHistory },
                    set: { controller.setHistoryRecording($0) }
                )
            )
            .toggleStyle(.switch)

            Text("\(controller.tuningHistorySummary.sampleCount) samples recorded on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Clear history") { controller.clearTuningHistory() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .tunerCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About").tunerSectionTitle()
            Text("Audio is analysed on device, never recorded and never uploaded. Settings and tuning history stay in this app's local storage.")
            if controller.sampleRate > 0 {
                Text(String(format: "Input format: %.1f kHz", controller.sampleRate / 1000))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .tunerCard()
    }
}
