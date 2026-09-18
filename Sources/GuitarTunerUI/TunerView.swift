import GuitarTunerKit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The full tuner screen, shared by the iOS and macOS apps.
public struct TunerView: View {
    @Bindable public var controller: TunerController
    @Environment(\.scenePhase) private var scenePhase
    /// Set when the app is backgrounded while listening, so the engine can be released
    /// (microphone indicator off, no idle capture) and brought back on return.
    @State private var resumeWhenActive = false

    public init(controller: TunerController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            TunerTheme.background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let message = statusMessage {
                        statusBanner(message)
                    }
                    gauge
                    primaryButton
                    LevelMeterView(
                        level: controller.reading.level,
                        rms: controller.reading.rms,
                        gate: controller.reading.gate,
                        clarity: controller.reading.clarity,
                        isSignalPresent: controller.reading.isSignalPresent
                    )
                    .tunerCard()
                    spectrumCard
                    historyCard
                    StringPickerView(
                        preset: controller.preset,
                        selection: controller.stringSelection,
                        referencePitch: controller.referencePitch,
                        detectedStringID: controller.reading.target?.kind.string?.id,
                        onSelect: { controller.stringSelection = $0 }
                    )
                    .tunerCard()
                    TunerControlsView(controller: controller)
                        .tunerCard()
                    footer
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            await controller.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                resumeWhenActive = controller.isRunning
                controller.stop()
            case .active:
                guard resumeWhenActive else { return }
                resumeWhenActive = false
                Task { await controller.start() }
            default:
                break
            }
        }
        .onDisappear {
            controller.stop()
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 720)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guitar Tuner")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("\(controller.inputMode.displayName) mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let tone: Color = switch controller.status {
        case .running: TunerTheme.inTune
        case .requestingPermission: TunerTheme.accent
        case .permissionDenied, .failed: TunerTheme.sharp
        case .idle: TunerTheme.idle
        }

        return HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(TunerTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.opacity(0.35), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private var statusText: String {
        switch controller.status {
        case .idle: "Paused"
        case .requestingPermission: "Requesting access"
        case .running: "Listening"
        case .permissionDenied: "No access"
        case .failed: "Error"
        }
    }

    private var gauge: some View {
        TunerGaugeView(
            reading: controller.reading,
            target: controller.displayTarget,
            toleranceCents: controller.inTuneToleranceCents,
            isActive: controller.isRunning
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(
                colors: [
                    TunerTheme.color(for: controller.reading.direction).opacity(controller.reading.isInTune ? 0.16 : 0.05),
                    .clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
        )
    }

    private var primaryButton: some View {
        Button {
            Task { await controller.toggle() }
        } label: {
            HStack(spacing: 8) {
                if controller.status == .requestingPermission {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: controller.isRunning ? "stop.fill" : "waveform")
                }
                Text(controller.isRunning ? "Stop listening" : "Start tuning")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(controller.isRunning ? TunerTheme.surface : TunerTheme.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        controller.isRunning ? TunerTheme.hairline : Color.clear,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(controller.isRunning ? Color.primary : TunerTheme.onAccent)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Stability").tunerSectionTitle()
                Spacer()
                Text("last 5 s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            TuningHistoryView(
                samples: controller.history,
                toleranceCents: controller.inTuneToleranceCents
            )
        }
        .tunerCard()
    }

    private var spectrumCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spectrum").tunerSectionTitle()
                Spacer()
                Text(spectrumDetail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            SpectrumView(
                snapshot: controller.spectrum,
                fundamental: controller.reading.frequency,
                isActive: controller.isRunning,
                placeholder: spectrumPlaceholder
            )
            HStack(spacing: 12) {
                Label("fundamental", systemImage: "line.diagonal")
                    .foregroundStyle(TunerTheme.inTune)
                Label("harmonics", systemImage: "line.diagonal")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption2)
        }
        .tunerCard()
    }

    private var spectrumDetail: String {
        guard let peak = controller.spectrum.peakFrequency else {
            return "filtered input"
        }
        return "strongest partial \(TunerFormat.frequency(peak))"
    }

    private var spectrumPlaceholder: String {
        switch controller.status {
        case .running:
            controller.hasAudioFrames ? "no signal yet — play a string" : "starting the audio engine…"
        case .requestingPermission:
            "waiting for microphone access"
        case .permissionDenied:
            "microphone access is off"
        case .failed:
            "audio engine stopped"
        case .idle:
            "press start to analyse"
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if controller.sampleRate > 0 {
                Text(String(format: "%.1f kHz · analysis window 4096 samples · NSDF autocorrelation", controller.sampleRate / 1000))
            }
            Text("Microphone audio never leaves the device and is not recorded.")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }

    private var statusMessage: String? {
        controller.audioDiagnostic ?? controller.status.message
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TunerTheme.sharp)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if controller.status == .permissionDenied {
                        Button("Open microphone settings") {
                            openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button("Try again") {
                        Task { await controller.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .tunerCard()
    }

    private func openMicrophoneSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

private extension PitchTarget.Kind {
    var string: InstrumentString? {
        if case let .string(value) = self { return value }
        return nil
    }
}
