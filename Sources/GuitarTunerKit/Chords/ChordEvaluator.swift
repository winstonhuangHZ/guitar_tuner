import Foundation

/// Compares what is being played against a target shape, note by note and string by
/// string. This is what turns the detector into a practice tool: "you are close, but the
/// F♯ that the 2nd fret of the top string should add is missing".
public struct ChordEvaluation: Sendable, Equatable {
    public enum Verdict: String, Sendable, Equatable {
        /// Expected and clearly present.
        case correct
        /// Expected, but noticeably weaker than the rest of the chord.
        case weak
        /// Expected, but not heard at all.
        case missing
        /// Heard, but the target chord does not use it.
        case unexpected
    }

    public struct NoteAssessment: Sendable, Equatable, Identifiable {
        public var id: Int { pitchClass }
        public var pitchClass: Int
        public var name: String
        public var isExpected: Bool
        public var strength: Double
        public var verdict: Verdict
    }

    public struct StringAssessment: Sendable, Equatable, Identifiable {
        public var id: Int
        public var label: String
        public var expectedNote: Note
        public var strength: Double
        public var verdict: Verdict
    }

    public var targetName: String
    public var detectedName: String?
    public var detectedConfidence: Double
    public var notes: [NoteAssessment]
    public var strings: [StringAssessment]
    /// 0...1: share of the chord's notes that are present, minus a penalty for extras.
    public var score: Double
    public var isCorrect: Bool

    public var missingNoteNames: [String] {
        notes.filter { $0.verdict == .missing }.map(\.name)
    }

    public var unexpectedNoteNames: [String] {
        notes.filter { $0.verdict == .unexpected }.map(\.name)
    }

    public var weakNoteNames: [String] {
        notes.filter { $0.verdict == .weak }.map(\.name)
    }

    /// One-line summary for the UI.
    public var summary: String {
        if missingNoteNames.isEmpty && unexpectedNoteNames.isEmpty && weakNoteNames.isEmpty {
            return "\(targetName) sounds complete"
        }
        var parts: [String] = []
        if !missingNoteNames.isEmpty {
            parts.append("missing \(missingNoteNames.joined(separator: " "))")
        }
        if !weakNoteNames.isEmpty {
            parts.append("too quiet: \(weakNoteNames.joined(separator: " "))")
        }
        if !unexpectedNoteNames.isEmpty {
            parts.append("extra \(unexpectedNoteNames.joined(separator: " "))")
        }
        return parts.joined(separator: " · ")
    }

    public static let empty = ChordEvaluation(
        targetName: "",
        detectedName: nil,
        detectedConfidence: 0,
        notes: [],
        strings: [],
        score: 0,
        isCorrect: false
    )
}

public struct ChordEvaluator: Sendable {
    /// An expected note weaker than this (relative to the loudest note) counts as missing.
    public var missingThreshold: Double = 0.28
    /// An expected note weaker than this but above `missingThreshold` counts as weak.
    public var weakThreshold: Double = 0.45
    /// An unexpected note above this strength is flagged.
    public var unexpectedThreshold: Double = 0.6
    /// Score above which the chord counts as played correctly.
    public var correctScore: Double = 0.8

    public init() {}

    public func evaluate(
        chroma: ChromaProfile,
        target: ChordVoicing,
        detection: ChordDetection? = nil
    ) -> ChordEvaluation {
        // Compare against what this *shape* plays, not the theoretical chord: open C6 and
        // open C7 deliberately leave out the fifth, and reporting it as missing would be
        // wrong feedback.
        let expected = target.pitchClasses

        var assessments: [ChordEvaluation.NoteAssessment] = []
        for pitchClass in 0..<ChromaProfile.pitchClassCount {
            let weight = chroma.weight(ofPitchClass: pitchClass)
            let isExpected = expected.contains(pitchClass)
            let verdict: ChordEvaluation.Verdict
            if isExpected {
                if weight < missingThreshold {
                    verdict = .missing
                } else if weight < weakThreshold {
                    verdict = .weak
                } else {
                    verdict = .correct
                }
            } else if weight >= unexpectedThreshold {
                verdict = .unexpected
            } else {
                continue // Not expected and not really there: nothing to say about it.
            }
            assessments.append(
                ChordEvaluation.NoteAssessment(
                    pitchClass: pitchClass,
                    name: NoteName(rawValue: pitchClass)?.sharpName ?? "?",
                    isExpected: isExpected,
                    strength: weight,
                    verdict: verdict
                )
            )
        }

        // Per-string view: a shape's string only matters if the chord needs that note.
        var stringAssessments: [ChordEvaluation.StringAssessment] = []
        for index in 0..<min(target.tuning.strings.count, target.frets.count) {
            guard let note = target.note(forStringIndex: index) else { continue }
            let weight = chroma.weight(ofPitchClass: note.midiNumber % 12)
            let verdict: ChordEvaluation.Verdict
            if weight < missingThreshold {
                verdict = .missing
            } else if weight < weakThreshold {
                verdict = .weak
            } else {
                verdict = .correct
            }
            stringAssessments.append(
                ChordEvaluation.StringAssessment(
                    id: index,
                    label: target.tuning.strings[index].label,
                    expectedNote: note,
                    strength: weight,
                    verdict: verdict
                )
            )
        }

        let expectedCount = max(expected.count, 1)
        let presentCount = assessments.filter { $0.isExpected && $0.verdict != .missing }.count
        let missingCount = assessments.filter { $0.verdict == .missing }.count
        let extraCount = assessments.filter { $0.verdict == .unexpected }.count
        let raw = Double(presentCount) / Double(expectedCount) - 0.2 * Double(extraCount)
        let score = min(max(raw, 0), 1)

        return ChordEvaluation(
            targetName: target.name,
            detectedName: detection?.name,
            detectedConfidence: detection?.confidence ?? 0,
            notes: assessments,
            strings: stringAssessments,
            score: score,
            // "Correct" needs the shape to be complete and free of notes that do not
            // belong — a C major with a ringing F♯ is a different problem than a quiet one.
            isCorrect: score >= correctScore && missingCount == 0 && extraCount == 0
        )
    }
}
