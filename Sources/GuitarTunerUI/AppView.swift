import GuitarTunerKit
import SwiftUI

/// Root view: the tuner and the chord practice mode share one audio engine, so switching
/// tabs keeps the microphone stream (and the tuning) alive.
public struct AppView: View {
    public enum Mode: String, CaseIterable, Identifiable {
        case tuner
        case chords

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .tuner: "Tuner"
            case .chords: "Chords"
            }
        }

        var symbol: String {
            switch self {
            case .tuner: "tuningfork"
            case .chords: "guitars"
            }
        }
    }

    @Bindable public var controller: TunerController
    @State private var mode: Mode = .tuner

    public init(controller: TunerController, initialMode: Mode = .tuner) {
        self.controller = controller
        _mode = State(initialValue: initialMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(TunerTheme.canvas)

            switch mode {
            case .tuner:
                TunerView(controller: controller)
            case .chords:
                ChordPracticeView(controller: controller)
            }
        }
    }
}
