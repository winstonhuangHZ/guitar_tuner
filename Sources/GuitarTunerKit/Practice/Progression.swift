import Foundation

/// The key a progression is played in.
public struct ProgressionKey: Sendable, Equatable, Hashable, Identifiable, Codable {
    public var tonic: NoteName
    public var isMinor: Bool

    public init(tonic: NoteName, isMinor: Bool = false) {
        self.tonic = tonic
        self.isMinor = isMinor
    }

    public var id: String { "\(tonic.rawValue)-\(isMinor ? "m" : "M")" }

    public var tonicPitchClass: Int { tonic.rawValue }

    /// `C`, `A minor`…
    public var displayName: String { isMinor ? "\(tonic.sharpName) minor" : tonic.sharpName }

    /// Keys that read better with flats (used for the picker's labels only).
    public var prefersFlats: Bool {
        [NoteName.f, .aSharp, .dSharp, .gSharp, .cSharp].contains(tonic)
    }

    public static let all: [ProgressionKey] = {
        let majors = NoteName.allCases.map { ProgressionKey(tonic: $0, isMinor: false) }
        let minors = NoteName.allCases.map { ProgressionKey(tonic: $0, isMinor: true) }
        return majors + minors
    }()

    public static let cMajor = ProgressionKey(tonic: .c)

    public static func key(id: String) -> ProgressionKey? {
        all.first { $0.id == id }
    }
}

/// One chord of a resolved progression.
public struct ProgressionStep: Sendable, Equatable, Identifiable, Codable {
    public var id: Int
    /// The shape to play — generated from a movable shape, so any key works.
    public var voicing: ChordVoicing
    public var beats: Int
    /// Roman numeral, e.g. `I`, `vi`.
    public var degree: String

    public init(id: Int, voicing: ChordVoicing, beats: Int = 4, degree: String = "") {
        self.id = id
        self.voicing = voicing
        self.beats = max(1, beats)
        self.degree = degree
    }

    public var chordName: String { voicing.name }
}

/// A progression ready to play: concrete shapes in one key.
public struct Progression: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var templateID: String
    public var name: String
    public var detail: String
    public var key: ProgressionKey
    public var steps: [ProgressionStep]
    public var defaultTempo: Double

    public init(
        id: String,
        templateID: String,
        name: String,
        detail: String,
        key: ProgressionKey,
        steps: [ProgressionStep],
        defaultTempo: Double = 80
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.detail = detail
        self.key = key
        self.steps = steps
        self.defaultTempo = defaultTempo
    }

    public var totalBeats: Int { steps.reduce(0) { $0 + $1.beats } }

    public func voicing(atStep index: Int) -> ChordVoicing? {
        guard steps.indices.contains(index) else { return nil }
        return steps[index].voicing
    }

    public var chordNames: [String] { steps.map(\.chordName) }

    /// `I – V – vi – IV in G`
    public var displayName: String { "\(name) in \(key.displayName)" }
}

/// A progression written in scale degrees, which is what makes it playable in any key.
public struct ProgressionTemplate: Sendable, Equatable, Identifiable, Codable {
    public struct Degree: Sendable, Equatable, Codable {
        /// Semitones above the tonic.
        public var semitones: Int
        public var quality: ChordQuality
        public var beats: Int
        public var roman: String

        public init(semitones: Int, quality: ChordQuality, beats: Int = 4, roman: String) {
            self.semitones = semitones
            self.quality = quality
            self.beats = max(1, beats)
            self.roman = roman
        }
    }

    public var id: String
    public var name: String
    public var detail: String
    public var degrees: [Degree]
    public var defaultTempo: Double
    /// Minor-key progressions use the minor rows of the key picker by default.
    public var prefersMinorKey: Bool

    public init(
        id: String,
        name: String,
        detail: String,
        degrees: [Degree],
        defaultTempo: Double = 80,
        prefersMinorKey: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.degrees = degrees
        self.defaultTempo = defaultTempo
        self.prefersMinorKey = prefersMinorKey
    }

    /// The roman numerals, for the picker.
    public var romanNumerals: String {
        degrees.map(\.roman).joined(separator: " – ")
    }

    /// Builds concrete, playable shapes in `key`.
    public func resolve(in key: ProgressionKey) -> Progression {
        let steps = degrees.enumerated().compactMap { index, degree -> ProgressionStep? in
            let pitchClass = ((key.tonicPitchClass + degree.semitones) % 12 + 12) % 12
            guard let voicing = ChordShapes.voicing(rootPitchClass: pitchClass, quality: degree.quality) else {
                return nil
            }
            return ProgressionStep(id: index, voicing: voicing, beats: degree.beats, degree: degree.roman)
        }
        return Progression(
            id: "\(id)-\(key.id)",
            templateID: id,
            name: name,
            detail: detail,
            key: key,
            steps: steps,
            defaultTempo: defaultTempo
        )
    }

