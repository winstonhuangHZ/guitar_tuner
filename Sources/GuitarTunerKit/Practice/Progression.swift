import Foundation

/// One chord in a progression, with how long it is held.
public struct ProgressionStep: Sendable, Equatable, Identifiable, Codable {
    public var id: Int
    /// `ChordLibrary` voicing id, e.g. `C`, `G7`.
    public var voicingID: String
    /// Length in metronome beats.
    public var beats: Int

    public init(id: Int, voicingID: String, beats: Int = 4) {
        self.id = id
        self.voicingID = voicingID
        self.beats = max(1, beats)
    }
}

/// A chord progression to practise over the metronome.
public struct Progression: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var detail: String
    public var steps: [ProgressionStep]
    public var defaultTempo: Double

    public init(id: String, name: String, detail: String, steps: [ProgressionStep], defaultTempo: Double = 80) {
        self.id = id
        self.name = name
        self.detail = detail
        self.steps = steps
        self.defaultTempo = defaultTempo
    }

    public var totalBeats: Int { steps.reduce(0) { $0 + $1.beats } }

    public func voicing(atStep index: Int) -> ChordVoicing? {
        guard steps.indices.contains(index) else { return nil }
        return ChordLibrary.voicing(id: steps[index].voicingID)
    }

    public var chordNames: [String] {
        steps.compactMap { ChordLibrary.voicing(id: $0.voicingID)?.name }
    }

    public static func progression(id: String) -> Progression? {
        all.first { $0.id == id }
    }

    private static func bars(_ ids: [String], beats: Int = 4) -> [ProgressionStep] {
        ids.enumerated().map { ProgressionStep(id: $0.offset, voicingID: $0.element, beats: beats) }
    }

    public static let popFour = Progression(
        id: "pop-I-V-vi-IV",
        name: "I – V – vi – IV",
        detail: "The four chords behind a huge number of songs",
        steps: bars(["C", "G", "Am", "F"]),
        defaultTempo: 84
    )

    public static let fifties = Progression(
        id: "fifties-I-vi-IV-V",
        name: "I – vi – IV – V",
        detail: "Doo-wop changes",
        steps: bars(["C", "Am", "F", "G"]),
        defaultTempo: 92
    )

    public static let twoFiveOne = Progression(
        id: "jazz-ii-V-I",
        name: "ii – V – I",
        detail: "The cadence most jazz standards turn on",
        steps: bars(["Dm7", "G7", "Cmaj7", "Cmaj7"]),
        defaultTempo: 100
    )

    public static let andalusian = Progression(
        id: "andalusian",
        name: "Andalusian",
        detail: "Am – G – F – E, the flamenco descent",
        steps: bars(["Am", "G", "F", "E"]),
        defaultTempo: 96
    )

    public static let twelveBarBlues = Progression(
        id: "blues-12-bar",
        name: "12-bar blues",
        detail: "E7 – A7 – B7",
        steps: bars(["E7", "E7", "E7", "E7", "A7", "A7", "E7", "E7", "B7", "A7", "E7", "B7"]),
        defaultTempo: 100
    )

    public static let canon = Progression(
        id: "canon",
        name: "Canon",
        detail: "Pachelbel's eight bars",
        steps: bars(["C", "G", "Am", "Em", "F", "C", "F", "G"]),
        defaultTempo: 88
    )

    public static let minorPop = Progression(
        id: "minor-vi-IV-I-V",
        name: "vi – IV – I – V",
        detail: "The same four chords, starting on the relative minor",
        steps: bars(["Am", "F", "C", "G"]),
        defaultTempo: 84
    )

    public static let all: [Progression] = [
        popFour,
        fifties,
        twoFiveOne,
        andalusian,
        twelveBarBlues,
        canon,
        minorPop,
    ]
}

/// Scores a practice run: which chords landed, which did not.
public struct ProgressionTrainer: Sendable {
    public struct StepScore: Sendable, Equatable, Identifiable {
        public var id: Int
        public var voicingID: String
        public var chordName: String
        /// Best match seen while this chord was the current one, 0...1.
        public var bestScore: Double
        public var isCorrect: Bool
    }

    /// What happened on this beat, so the UI can react.
    public struct BeatUpdate: Sendable, Equatable {
        public var stepIndex: Int
        public var beatInStep: Int
        public var isStepStart: Bool
        public var beatsElapsed: Int
        /// Set when a chord's time ran out and it was scored.
        public var scored: StepScore?
        public var isFinished: Bool
    }

    public private(set) var progression: Progression
    public private(set) var stepIndex: Int = 0
    public private(set) var beatInStep: Int = 0
    public private(set) var beatsElapsed: Int = 0
    public private(set) var scores: [StepScore] = []
    public private(set) var bestStreak: Int = 0

    /// Score a chord has to reach to count as played.
    public var passScore: Double
    /// How many beats to wait after a chord change before judging — the player needs a
    /// moment to move their fingers.
    public var settleBeats: Int = 1

    private var currentBestScore: Double = 0
    private var currentStreak: Int = 0
    private let evaluator = ChordEvaluator()

    public init(progression: Progression, passScore: Double = 0.75) {
        self.progression = progression
        self.passScore = passScore
    }

    public var currentVoicing: ChordVoicing? { progression.voicing(atStep: stepIndex) }

    public var isFinished: Bool { stepIndex >= progression.steps.count }

    public var correctCount: Int { scores.filter(\.isCorrect).count }

    public var accuracy: Double {
        guard !scores.isEmpty else { return 0 }
        return Double(correctCount) / Double(scores.count)
    }

    public var averageScore: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.map(\.bestScore).reduce(0, +) / Double(scores.count)
    }

    public mutating func reset() {
        stepIndex = 0
        beatInStep = 0
        beatsElapsed = 0
        scores = []
        bestStreak = 0
        currentBestScore = 0
        currentStreak = 0
    }

    public mutating func update(progression newProgression: Progression) {
        progression = newProgression
        reset()
    }

    /// Feeds one metronome beat plus whatever the tuner heard since the last one.
    public mutating func onBeat(chroma: ChromaProfile?) -> BeatUpdate? {
        guard !isFinished else { return nil }
        let step = progression.steps[stepIndex]
        let isStepStart = beatInStep == 0

        // Judge only after the settle window, and only against the chord that is current.
        if beatInStep >= settleBeats, let chroma, !chroma.isSilent, let voicing = currentVoicing {
            let evaluation = evaluator.evaluate(chroma: chroma, target: voicing, detection: nil)
            currentBestScore = max(currentBestScore, evaluation.score)
        }

        var scored: StepScore?
        beatInStep += 1
        beatsElapsed += 1

        if beatInStep >= step.beats {
            let isCorrect = currentBestScore >= passScore
            let score = StepScore(
                id: stepIndex,
                voicingID: step.voicingID,
                chordName: currentVoicing?.name ?? step.voicingID,
                bestScore: currentBestScore,
                isCorrect: isCorrect
            )
            scores.append(score)
            scored = score
            currentStreak = isCorrect ? currentStreak + 1 : 0
            bestStreak = max(bestStreak, currentStreak)
            currentBestScore = 0
            beatInStep = 0
            stepIndex += 1
        }

        return BeatUpdate(
            stepIndex: min(stepIndex, max(progression.steps.count - 1, 0)),
            beatInStep: beatInStep,
            isStepStart: isStepStart,
            beatsElapsed: beatsElapsed,
            scored: scored,
            isFinished: isFinished
        )
    }
}
