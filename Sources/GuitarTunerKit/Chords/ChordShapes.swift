import Foundation

/// Movable chord shapes — the way guitarists actually transpose.
///
/// A shape is a set of frets relative to a root fret, plus which string carries the root.
/// Sliding the E shape up two frets turns E into F♯; the A shape covers the roots whose
/// lowest comfortable position is on the 5th string. This is what lets a progression be
/// played in any key instead of only the handful of keys the written-out library covers.
public struct MovableChordShape: Sendable, Hashable {
    public var name: String
    /// Frets with the shape at its home position; `nil` is a muted string.
    public var frets: [Int?]
    /// Index of the string that carries the root note (0 = lowest string).
    public var rootStringIndex: Int
    public var quality: ChordQuality

    public init(name: String, frets: [Int?], rootStringIndex: Int, quality: ChordQuality) {
        self.name = name
        self.frets = frets
        self.rootStringIndex = rootStringIndex
        self.quality = quality
    }

    /// Fret the shape has to sit at so its root becomes `rootPitchClass`, or `nil` when
    /// that would push it off the neck.
    public func position(
        forRootPitchClass rootPitchClass: Int,
        tuning: TuningPreset = .standardGuitar
    ) -> Int? {
        guard tuning.strings.indices.contains(rootStringIndex),
              frets.indices.contains(rootStringIndex) else { return nil }
        let openPitchClass = tuning.strings[rootStringIndex].midiNumber % 12
        let shapeRootFret = frets[rootStringIndex] ?? 0
        let position = (((rootPitchClass - openPitchClass) % 12 + 12) % 12) - shapeRootFret
        guard position >= 0 else { return nil }
        let highest = frets.compactMap { $0 }.max().map { $0 + position } ?? position
        guard highest <= 15 else { return nil }
        return position
    }

    /// The shape as a concrete voicing at `position`.
    public func voicing(
        at position: Int,
        rootPitchClass: Int,
        tuning: TuningPreset = .standardGuitar
    ) -> ChordVoicing {
        let frets = frets.map { $0.map { $0 + position } }
        let root = NoteName(rawValue: ((rootPitchClass % 12) + 12) % 12) ?? .c
        return ChordVoicing(
            id: "shape-\(name.lowercased())-\(root.rawValue)-\(quality.rawValue)",
            root: root,
            quality: quality,
            tuning: tuning,
            frets: frets,
            baseFret: max(1, frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 1)
        )
    }
}

/// The movable shapes the app knows, by quality.
public enum ChordShapes {
    /// Home positions on a standard-tuned guitar.
    public static let all: [MovableChordShape] = [
        // Majors
        MovableChordShape(name: "E", frets: [0, 2, 2, 1, 0, 0], rootStringIndex: 0, quality: .major),
        MovableChordShape(name: "A", frets: [nil, 0, 2, 2, 2, 0], rootStringIndex: 1, quality: .major),
        // Minors
        MovableChordShape(name: "Em", frets: [0, 2, 2, 0, 0, 0], rootStringIndex: 0, quality: .minor),
        MovableChordShape(name: "Am", frets: [nil, 0, 2, 2, 1, 0], rootStringIndex: 1, quality: .minor),
        // Suspended
        MovableChordShape(name: "Esus4", frets: [0, 2, 2, 2, 0, 0], rootStringIndex: 0, quality: .sus4),
        MovableChordShape(name: "Asus4", frets: [nil, 0, 2, 2, 3, 0], rootStringIndex: 1, quality: .sus4),
        MovableChordShape(name: "Asus2", frets: [nil, 0, 2, 2, 0, 0], rootStringIndex: 1, quality: .sus2),
        // Sevenths
        MovableChordShape(name: "E7", frets: [0, 2, 0, 1, 0, 0], rootStringIndex: 0, quality: .dominantSeventh),
        MovableChordShape(name: "A7", frets: [nil, 0, 2, 0, 2, 0], rootStringIndex: 1, quality: .dominantSeventh),
        MovableChordShape(name: "Emaj7", frets: [0, 2, 1, 1, 0, 0], rootStringIndex: 0, quality: .majorSeventh),
        MovableChordShape(name: "Amaj7", frets: [nil, 0, 2, 1, 2, 0], rootStringIndex: 1, quality: .majorSeventh),
        MovableChordShape(name: "Em7", frets: [0, 2, 0, 0, 0, 0], rootStringIndex: 0, quality: .minorSeventh),
        MovableChordShape(name: "Am7", frets: [nil, 0, 2, 0, 1, 0], rootStringIndex: 1, quality: .minorSeventh),
        // Power chords
        MovableChordShape(name: "E5", frets: [0, 2, 2, nil, nil, nil], rootStringIndex: 0, quality: .power),
        MovableChordShape(name: "A5", frets: [nil, 0, 2, 2, nil, nil], rootStringIndex: 1, quality: .power),
    ]

    public static func shapes(for quality: ChordQuality) -> [MovableChordShape] {
        all.filter { $0.quality == quality }
    }

    /// A playable voicing for any root/quality combination the shapes cover.
    ///
    /// The position nearest the nut wins, which is also what a player would choose: B
    /// major comes out as the A shape at fret 2, not the E shape at fret 7.
    public static func voicing(
        rootPitchClass: Int,
        quality: ChordQuality,
        tuning: TuningPreset = .standardGuitar
    ) -> ChordVoicing? {
        let candidates = shapes(for: quality).compactMap { shape -> (MovableChordShape, Int)? in
            guard let position = shape.position(forRootPitchClass: rootPitchClass, tuning: tuning) else {
                return nil
            }
            return (shape, position)
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return best.0.voicing(
            at: best.1,
            rootPitchClass: rootPitchClass,
            tuning: tuning
        )
    }
}
