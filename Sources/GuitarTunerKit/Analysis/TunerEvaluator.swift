import Foundation

/// Turns a stabilised frequency into a target string, a cents deviation and an
/// in-tune flag.
///
/// Auto mode keeps the previously matched string unless another string is clearly
/// closer (`hysteresisCents`), which stops the target from flip-flopping between the
/// 5th and 6th string while a low string is ringing.
public struct TunerEvaluator: Sendable {
    public var hysteresisCents: Double
    private var currentTargetID: String?

    public init(hysteresisCents: Double = 12) {
        self.hysteresisCents = hysteresisCents
    }

    public var activeTargetID: String? { currentTargetID }

    public mutating func reset() {
        currentTargetID = nil
    }

    public mutating func evaluate(
        _ stabilized: StabilizedPitch,
        selection: TuningSelection,
        timestamp: TimeInterval
    ) -> TunerReading {
        var reading = TunerReading(
            frequency: stabilized.frequency,
            rawFrequency: stabilized.rawFrequency,
            clarity: stabilized.clarity,
            level: stabilized.analysis.level,
            rms: stabilized.analysis.rms,
            gate: stabilized.analysis.gate,
            isHeld: stabilized.isHeld,
            timestamp: timestamp
        )

        guard let frequency = stabilized.frequency else {
            currentTargetID = nil
            return reading
        }

        guard let match = resolveTarget(frequency: frequency, selection: selection) else {
            reading.note = NoteMath.nearestNote(
                forFrequency: frequency,
                referencePitch: selection.referencePitch
            )?.note
            return reading
        }

        currentTargetID = match.target.id
        reading.target = match.target
        reading.cents = match.cents
        reading.note = match.target.note
        reading.isInTune = abs(match.cents) <= selection.inTuneToleranceCents
            && stabilized.clarity >= selection.minimumClarityForInTune

        return reading
    }

    // MARK: - Target resolution

    private func resolveTarget(frequency: Double, selection: TuningSelection) -> (target: PitchTarget, cents: Double)? {
        if selection.preset.isChromatic {
            guard let nearest = NoteMath.nearestNote(
                forFrequency: frequency,
                referencePitch: selection.referencePitch
            ) else { return nil }
            let targetFrequency = NoteMath.frequency(of: nearest.note, referencePitch: selection.referencePitch)
            let target = PitchTarget(
                id: "chromatic-\(nearest.note.midiNumber)",
                kind: .chromatic,
                note: nearest.note,
                frequency: targetFrequency,
                detailedLabel: nearest.note.description()
            )
            return (target, NoteMath.cents(from: frequency, to: targetFrequency))
        }

        let candidates = candidateStrings(for: selection)
        guard !candidates.isEmpty else { return nil }

        var best: (string: InstrumentString, cents: Double)?
        for string in candidates {
            let target = string.frequency(referencePitch: selection.referencePitch)
            let cents = NoteMath.cents(from: frequency, to: target)
            if best == nil || abs(cents) < abs(best!.cents) {
                best = (string, cents)
            }
        }

        guard var match = best else { return nil }

        if let currentTargetID,
           let previous = candidates.first(where: { "string-\($0.id)" == currentTargetID }) {
            let previousCents = previous.centsDeviation(for: frequency, referencePitch: selection.referencePitch)
            if abs(previousCents) <= abs(match.cents) + hysteresisCents {
                match = (previous, previousCents)
            }
        }

        let target = PitchTarget(
            id: "string-\(match.string.id)",
            kind: .string(match.string),
            note: match.string.note,
            frequency: match.string.frequency(referencePitch: selection.referencePitch),
            detailedLabel: match.string.detailedName
        )
        return (target, match.cents)
    }

    private func candidateStrings(for selection: TuningSelection) -> [InstrumentString] {
        switch selection.stringSelection {
        case .automatic:
            selection.preset.strings
        case let .locked(id):
            selection.preset.strings.filter { $0.id == id }
        }
    }
}
