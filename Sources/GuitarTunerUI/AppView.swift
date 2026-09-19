import GuitarTunerKit
import SwiftUI

/// Root view: the tuner and the chord practice mode share one audio engine, so switching
/// tabs keeps the microphone stream (and the tuning) alive.
public struct AppView: View {
    public enum Mode: String, CaseIterable, Identifiable {
        case tuner
        case chords
        case metronome
        case practice

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .tuner: "Tuner"
            case .chords: "Chords"
            case .metronome: "Metronome"
            case .practice: "Practice"
            }
        }

        var symbol: String {
            switch self {
            case .tuner: "tuningfork"
            case .chords: "guitars"
            case .metronome: "metronome"
            case .practice: "chart.line.uptrend.xyaxis"
            }
        }
    }

    @Bindable public var controller: TunerController
    @State private var mode: Mode = .tuner
    @State private var showsSettings = false

    public init(controller: TunerController, initialMode: Mode = .tuner) {
        self.controller = controller
        _mode = State(initialValue: initialMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .padding(7)
                        .background(TunerTheme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(TunerTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(TunerTheme.canvas)

            switch mode {
            case .tuner:
                TunerView(controller: controller)
            case .chords:
                ChordPracticeView(controller: controller)
            case .metronome:
                MetronomeView(controller: controller)
            case .practice:
                PracticeProgressView(controller: controller)
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(controller: controller)
                .preferredColorScheme(.light)
        }
    }
}
