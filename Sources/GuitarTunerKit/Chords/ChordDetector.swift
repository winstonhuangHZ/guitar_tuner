import Foundation

/// What the detector heard.
public struct ChordDetection: Sendable, Equatable {
    public struct Candidate: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var root: NoteName
        public var quality: ChordQuality
        public var score: Double
    }

    public var candidates: [Candidate]
    public var chroma: ChromaProfile
    /// Cosine similarity of the winning template, 0...1.
    public var score: Double
    /// 0...1, combining how well the winner fits with how far ahead it is.
    public var confidence: Double

    public init(
        candidates: [Candidate] = [],
        chroma: ChromaProfile = .silent,
        score: Double = 0,
        confidence: Double = 0
    ) {
        self.candidates = candidates
        self.chroma = chroma
        self.score = score
        self.confidence = confidence
    }

    public static let none = ChordDetection()

    public var best: Candidate? { candidates.first }
    public var name: String? { best?.name }
    public var root: NoteName? { best?.root }
    public var quality: ChordQuality? { best?.quality }
    public var isConfident: Bool { confidence >= 0.5 }
}

/// Matches a `ChromaProfile` against chord templates.
public struct ChordDetector: Sendable {
    public var candidateQualities: [ChordQuality]
    /// Weight of each interval in a template. The perfect fifth is deliberately light:
    /// guitar voicings routinely omit it, and weighting it like a third makes a missing
    /// fifth look like a missing chord tone.
    public var intervalWeights: [Int: Double]
    /// How strongly energy outside the template counts against a candidate. Without this
    /// a bare root + fifth (a power chord) would win every time, because its two-note
    /// template always "fits" inside a full triad.
    public var extraPenalty: Double
    /// Score below which nothing is reported, however confident the ranking.
    public var minimumScore: Double
    /// Score difference (against the best *differently-shaped* chord) that counts as a
    /// clear win.
    public var decisiveMargin: Double
    /// How much having the chord's root in the bass counts towards the score — the
    /// tie-breaker between chords that share a pitch-class set (Asus2 / Esus4).
    public var bassRootBonus: Double
    /// A chord needs at least this many sounding pitch classes; one note is not a chord.
    public var minimumSoundingNotes: Int
    /// Chroma weight at or above which a pitch class counts as sounding.
    public var soundingThreshold: Double
    /// Note strength at or above which the lowest note defines the bass.
    public var bassThreshold: Double
    /// Chroma weight at which a template tone counts as fully present.
    ///
    /// Scoring with the raw chroma value punishes doublings: an open E major sounds its
    /// root on three strings and its third on one, so the third looks "mostly missing"
    /// and every triad loses to its own power chord. Past this weight a tone simply
    /// counts as there.
    public var presenceSaturation: Double
    /// Cost per tone beyond a triad. Adding a seventh (or a ninth) is a strong claim, so
    /// it has to be clearly audible: when the evidence is ambiguous the simpler chord is
    /// the better answer, which is also how the ear hears it.
    public var complexityPenalty: Double

    public init(
        candidateQualities: [ChordQuality] = ChordLibrary.detectableQualities,
        intervalWeights: [Int: Double] = ChordDetector.defaultIntervalWeights,
        extraPenalty: Double = 3.0,
        minimumScore: Double = 0.6,
        decisiveMargin: Double = 0.12,
        bassRootBonus: Double = 0.1,
        minimumSoundingNotes: Int = 2,
        soundingThreshold: Double = 0.3,
        bassThreshold: Double = 0.3,
        presenceSaturation: Double = 0.45,
        complexityPenalty: Double = 0.03
    ) {
        self.candidateQualities = candidateQualities
        self.intervalWeights = intervalWeights
        self.extraPenalty = extraPenalty
        self.minimumScore = minimumScore
        self.decisiveMargin = decisiveMargin
        self.bassRootBonus = bassRootBonus
        self.minimumSoundingNotes = minimumSoundingNotes
        self.soundingThreshold = soundingThreshold
        self.bassThreshold = bassThreshold
        self.presenceSaturation = presenceSaturation
        self.complexityPenalty = complexityPenalty
    }

