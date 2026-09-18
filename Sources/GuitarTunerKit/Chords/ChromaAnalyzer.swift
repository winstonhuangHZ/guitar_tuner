import Foundation

/// Twelve-bin pitch-class profile of the current audio, plus the per-note strengths it
/// was built from.
///
/// `noteStrengths` covers `firstMIDINote...lastMIDINote`; it is what lets the chord
/// evaluator say *which* note of a shape is missing rather than only "the chroma vector
/// looks wrong".
public struct ChromaProfile: Sendable, Equatable {
    public static let pitchClassCount = 12

    /// Pitch-class weights, normalised so the strongest bin is 1 (all zero when silent).
    public var weights: [Double]
    /// Per-note strengths for `firstMIDINote...lastMIDINote`, normalised the same way.
    public var noteStrengths: [Double]
    public var firstMIDINote: Int
    public var isSilent: Bool

    public init(
        weights: [Double] = [Double](repeating: 0, count: ChromaProfile.pitchClassCount),
        noteStrengths: [Double] = [],
        firstMIDINote: Int = ChromaAnalyzer.defaultFirstMIDINote,
        isSilent: Bool = true
    ) {
        self.weights = weights
        self.noteStrengths = noteStrengths
        self.firstMIDINote = firstMIDINote
        self.isSilent = isSilent
    }

    public static let silent = ChromaProfile()

    public func weight(ofPitchClass pitchClass: Int) -> Double {
        let index = ((pitchClass % 12) + 12) % 12
        guard index < weights.count else { return 0 }
        return weights[index]
    }

    public func strength(ofMIDINote midiNumber: Int) -> Double {
        let index = midiNumber - firstMIDINote
        guard index >= 0, index < noteStrengths.count else { return 0 }
        return noteStrengths[index]
    }

    /// Strongest pitch of the chord's bass register — used to break ties between chords
    /// that share a pitch-class set (C6 and Am7 are the same notes in a different order).
    public func bassWeight(ofPitchClass pitchClass: Int, belowMIDINote limit: Int) -> Double {
        let target = ((pitchClass % 12) + 12) % 12
        var best = 0.0
        for midi in firstMIDINote...min(limit, firstMIDINote + noteStrengths.count - 1) {
            guard ((midi % 12) + 12) % 12 == target else { continue }
            best = max(best, strength(ofMIDINote: midi))
        }
        return best
    }

    /// Pitch class of the lowest note that is actually sounding. Asus2 and Esus4 are the
    /// same three notes, and this is what tells them apart.
    public func bassPitchClass(above threshold: Double) -> Int? {
        for index in noteStrengths.indices where noteStrengths[index] >= threshold {
            return ((firstMIDINote + index) % 12 + 12) % 12
        }
        return nil
    }

    public var strongestPitchClass: Int? {
        guard let index = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[index] > 0 else {
            return nil
        }
        return index
    }

    /// Pitch classes above `threshold`, strongest first.
    public func soundingPitchClasses(above threshold: Double) -> [Int] {
        weights.indices
            .filter { weights[$0] >= threshold }
            .sorted { weights[$0] > weights[$1] }
    }
}

/// Turns an audio window into a `ChromaProfile`.
///
/// Per note it sums the magnitude of that note's harmonics (harmonic product spectrum),
/// rather than folding the raw spectrum onto twelve bins. That matters for a guitar: the
/// 3rd harmonic of E sits a twelfth above it and would otherwise be read as a B, so a
/// single low E would look like an E5 chord. Harmonic summing reinforces the *fundamental*
/// the harmonics belong to and keeps the chord tones clean.
public final class ChromaAnalyzer: @unchecked Sendable {
    public static let defaultFirstMIDINote = 36   // C2
    public static let defaultLastMIDINote = 84    // C6

    /// Harmonics checked when testing whether a fundamental has a series of its own.
    public var harmonicCount: Int = 5
    /// A harmonic counts as present when it reaches this fraction of the fundamental.
    public var harmonicPresenceRatio: Double = 0.18
    public var maximumWindowSize: Int = 8192
    public var firstMIDINote: Int = ChromaAnalyzer.defaultFirstMIDINote
    public var lastMIDINote: Int = ChromaAnalyzer.defaultLastMIDINote
    /// Must match the tuner's reference so the chroma lines up with the played pitch.
    public var referencePitch: Double = NoteMath.defaultReferencePitch
    /// Chroma weight at or above which a pitch class counts as sounding.
    public var soundingThreshold: Double = 0.3
    /// Peak magnitude (≈ full scale) below which the frame is treated as silence.
    public var silenceMagnitude: Double = 0.0006

    private let spectral = SpectralTransform()

    public init() {}