    public static func template(id: String) -> ProgressionTemplate? {
        all.first { $0.id == id }
    }

    private static func degrees(_ entries: [(Int, ChordQuality, String)], beats: Int = 4) -> [Degree] {
        entries.map { Degree(semitones: $0.0, quality: $0.1, beats: beats, roman: $0.2) }
    }

    public static let popFour = ProgressionTemplate(
        id: "pop-I-V-vi-IV",
        name: "I – V – vi – IV",
        detail: "The four chords behind a huge number of songs",
        degrees: degrees([(0, .major, "I"), (7, .major, "V"), (9, .minor, "vi"), (5, .major, "IV")]),
        defaultTempo: 84
    )

    public static let fifties = ProgressionTemplate(
        id: "fifties-I-vi-IV-V",
        name: "I – vi – IV – V",
        detail: "Doo-wop changes",
        degrees: degrees([(0, .major, "I"), (9, .minor, "vi"), (5, .major, "IV"), (7, .major, "V")]),
        defaultTempo: 92
    )

    public static let twoFiveOne = ProgressionTemplate(
        id: "jazz-ii-V-I",
        name: "ii – V – I",
        detail: "The cadence most jazz standards turn on",
        degrees: degrees([
            (2, .minorSeventh, "ii"),
            (7, .dominantSeventh, "V"),
            (0, .majorSeventh, "I"),
            (0, .majorSeventh, "I"),
        ]),
        defaultTempo: 100
    )

    public static let andalusian = ProgressionTemplate(
        id: "andalusian",
        name: "i – ♭VII – ♭VI – V",
        detail: "The flamenco descent",
        degrees: degrees([(0, .minor, "i"), (10, .major, "♭VII"), (8, .major, "♭VI"), (7, .major, "V")]),
        defaultTempo: 96,
        prefersMinorKey: true
    )

    public static let twelveBarBlues = ProgressionTemplate(
        id: "blues-12-bar",
        name: "12-bar blues",
        detail: "I – IV – V with dominant sevenths",
        degrees: degrees([
            (0, .dominantSeventh, "I"), (0, .dominantSeventh, "I"),
            (0, .dominantSeventh, "I"), (0, .dominantSeventh, "I"),
            (5, .dominantSeventh, "IV"), (5, .dominantSeventh, "IV"),
            (0, .dominantSeventh, "I"), (0, .dominantSeventh, "I"),
            (7, .dominantSeventh, "V"), (5, .dominantSeventh, "IV"),
            (0, .dominantSeventh, "I"), (7, .dominantSeventh, "V"),
        ]),
        defaultTempo: 100
    )

    public static let canon = ProgressionTemplate(
        id: "canon",
        name: "I – V – vi – iii – IV – I – IV – V",
        detail: "Pachelbel's eight bars",
        degrees: degrees([
            (0, .major, "I"), (7, .major, "V"), (9, .minor, "vi"), (4, .minor, "iii"),
            (5, .major, "IV"), (0, .major, "I"), (5, .major, "IV"), (7, .major, "V"),
        ]),
        defaultTempo: 88
    )

    public static let minorPop = ProgressionTemplate(
        id: "minor-vi-IV-I-V",
        name: "vi – IV – I – V",
        detail: "The same four chords, starting on the relative minor",
        degrees: degrees([(9, .minor, "vi"), (5, .major, "IV"), (0, .major, "I"), (7, .major, "V")]),
        defaultTempo: 84
    )

    public static let bluesRock = ProgressionTemplate(
        id: "rock-I-bVII-IV",
        name: "I – ♭VII – IV",
        detail: "Mixolydian rock changes",
        degrees: degrees([(0, .major, "I"), (10, .major, "♭VII"), (5, .major, "IV"), (0, .major, "I")]),
        defaultTempo: 104
    )

    public static let all: [ProgressionTemplate] = [
        popFour,
        fifties,
        twoFiveOne,
        andalusian,
        twelveBarBlues,
        canon,
        minorPop,
        bluesRock,
    ]
}

/// Scores a practice run: which chords landed, which did not.
public struct ProgressionTrainer: Sendable {
    public struct StepScore: Sendable, Equatable, Identifiable {
        public var id: Int
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
        if beatInStep >= settleBeats, let chroma, !chroma.isSilent {
            let evaluation = evaluator.evaluate(chroma: chroma, target: step.voicing, detection: nil)
            currentBestScore = max(currentBestScore, evaluation.score)
        }

        var scored: StepScore?
        beatInStep += 1
        beatsElapsed += 1

        if beatInStep >= step.beats {
            let isCorrect = currentBestScore >= passScore
            let score = StepScore(
                id: stepIndex,
                chordName: step.voicing.name,
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
