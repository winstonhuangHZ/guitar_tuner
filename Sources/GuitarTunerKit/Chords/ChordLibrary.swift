import Foundation

/// Common guitar voicings, written out by hand.
///
/// Fret numbers are in tuning order (6th string → 1st string); `nil` is a muted string.
public enum ChordLibrary {
    public static let guitar: [ChordVoicing] = [
        // MARK: Open majors
        voicing("C", .c, .major, [nil, 3, 2, 0, 1, 0]),
        voicing("G", .g, .major, [3, 2, 0, 0, 0, 3]),
        voicing("D", .d, .major, [nil, nil, 0, 2, 3, 2]),
        voicing("A", .a, .major, [nil, 0, 2, 2, 2, 0]),
        voicing("E", .e, .major, [0, 2, 2, 1, 0, 0]),
        voicing("F", .f, .major, [1, 3, 3, 2, 1, 1]),
        voicing("B♭", .aSharp, .major, [nil, 1, 3, 3, 3, 1]),
        voicing("B", .b, .major, [nil, 2, 4, 4, 4, 2]),

        // MARK: Open minors
        voicing("Am", .a, .minor, [nil, 0, 2, 2, 1, 0]),
        voicing("Em", .e, .minor, [0, 2, 2, 0, 0, 0]),
        voicing("Dm", .d, .minor, [nil, nil, 0, 2, 3, 1]),
        voicing("Bm", .b, .minor, [nil, 2, 4, 4, 3, 2]),
        voicing("F♯m", .fSharp, .minor, [2, 4, 4, 2, 2, 2]),
        voicing("Cm", .c, .minor, [nil, 3, 5, 5, 4, 3], baseFret: 3),
        voicing("Gm", .g, .minor, [3, 5, 5, 3, 3, 3], baseFret: 3),
        voicing("Fm", .f, .minor, [1, 3, 3, 1, 1, 1]),

        // MARK: Sevenths
        voicing("C7", .c, .dominantSeventh, [nil, 3, 2, 3, 1, 0]),
        voicing("D7", .d, .dominantSeventh, [nil, nil, 0, 2, 1, 2]),
        voicing("E7", .e, .dominantSeventh, [0, 2, 0, 1, 0, 0]),
        voicing("G7", .g, .dominantSeventh, [3, 2, 0, 0, 0, 1]),
        voicing("A7", .a, .dominantSeventh, [nil, 0, 2, 0, 2, 0]),
        voicing("B7", .b, .dominantSeventh, [nil, 2, 1, 2, 0, 2]),
        voicing("F7", .f, .dominantSeventh, [1, 3, 1, 2, 1, 1]),
        voicing("Cmaj7", .c, .majorSeventh, [nil, 3, 2, 0, 0, 0]),
        voicing("Dmaj7", .d, .majorSeventh, [nil, nil, 0, 2, 2, 2]),
        voicing("Emaj7", .e, .majorSeventh, [0, 2, 1, 1, 0, 0]),
        voicing("Fmaj7", .f, .majorSeventh, [nil, nil, 3, 2, 1, 0]),
        voicing("Gmaj7", .g, .majorSeventh, [3, 2, 0, 0, 0, 2]),
        voicing("Amaj7", .a, .majorSeventh, [nil, 0, 2, 1, 2, 0]),
        voicing("Am7", .a, .minorSeventh, [nil, 0, 2, 0, 1, 0]),
        voicing("Em7", .e, .minorSeventh, [0, 2, 0, 0, 0, 0]),
        voicing("Dm7", .d, .minorSeventh, [nil, nil, 0, 2, 1, 1]),
        voicing("Bm7", .b, .minorSeventh, [nil, 2, 4, 2, 3, 2]),
        voicing("Gm7", .g, .minorSeventh, [3, 5, 3, 3, 3, 3], baseFret: 3),

        // MARK: Suspended, added and sixth
        voicing("Csus4", .c, .sus4, [nil, 3, 3, 0, 1, 1]),
        voicing("Dsus4", .d, .sus4, [nil, nil, 0, 2, 3, 3]),
        voicing("Asus2", .a, .sus2, [nil, 0, 2, 2, 0, 0]),
        voicing("Asus4", .a, .sus4, [nil, 0, 2, 2, 3, 0]),
        voicing("Esus4", .e, .sus4, [0, 2, 2, 2, 0, 0]),
        voicing("Cadd9", .c, .addNine, [nil, 3, 2, 0, 3, 0]),
        voicing("C6", .c, .six, [nil, 3, 2, 2, 1, 0]),
        voicing("Bm7♭5", .b, .halfDiminished, [nil, 2, 3, 2, 3, nil]),

        // MARK: Power chords
        voicing("E5", .e, .power, [0, 2, 2, nil, nil, nil]),
        voicing("A5", .a, .power, [nil, 0, 2, 2, nil, nil]),
        voicing("D5", .d, .power, [nil, nil, 0, 2, 3, nil]),
        voicing("G5", .g, .power, [3, 5, 5, nil, nil, nil], baseFret: 3),
    ]

    /// Voicings grouped by root for the picker.
    public static let guitarByRoot: [(root: NoteName, voicings: [ChordVoicing])] = {
        var order: [NoteName] = []
        var buckets: [NoteName: [ChordVoicing]] = [:]
        for voicing in guitar {
            if buckets[voicing.root] == nil {
                order.append(voicing.root)
                buckets[voicing.root] = []
            }
            buckets[voicing.root]?.append(voicing)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }()

    /// Candidate chords for the detector: every root with every quality that at least one
    /// voicing in the library uses.
    public static let detectableQualities: [ChordQuality] = {
        var seen: [ChordQuality] = []
        for voicing in guitar where !seen.contains(voicing.quality) {
            seen.append(voicing.quality)
        }
        return seen
    }()

    public static func voicing(id: String) -> ChordVoicing? {
        guitar.first { $0.id == id }
    }

    private static func voicing(
        _ id: String,
        _ root: NoteName,
        _ quality: ChordQuality,
        _ frets: [Int?],
        baseFret: Int = 1
    ) -> ChordVoicing {
        ChordVoicing(id: id, root: root, quality: quality, frets: frets, baseFret: baseFret)
    }
}
