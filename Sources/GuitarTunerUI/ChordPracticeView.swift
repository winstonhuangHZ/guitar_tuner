import GuitarTunerKit
import SwiftUI

/// Chord mode: show a shape, listen to what is actually played, and say which string or
/// which note is off.
public struct ChordPracticeView: View {
    @Bindable public var controller: TunerController

    @State private var selectedRoot: NoteName = .c
    @State private var selectedVoicingID: String = ChordLibrary.guitar.first?.id ?? ""

    public init(controller: TunerController) {
        self.controller = controller
    }

    private var availableVoicings: [ChordVoicing] {
        ChordLibrary.guitar.filter { $0.root == selectedRoot }
    }

    private var selectedVoicing: ChordVoicing? {
        availableVoicings.first { $0.id == selectedVoicingID } ?? availableVoicings.first
    }

    public var body: some View {
        ZStack {
            TunerTheme.background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    chordPicker
                    diagramCard
                    liveCard
                    helpCard
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            await controller.start()
            syncTarget()
        }
        .onChange(of: selectedRoot) { _, _ in
            selectedVoicingID = availableVoicings.first?.id ?? ""
            syncTarget()
        }
        .onChange(of: selectedVoicingID) { _, _ in syncTarget() }
        .onDisappear { controller.practiceTarget = nil }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chord practice")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Strum the shape and watch which string lands where")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !controller.isRunning {
                Button("Listen") { Task { await controller.start() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var chordPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Root").tunerSectionTitle()
                Spacer()
                Text("\(ChordLibrary.guitar.count) shapes in the library")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(NoteName.allCases, id: \.self) { root in
                        let hasShapes = ChordLibrary.guitar.contains { $0.root == root }
                        Button {
                            selectedRoot = root
                        } label: {
                            Text(root.sharpName)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .frame(minWidth: 34)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(root == selectedRoot ? TunerTheme.accent : TunerTheme.subtleFill)
                                )
                                .foregroundStyle(root == selectedRoot ? TunerTheme.onAccent : Color.primary)
                                .opacity(hasShapes ? 1 : 0.4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if !availableVoicings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableVoicings) { voicing in
                            Button {
                                selectedVoicingID = voicing.id
                            } label: {
                                VStack(spacing: 1) {
                                    Text(voicing.name)
                                        .font(.system(.headline, design: .rounded))
                                    Text(voicing.quality.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(voicing.id == selectedVoicing?.id ? TunerTheme.onAccent.opacity(0.85) : .secondary)
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(voicing.id == selectedVoicing?.id ? TunerTheme.accent : TunerTheme.subtleFill)
                                )
                                .foregroundStyle(voicing.id == selectedVoicing?.id ? TunerTheme.onAccent : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .tunerCard()
    }

    @ViewBuilder
    private var diagramCard: some View {
        if let voicing = selectedVoicing {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(voicing.name)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(voicing.quality.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(voicing.notes.map { $0.description() }.joined(separator: " "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ChordDiagramView(
                    voicing: voicing,
                    stringVerdicts: verdicts(for: voicing)
                )

                HStack(spacing: 10) {
                    Button {
                        controller.playPracticeChord()
                    } label: {
                        Label("Hear this chord", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        controller.playReferenceTone(stringIndex: voicing.frets.firstIndex { $0 != nil } ?? 0)
                    } label: {
                        Label("Lowest note", systemImage: "music.note")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                HStack(spacing: 14) {
                    legendDot(TunerTheme.inTune, "sounds")
                    legendDot(TunerTheme.sharp, "quiet or missing")
                    legendDot(Color.black.opacity(0.65), "muted / extra")
                    Spacer()
                }
                .font(.caption2)
            }
            .tunerCard()
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What the tuner hears").tunerSectionTitle()
                Spacer()
                if let detection = controller.chordDetection.best {
                    Text("\(detection.name) · \(Int((controller.chordDetection.confidence * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(controller.chordDetection.isConfident ? TunerTheme.inTune : .secondary)
                } else {
                    Text(controller.status.isRunning ? "nothing yet" : "not listening")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            ChromaBarView(
                chroma: controller.chroma,
                expectedPitchClasses: selectedVoicing?.pitchClasses ?? []
            )

            if let evaluation = controller.chordEvaluation {
                Divider().opacity(0.35)
                HStack(spacing: 8) {
                    Image(systemName: evaluation.isCorrect ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(evaluation.isCorrect ? TunerTheme.inTune : TunerTheme.sharp)
                    Text(evaluation.summary)
                        .font(.callout)
                    Spacer()
                    Text("\(Int((evaluation.score * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if controller.isRunning {
                Text("Strum all the strings of the shape and hold them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .tunerCard()
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to practise").tunerSectionTitle()
            Text("1. Tune first — chord detection assumes the strings are close to pitch (a few tens of cents).")
            Text("2. Play the shape and let it ring; the diagram colours each string green when its note is heard.")
            Text("3. \"Missing\" means a note the shape needs was not heard — usually a string that did not sound or a finger muting its neighbour.")
            Text("4. For single-string accuracy, switch to the Tuner tab and pick that string there.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .tunerCard()
    }

    // MARK: - Helpers

    private func verdicts(for voicing: ChordVoicing) -> [ChordEvaluation.Verdict?] {
        guard let evaluation = controller.chordEvaluation,
              evaluation.targetName == voicing.name else {
            return []
        }
        var result: [ChordEvaluation.Verdict?] = Array(repeating: nil, count: voicing.frets.count)
        for assessment in evaluation.strings where assessment.id < result.count {
            result[assessment.id] = assessment.verdict
        }
        return result
    }

    private func syncTarget() {
        controller.practiceTarget = selectedVoicing
    }
}

/// Twelve pitch-class bars, highlighting the notes the target chord needs.
public struct ChromaBarView: View {
    public var chroma: ChromaProfile
    public var expectedPitchClasses: Set<Int>

    public init(chroma: ChromaProfile, expectedPitchClasses: Set<Int>) {
        self.chroma = chroma
        self.expectedPitchClasses = expectedPitchClasses
    }

    public var body: some View {
        GeometryReader { proxy in
            let count = ChromaProfile.pitchClassCount
            let spacing: CGFloat = 4
            let slot = (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<count, id: \.self) { pitchClass in
                    let weight = chroma.weight(ofPitchClass: pitchClass)
                    let isExpected = expectedPitchClasses.contains(pitchClass)
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: pitchClass, weight: weight, isExpected: isExpected))
                            .frame(width: slot, height: max(3, CGFloat(weight) * (proxy.size.height - 16)))
                        Text(name(for: pitchClass))
                            .font(.system(size: 8, weight: isExpected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isExpected ? Color.primary : Color.black.opacity(0.35))
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 62)
    }

    private func color(for pitchClass: Int, weight: Double, isExpected: Bool) -> Color {
        if isExpected {
            return weight >= 0.3 ? TunerTheme.inTune : TunerTheme.inTune.opacity(0.25)
        }
        return weight >= 0.45 ? TunerTheme.sharp.opacity(0.75) : TunerTheme.accent.opacity(0.35)
    }

    private func name(for pitchClass: Int) -> String {
        NoteName(rawValue: pitchClass)?.sharpName ?? "?"
    }
}
