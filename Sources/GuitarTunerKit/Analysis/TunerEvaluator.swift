import Foundation

/// Turns a stabilised frequency into a target string, a cents deviation and an
/// in-tune flag.
///
/// Auto mode keeps the previously matched string unless another string is clearly
/// closer (`hysteresisCents`), which stops the target from flip-flopping between the
/// 5th and 6th string while a low string is ringing.
public struct TunerEvaluator: Sendable {
    public var hysteresisCents: Double
    /// A reading may only be attributed to a string through one of its harmonics when the
    /// folded result lands this close to the string.
    public var harmonicFoldToleranceCents: Double
    /// How far off a direct match has to be before harmonic interpretations are tried.
    public var directMatchSuspicionCents: Double
    /// Cost per harmonic step, so the 2nd harmonic is preferred over the 4th.
    public var harmonicStepPenaltyCents: Double
    public var maximumHarmonicDivisor: Int
    private var currentTargetID: String?

    public init(
        hysteresisCents: Double = 12,
        harmonicFoldToleranceCents: Double = 25,
        directMatchSuspicionCents: Double = 60,
        harmonicStepPenaltyCents: Double = 5,
        maximumHarmonicDivisor: Int = 6
    ) {
        self.hysteresisCents = hysteresisCents
        self.harmonicFoldToleranceCents = harmonicFoldToleranceCents
        self.directMatchSuspicionCents = directMatchSuspicionCents
        self.harmonicStepPenaltyCents = harmonicStepPenaltyCents
        self.maximumHarmonicDivisor = maximumHarmonicDivisor
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
        reading.harmonicDivisor = match.divisor > 1 ? match.divisor : nil
        reading.isInTune = abs(match.cents) <= selection.inTuneToleranceCents
            && stabilized.clarity >= selection.minimumClarityForInTune

        return reading
    }

    // MARK: - Target resolution

    private func resolveTarget(
        frequency: Double,
        selection: TuningSelection
    ) -> (target: PitchTarget, cents: Double, divisor: Int)? {
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
            return (target, NoteMath.cents(from: frequency, to: targetFrequency), 1)
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
        var divisor = 1

        // A low string with a weak fundamental is heard mainly through its harmonics, and
        // the harmonic can sit much closer to a different string than to its own: the 2nd
        // harmonic of low E (164.8 Hz) is 200 cents from the D3 string but 1200 cents from
        // E2, so a naive matcher names the wrong string with confidence. Guitars cannot be
        // tuned an octave up without snapping, so when a harmonic interpretation lands on
        // a string essentially in tune, that is the right answer.
        let isLocked = selection.stringSelection.lockedStringID != nil
        // Only a poor direct match, or an explicitly locked string, justifies reading the
        // measurement as a harmonic. Using the *tracked* string as an extra excuse would
        // make the tuner report "E2 in tune" when the player has actually moved to the B
        // string — the harmonic and the open string are the same frequency.
        if isLocked || abs(match.cents) > directMatchSuspicionCents {
            let folded = bestHarmonicMatch(
                frequency: frequency,
                candidates: candidates,
                selection: selection
            )
            if let folded {
                let clearlyBetter = abs(folded.cents)
                    + harmonicStepPenaltyCents * Double(folded.divisor - 1) < abs(match.cents)
                if isLocked || clearlyBetter {
                    match = (folded.string, folded.cents)
                    divisor = folded.divisor
                }
            }
        }

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
        return (target, match.cents, divisor)
    }

    /// Best string when the measured frequency is read as an integer multiple of that
    /// string's pitch.
    private func bestHarmonicMatch(
        frequency: Double,
        candidates: [InstrumentString],
        selection: TuningSelection
    ) -> (string: InstrumentString, cents: Double, divisor: Int)? {
        var best: (string: InstrumentString, cents: Double, divisor: Int)?
        var bestCost = Double.infinity

        for divisor in 2...max(2, maximumHarmonicDivisor) {
            let implied = frequency / Double(divisor)
            guard implied > 0 else { continue }
            for string in candidates {
                let cents = string.centsDeviation(for: implied, referencePitch: selection.referencePitch)
                guard abs(cents) <= harmonicFoldToleranceCents else { continue }
                let cost = abs(cents) + harmonicStepPenaltyCents * Double(divisor - 1)
                guard cost < bestCost else { continue }
                bestCost = cost
                best = (string, cents, divisor)
            }
        }

        return best
    }

    private func candidateStrings(for selection: TuningSelection) -> [InstrumentString] {
        let strings = selection.preset.strings(capoFret: selection.capoFret)
        return switch selection.stringSelection {
        case .automatic:
            strings
        case let .locked(id):
            strings.filter { $0.id == id }
        }
    }
}