    public func analyze(samples: [Float], sampleRate: Double) -> ChromaProfile {
        guard sampleRate > 0, samples.count >= 1024 else { return .silent }

        let size = SpectralTransform.preferredSize(
            for: min(samples.count, maximumWindowSize),
            maximum: maximumWindowSize
        )
        guard size >= 512 else { return .silent }
        var magnitudes = spectral.transform(samples: samples, requestedSize: size)
        guard !magnitudes.isEmpty else { return .silent }

        let noteCount = max(0, lastMIDINote - firstMIDINote + 1)
        guard noteCount > 0 else { return .silent }

        var noteStrengths = [Double](repeating: 0, count: noteCount)
        var weights = [Double](repeating: 0, count: ChromaProfile.pitchClassCount)
        var peakMagnitude = 0.0

        // Hann coherent gain 0.5 and the mirrored negative frequency give the factor 4.
        let amplitudeScale = 4 / Double(size)

        for index in 0..<noteCount {
            let midiNumber = firstMIDINote + index
            let fundamental = NoteMath.frequency(
                midiNumber: Double(midiNumber),
                referencePitch: referencePitch
            )
            guard fundamental > 0 else { continue }

            let harmonicLimit = max(1, harmonicCount)

            // Harmonic sum. The FFT cannot resolve semitones in the bass — at 82 Hz the
            // bins are only 0.8 apart — so neighbouring notes inevitably see each other's
            // energy. What separates a real note from a leaking neighbour is the *series*:
            // a note that is really there has energy at 2f, 3f, 4f…
            // Read at the exact equal-tempered frequency. Searching a window for a better
            // match sounds appealing (strings are never in tune) but it lets a bass note
            // latch onto its neighbour's peak: below ~250 Hz the bins are closer together
            // than a semitone, and the leakage was measurably worse than the detuning it
            // recovered (41 of 46 shapes recognised instead of 45).
            let fundamentalMagnitude = magnitude(
                at: fundamental,
                in: magnitudes,
                size: size,
                sampleRate: sampleRate
            )

            // A note is present when its fundamental is there *and* the series above it
            // follows. Both halves matter:
            //  - summing harmonic energy instead would credit a note for partials that
            //    belong to lower notes (the 3rd harmonic of E lands on B, so every plain
            //    triad would read as a seventh chord);
            //  - trusting the fundamental alone would credit leakage: below ~250 Hz the
            //    FFT cannot separate semitones, so neighbouring notes see a strong peak
            //    they do not own. Such a phantom has no series of its own.
            var harmonicHits = 0
            var harmonicsChecked = 0
            if harmonicLimit > 1 {
                for harmonic in 2...harmonicLimit {
                    let frequency = fundamental * Double(harmonic)
                    guard frequency < sampleRate / 2 else { break }
                    harmonicsChecked += 1
                    let magnitude = magnitude(
                        at: frequency,
                        in: magnitudes,
                        size: size,
                        sampleRate: sampleRate
                    )
                    if magnitude >= harmonicPresenceRatio * fundamentalMagnitude {
                        harmonicHits += 1
                    }
                }
            }
            let completeness = harmonicsChecked > 0
                ? Double(harmonicHits) / Double(harmonicsChecked)
                : 1
            let strength = fundamentalMagnitude * completeness * amplitudeScale
            noteStrengths[index] = strength
            peakMagnitude = max(peakMagnitude, strength)
            let pitchClass = ((midiNumber % 12) + 12) % 12
            // Strongest note per pitch class, not the sum: an open E major sounds its root
            // on three strings and its third on one, and summing would make the third look
            // like it is barely there.
            weights[pitchClass] = max(weights[pitchClass], strength)
        }

        guard peakMagnitude > silenceMagnitude else { return .silent }

        for index in noteStrengths.indices {
            noteStrengths[index] /= peakMagnitude
        }
        let chromaPeak = max(weights.max() ?? 0, 1e-12)
        for index in weights.indices {
            weights[index] /= chromaPeak
        }

        return ChromaProfile(
            weights: weights,
            noteStrengths: noteStrengths,
            firstMIDINote: firstMIDINote,
            isSilent: false
        )
    }

    /// Magnitude at an arbitrary frequency, linearly interpolated between bins.
    ///
    /// Reading the nearest bin (or the max over a small window) is not good enough: the
    /// bins are 5.9 Hz apart at 48 kHz, which is *less than a semitone* below 250 Hz, so
    /// three neighbouring bass notes would all read the same peak.
    private func magnitude(
        at frequency: Double,
        in magnitudes: [Float],
        size: Int,
        sampleRate: Double
    ) -> Double {
        let position = frequency * Double(size) / sampleRate
        let lower = Int(position.rounded(.down))
        let upper = lower + 1
        guard lower >= 1, upper < magnitudes.count else { return 0 }
        let fraction = position - Double(lower)
        return Double(magnitudes[lower]) * (1 - fraction) + Double(magnitudes[upper]) * fraction
    }

}