    /// Root and chord-defining tones carry full weight; the fifth is optional; added and
    /// suspended tones sit in between.
    public static let defaultIntervalWeights: [Int: Double] = [
        0: 1.0,   // root
        3: 1.0,   // minor third
        4: 1.0,   // major third
        10: 1.0,  // minor seventh
        11: 1.0,  // major seventh
        2: 0.8,   // ninth / sus2
        5: 0.8,   // sus4
        6: 0.8,   // diminished fifth
        8: 0.8,   // augmented fifth
        9: 0.8,   // sixth
        7: 0.25,  // perfect fifth — commonly omitted
    ]

    public func detect(_ chroma: ChromaProfile) -> ChordDetection {
        guard !chroma.isSilent else { return .none }

        let sounding = chroma.soundingPitchClasses(above: soundingThreshold)
        guard sounding.count >= minimumSoundingNotes else {
            return ChordDetection(candidates: [], chroma: chroma)
        }

        let bass = chroma.bassPitchClass(above: bassThreshold)

        var candidates: [ChordDetection.Candidate] = []
        for root in NoteName.allCases {
            for quality in candidateQualities {
                let intervals = Set(quality.intervals.map { (($0 % 12) + 12) % 12 })
                var score = matchScore(chroma: chroma, intervals: intervals, root: root.rawValue)
                score -= complexityPenalty * Double(max(0, intervals.count - 3))
                if bass == root.rawValue { score += bassRootBonus }
                candidates.append(
                    ChordDetection.Candidate(
                        id: "\(root.rawValue)-\(quality.rawValue)",
                        name: root.sharpName + quality.symbol,
                        root: root,
                        quality: quality,
                        score: score
                    )
                )
            }
        }

        candidates.sort { $0.score > $1.score }
        guard let best = candidates.first, best.score >= minimumScore else {
            return ChordDetection(candidates: Array(candidates.prefix(5)), chroma: chroma)
        }

        // Some chords are the same notes in a different order (C6 and Am7). Those are not
        // competing answers, so the margin is measured against the best *differently
        // shaped* candidate.
        let bestShape = best.quality.pitchClasses(abovePitchClass: best.root.rawValue)
        let rival = candidates.first { candidate in
            candidate.quality.pitchClasses(abovePitchClass: candidate.root.rawValue) != bestShape
        }
        let margin = best.score - (rival?.score ?? 0)

        let fit = (best.score - minimumScore) / max(1 - minimumScore, 1e-6)
        let decisiveness = margin / max(decisiveMargin, 1e-6)
        let confidence = min(max(fit, 0), 1) * min(max(decisiveness, 0), 1)

        return ChordDetection(
            candidates: Array(candidates.prefix(5)),
            chroma: chroma,
            score: best.score,
            confidence: confidence
        )
    }

    /// Weighted coverage of the template, minus a penalty for energy the template does
    /// not explain.
    ///
    /// Cosine similarity is the obvious choice here and it does not work: a two-note
    /// power-chord template normalises to a *better* fit than the three-note triad it is
    /// contained in, so every major and minor chord comes back as a `5` chord. Rewarding
    /// coverage and charging for unexplained energy keeps both directions honest — a full
    /// triad beats the power chord, and a real power chord (no third anywhere) still wins
    /// over the triad, which would be missing a defining tone.
    private func matchScore(chroma: ChromaProfile, intervals: Set<Int>, root: Int) -> Double {
        guard !intervals.isEmpty else { return 0 }

        var covered = 0.0
        var templateWeight = 0.0
        for interval in intervals {
            let weight = intervalWeights[interval] ?? 0.8
            let pitchClass = ((root + interval) % 12 + 12) % 12
            let presence = min(1, chroma.weight(ofPitchClass: pitchClass) / max(presenceSaturation, 1e-6))
            covered += weight * presence
            templateWeight += weight
        }
        guard templateWeight > 0 else { return 0 }

        var unexplained = 0.0
        for pitchClass in 0..<ChromaProfile.pitchClassCount {
            let interval = ((pitchClass - root) % 12 + 12) % 12
            guard !intervals.contains(interval) else { continue }
            unexplained += chroma.weight(ofPitchClass: pitchClass)
        }

        return covered / templateWeight - extraPenalty * unexplained / Double(ChromaProfile.pitchClassCount)
    }
}
