import Foundation

/// One metronome setting: a time signature plus how its beats are grouped.
///
/// The grouping is what makes odd metres usable. 7/8 is not seven identical beats, it is
/// 2+2+3 (or 3+2+2), and hearing where the groups turn around is the whole point of
/// practising it.
public struct MetronomePattern: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    /// Beats per bar (the numerator).
    public var beats: Int
    /// Note value that gets one beat (the denominator): 4 = quarter, 8 = eighth.
    public var noteValue: Int
    /// Group lengths; must sum to `beats`. A single group means "accent beat one only".
    public var grouping: [Int]
    /// Extra ticks between beats (1 = none, 2 = eighths, 3 = triplets).
    public var subdivision: Int

    public init(
        id: String,
        name: String,
        beats: Int,
        noteValue: Int,
        grouping: [Int],
        subdivision: Int = 1
    ) {
        self.id = id
        self.name = name
        self.beats = max(1, beats)
        self.noteValue = noteValue
        self.subdivision = max(1, subdivision)
        let normalized = grouping.filter { $0 > 0 }
        self.grouping = normalized.reduce(0, +) == beats ? normalized : [beats]
    }

    public static let minimumTempo = 30.0
    public static let maximumTempo = 260.0

    /// Time signature as players write it.
    public var timeSignature: String { "\(beats)/\(noteValue)" }

    /// `4/4`, `7/8 (2+2+3)`…
    public var displayName: String {
        grouping.count > 1
            ? "\(timeSignature) (\(grouping.map(String.init).joined(separator: "+")))"
            : timeSignature
    }

    /// Seconds per beat at a tempo that counts the denominator note.
    public func beatDuration(tempo: Double) -> Double {
        60.0 / min(max(tempo, Self.minimumTempo), Self.maximumTempo)
    }

    /// Accent for the tick at `index` within the bar (one beat = `subdivision` ticks).
    public func accent(atTick index: Int) -> MetronomeAccent {
        let ticksPerBeat = subdivision
        let barTicks = beats * ticksPerBeat
        guard barTicks > 0 else { return .beat }
        let tick = ((index % barTicks) + barTicks) % barTicks
        guard tick % ticksPerBeat == 0 else { return .subdivision }

        let beat = tick / ticksPerBeat
        if beat == 0 { return .downbeat }
        var boundary = 0
        for group in grouping.dropLast() {
            boundary += group
            if beat == boundary { return .groupStart }
        }
        return .beat
    }

    /// Ticks in one bar.
    public var ticksPerBar: Int { beats * subdivision }

    public static let commonTime = MetronomePattern(id: "4-4", name: "Common time", beats: 4, noteValue: 4, grouping: [4])
    public static let simpleThree = MetronomePattern(id: "3-4", name: "Waltz", beats: 3, noteValue: 4, grouping: [3])
    public static let simpleTwo = MetronomePattern(id: "2-4", name: "March", beats: 2, noteValue: 4, grouping: [2])

    /// Everything the picker offers. Odd metres come with their usual groupings.
    public static let all: [MetronomePattern] = [
        simpleTwo,
        simpleThree,
        commonTime,
        MetronomePattern(id: "5-4", name: "5/4 (3+2)", beats: 5, noteValue: 4, grouping: [3, 2]),
        MetronomePattern(id: "6-4", name: "6/4 (3+3)", beats: 6, noteValue: 4, grouping: [3, 3]),
        MetronomePattern(id: "7-4", name: "7/4 (4+3)", beats: 7, noteValue: 4, grouping: [4, 3]),
        MetronomePattern(id: "3-8", name: "3/8", beats: 3, noteValue: 8, grouping: [3]),
        MetronomePattern(id: "5-8-3-2", name: "5/8 (3+2)", beats: 5, noteValue: 8, grouping: [3, 2]),
        MetronomePattern(id: "5-8-2-3", name: "5/8 (2+3)", beats: 5, noteValue: 8, grouping: [2, 3]),
        MetronomePattern(id: "6-8", name: "6/8 (3+3)", beats: 6, noteValue: 8, grouping: [3, 3]),
        MetronomePattern(id: "7-8-2-2-3", name: "7/8 (2+2+3)", beats: 7, noteValue: 8, grouping: [2, 2, 3]),
        MetronomePattern(id: "7-8-3-2-2", name: "7/8 (3+2+2)", beats: 7, noteValue: 8, grouping: [3, 2, 2]),
        MetronomePattern(id: "7-8-2-3-2", name: "7/8 (2+3+2)", beats: 7, noteValue: 8, grouping: [2, 3, 2]),
        MetronomePattern(id: "9-8-3-3-3", name: "9/8 (3+3+3)", beats: 9, noteValue: 8, grouping: [3, 3, 3]),
        MetronomePattern(id: "9-8-2-2-2-3", name: "9/8 (2+2+2+3)", beats: 9, noteValue: 8, grouping: [2, 2, 2, 3]),
        MetronomePattern(id: "10-8-3-3-2-2", name: "10/8 (3+3+2+2)", beats: 10, noteValue: 8, grouping: [3, 3, 2, 2]),
        MetronomePattern(id: "10-8-2-3-2-3", name: "10/8 (2+3+2+3)", beats: 10, noteValue: 8, grouping: [2, 3, 2, 3]),
        MetronomePattern(id: "11-8", name: "11/8 (3+3+3+2)", beats: 11, noteValue: 8, grouping: [3, 3, 3, 2]),
        MetronomePattern(id: "12-8", name: "12/8 (4×3)", beats: 12, noteValue: 8, grouping: [3, 3, 3, 3]),
    ]

    public static func pattern(id: String) -> MetronomePattern? {
        all.first { $0.id == id }
    }
}

public enum MetronomeAccent: String, Sendable, Equatable {
    /// First beat of the bar.
    case downbeat
    /// First beat of a group inside the bar.
    case groupStart
    /// Any other beat.
    case beat
    /// An in-between tick produced by the subdivision.
    case subdivision
}

/// Where the metronome is right now. Kept away from the audio scheduling so the beat maths
/// can be verified without an audio device.
public struct MetronomeClock: Sendable {
    public private(set) var pattern: MetronomePattern
    public private(set) var tempo: Double
    public private(set) var tickIndex: Int

    public init(pattern: MetronomePattern = .commonTime, tempo: Double = 90, tickIndex: Int = 0) {
        self.pattern = pattern
        self.tempo = tempo
        self.tickIndex = tickIndex
    }

    /// Seconds between ticks.
    public var tickDuration: Double {
        pattern.beatDuration(tempo: tempo) / Double(pattern.subdivision)
    }

    public var accent: MetronomeAccent { pattern.accent(atTick: tickIndex) }

    /// Beat within the bar counting from 1, the way a player counts.
    public var beatNumber: Int {
        (tickIndex / pattern.subdivision) % pattern.beats + 1
    }

    public var barNumber: Int {
        tickIndex / max(pattern.ticksPerBar, 1) + 1
    }

    public mutating func advance() {
        tickIndex += 1
    }

    public mutating func update(pattern: MetronomePattern? = nil, tempo: Double? = nil) {
        if let pattern { self.pattern = pattern }
        if let tempo {
            self.tempo = min(max(tempo, MetronomePattern.minimumTempo), MetronomePattern.maximumTempo)
        }
    }

    public mutating func reset() {
        tickIndex = 0
    }
}
