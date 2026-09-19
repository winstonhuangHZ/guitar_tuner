import GuitarTunerKit
import SwiftUI

/// Progress page: the progression trainer and what the tuning history says about each
/// string.
public struct PracticeProgressView: View {
    @Bindable public var controller: TunerController

    public init(controller: TunerController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            TunerTheme.background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    progressionCard
                    scoreCard
                    historyCard
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if !controller.isRunning {
                await controller.start()
            }
            controller.refreshHistorySummary()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Chord changes with the metronome, plus how your guitar drifts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.isProgressionRunning ? controller.stopProgression() : controller.startProgression()
            } label: {
                Label(
                    controller.isProgressionRunning ? "Stop" : "Start",
                    systemImage: controller.isProgressionRunning ? "stop.fill" : "play.fill"
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(controller.isProgressionRunning ? TunerTheme.surface : TunerTheme.accent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            controller.isProgressionRunning ? TunerTheme.hairline : .clear,
                            lineWidth: 1
                        )
                )
                .foregroundStyle(controller.isProgressionRunning ? Color.primary : TunerTheme.onAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var progressionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progression").tunerSectionTitle()
                Spacer()
                Text("\(controller.metronomeTempo.rounded(), specifier: "%.0f") BPM · \(controller.metronomePattern.timeSignature)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker(
                "Progression",
                selection: Binding(
                    get: { controller.progression.id },
                    set: { id in
                        if let progression = Progression.progression(id: id) {
                            controller.setProgression(progression)
                        }
                    }
                )
            ) {
                ForEach(Progression.all) { progression in
                    Text("\(progression.name) — \(progression.detail)").tag(progression.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            // Chord chips with the result of the last run.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(controller.progression.steps.enumerated()), id: \.offset) { index, step in
                        let name = ChordLibrary.voicing(id: step.voicingID)?.name ?? step.voicingID
                        let score = controller.progressionScores.first { $0.id == index }
                        let isCurrent = controller.isProgressionRunning
                            && controller.progressionUpdate?.stepIndex == index
                        Text(name)
                            .font(.system(.headline, design: .rounded))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(background(for: score, isCurrent: isCurrent))
                            )
                            .foregroundStyle(score != nil || isCurrent ? TunerTheme.onAccent : Color.primary)
                    }
                }
                .padding(.vertical, 2)
            }

            if controller.progressionIsFinished {
                Text("Finished — \(Int((controller.progressionAccuracy * 100).rounded()))% of the changes landed.")
                    .font(.callout)
                    .foregroundStyle(TunerTheme.inTune)
            } else if controller.isProgressionRunning {
                Text(nextChordHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start, and the metronome counts while the tuner scores every chord change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tunerCard()
    }

    private var nextChordHint: String {
        guard let voicing = controller.progressionCurrentVoicing else { return "" }
        let remaining = (controller.progressionUpdate?.beatInStep).map { max(voicing.frets.count, 0) - $0 } ?? 0
        _ = remaining
        return "Now: \(voicing.name) — \(voicing.quality.displayName)"
    }

    private func background(for score: ProgressionTrainer.StepScore?, isCurrent: Bool) -> Color {
        if let score {
            return score.isCorrect ? TunerTheme.inTune : TunerTheme.sharp
        }
        return isCurrent ? TunerTheme.accent : TunerTheme.subtleFill
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This run").tunerSectionTitle()
            HStack(spacing: 18) {
                metric("Accuracy", String(format: "%.0f%%", controller.progressionAccuracy * 100))
                metric("Chords", "\(controller.progressionScores.filter(\.isCorrect).count)/\(controller.progressionScores.count)")
                metric("Best streak", "\(controller.progressionBestStreak)")
            }
            HStack {
                Button("Reset run") { controller.resetProgression() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Hear it") { controller.playProgressionReference() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .tunerCard()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tuning history").tunerSectionTitle()
                Spacer()
                Text(summaryCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if controller.tuningHistorySummary.isEmpty {
                Text("Nothing recorded yet. Tune a few strings and this fills in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.tuningHistorySummary.stats) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(stat.label).font(.callout)
                            Spacer()
                            Text(String(format: "%+.1f ¢", stat.averageCents))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(abs(stat.averageCents) <= 5 ? TunerTheme.inTune : TunerTheme.sharp)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TunerTheme.track)
                                Capsule()
                                    .fill(abs(stat.averageCents) <= 5 ? TunerTheme.inTune : TunerTheme.sharp)
                                    .frame(width: proxy.size.width * min(abs(stat.averageCents) / 25, 1))
                            }
                        }
                        .frame(height: 6)
                        Text("\(stat.sampleCount) samples · in tune \(Int((stat.inTuneRatio * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }

                if !controller.tuningHistorySummary.hints.isEmpty {
                    Divider().opacity(0.35)
                    ForEach(controller.tuningHistorySummary.hints, id: \.self) { hint in
                        Label(hint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tunerCard()
    }

    private var summaryCaption: String {
        let summary = controller.tuningHistorySummary
        guard let last = summary.lastSample else { return "no samples" }
        let date = Date(timeIntervalSince1970: last)
        return "last \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
