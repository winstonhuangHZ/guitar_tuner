import GuitarTunerKit
import SwiftUI

/// Metronome page: time signature (including odd metres), tempo, accents and a visual
/// pulse. Timing itself is sample-accurate in the audio engine; this view only displays it.
public struct MetronomeView: View {
    @Bindable public var controller: TunerController
    @State private var tapTimes: [TimeInterval] = []

    public init(controller: TunerController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            TunerTheme.background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    beatCard
                    patternCard
                    tempoCard
                    optionsCard
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Metronome")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text(controller.metronomePattern.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.toggleMetronome()
            } label: {
                Label(
                    controller.isMetronomeRunning ? "Stop" : "Start",
                    systemImage: controller.isMetronomeRunning ? "stop.fill" : "play.fill"
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(controller.isMetronomeRunning ? TunerTheme.surface : TunerTheme.accent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            controller.isMetronomeRunning ? TunerTheme.hairline : .clear,
                            lineWidth: 1
                        )
                )
                .foregroundStyle(controller.isMetronomeRunning ? Color.primary : TunerTheme.onAccent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Beat dots plus a pulse; `TimelineView` extrapolates from the last scheduled click so
    /// the flash lines up with the audio without polling.
    private var beatCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0..<controller.metronomePattern.beats, id: \.self) { index in
                    let isGroupStart = isGroupStart(beat: index)
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: isGroupStart ? 18 : 13, height: isGroupStart ? 18 : 13)
                }
            }
            .frame(maxWidth: .infinity)

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let pulse = beatPulse(at: context.date)
                Text("\(controller.metronomeTempo.rounded(), specifier: "%.0f") BPM")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .scaleEffect(1 + 0.06 * pulse)
                    .foregroundStyle(pulse > 0.4 ? TunerTheme.inTune : Color.primary)
            }

            Text(controller.lastBeat.map { "bar \($0.barNumber) · beat \($0.beatNumber)" } ?? "stopped")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .tunerCard()
    }

    private var patternCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Time signature").tunerSectionTitle()
                Spacer()
                Text("odd metres come with their usual groupings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(MetronomePattern.all) { pattern in
                    Button {
                        controller.setMetronomePattern(pattern)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.timeSignature)
                                .font(.system(.headline, design: .rounded))
                            if pattern.grouping.count > 1 {
                                Text(pattern.grouping.map(String.init).joined(separator: "+"))
                                    .font(.caption2.monospacedDigit())
                            } else {
                                Text(pattern.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    pattern.id == controller.metronomePattern.id
                                        ? TunerTheme.accent
                                        : TunerTheme.subtleFill
                                )
                        )
                        .foregroundStyle(
                            pattern.id == controller.metronomePattern.id ? TunerTheme.onAccent : Color.primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .tunerCard()
    }

    private var tempoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tempo").tunerSectionTitle()
                Spacer()
                Button("Tap") { tapped() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("−") { controller.setMetronomeTempo(controller.metronomeTempo - 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("+") { controller.setMetronomeTempo(controller.metronomeTempo + 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Common") { controller.setMetronomeTempo(90) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Slider(
                value: Binding(
                    get: { controller.metronomeTempo },
                    set: { controller.setMetronomeTempo($0) }
                ),
                in: MetronomePattern.minimumTempo...MetronomePattern.maximumTempo,
                step: 1
            )
            .tint(TunerTheme.accent)

            Text(tempoHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .tunerCard()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Accent the downbeat and group starts",
                isOn: Binding(
                    get: { controller.metronomeAccentsEnabled },
                    set: { controller.setMetronomeAccents($0) }
                )
            )
            .toggleStyle(.switch)

            HStack {
                Text("Volume").tunerSectionTitle()
                Slider(
                    value: Binding(
                        get: { controller.metronomeVolume },
                        set: { controller.setMetronomeVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(TunerTheme.inTune)
            }
        }
        .tunerCard()
    }

    // MARK: - Helpers

    private var tempoHint: String {
        let pattern = controller.metronomePattern
        let noteName: String = switch pattern.noteValue {
        case 4: "quarter notes"
        case 8: "eighth notes"
        default: "1/\(pattern.noteValue) notes"
        }
        let barSeconds = pattern.beatDuration(tempo: controller.metronomeTempo) * Double(pattern.beats)
        return "Tempo counts \(noteName); one bar takes \(String(format: "%.2f", barSeconds)) s."
    }

    private func isGroupStart(beat index: Int) -> Bool {
        guard index > 0 else { return true }
        var boundary = 0
        for group in controller.metronomePattern.grouping.dropLast() {
            boundary += group
            if index == boundary { return true }
        }
        return false
    }

    private func dotColor(for index: Int) -> Color {
        guard controller.isMetronomeRunning else { return TunerTheme.track }
        let beat = currentBeatIndex()
        guard let beat else { return TunerTheme.track }
        return beat % max(controller.metronomePattern.beats, 1) == index
            ? TunerTheme.inTune
            : TunerTheme.track
    }

    /// Which beat is sounding now, from the last scheduled click plus elapsed host time.
    private func currentBeatIndex() -> Int? {
        guard let beat = controller.lastBeat else { return nil }
        let now = HostClock.now
        guard now >= beat.hostTime else { return beat.beatNumber - 1 }
        let elapsed = HostClock.seconds(from: beat.hostTime, to: now)
        let ticks = Int(elapsed / max(beat.duration, 0.001))
        return (beat.tickIndex / max(controller.metronomePattern.subdivision, 1) + ticks)
            % max(controller.metronomePattern.beats, 1)
    }

    private func beatPulse(at date: Date) -> Double {
        guard controller.isMetronomeRunning, let beat = controller.lastBeat else { return 0 }
        _ = date
        let now = HostClock.now
        guard now >= beat.hostTime else { return 0 }
        let elapsed = HostClock.seconds(from: beat.hostTime, to: now)
        let phase = elapsed.truncatingRemainder(dividingBy: max(beat.duration, 0.001)) / max(beat.duration, 0.001)
        return max(0, 1 - phase * 3)
    }

    private func tapped() {
        let now = Date().timeIntervalSince1970
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst(tapTimes.count - 6) }
        guard tapTimes.count >= 2 else { return }
        let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0 - $1 }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0.15, average < 3 else { return }
        controller.setMetronomeTempo(60 / average)
    }
}
