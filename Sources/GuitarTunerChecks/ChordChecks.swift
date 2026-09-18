import Foundation
import GuitarTunerKit

/// Renders a voicing as audio: every sounding string with a decaying harmonic series.
private func renderChord(
    _ voicing: ChordVoicing,
    sampleRate: Double = 48_000,
    count: Int = 8192,
    amplitude: Double = 0.22,
    detuneCents: Double = 0,
    mutedStrings: Set<Int> = [],
    extraMIDINotes: [Int] = []
) -> [Float] {
    var samples = [Float](repeating: 0, count: count)
    let harmonicWeights = [1.0, 0.7, 0.5, 0.35, 0.25, 0.18]

    var midiNotes: [Int] = []
    for index in 0..<voicing.frets.count where !mutedStrings.contains(index) {
        if let note = voicing.note(forStringIndex: index) { midiNotes.append(note.midiNumber) }
    }
    midiNotes.append(contentsOf: extraMIDINotes)

    for midi in midiNotes {
        let fundamental = NoteMath.frequency(midiNumber: Double(midi)) * pow(2, detuneCents / 1200)
        for (offset, weight) in harmonicWeights.enumerated() {
            let frequency = fundamental * Double(offset + 1)
            guard frequency < sampleRate / 2 else { break }
            let step = 2 * Double.pi * frequency / sampleRate
            for index in 0..<count {
                samples[index] += Float(amplitude * weight * sin(step * Double(index)))
            }
        }
    }

    let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
    if peak > 0.95 {
        let scale = 0.95 / peak
        for index in samples.indices { samples[index] *= scale }
    }
    return samples
}

private func detect(
    _ samples: [Float],
    detection: inout ChordDetection,
    analyzer: ChromaAnalyzer,
    detector: ChordDetector,
    sampleRate: Double = 48_000
) {
    let chroma = analyzer.analyze(samples: samples, sampleRate: sampleRate)
    detection = detector.detect(chroma)
}

func runChordChecks(_ runner: CheckRunner) {
    runner.group("Chord library")

    runner.greater(ChordLibrary.guitar.count, 40, "library size")
    for voicing in ChordLibrary.guitar {
        runner.equal(voicing.frets.count, 6, "\(voicing.name) has six string slots")
        runner.expect(voicing.soundingStringCount >= 3, "\(voicing.name) sounds at least three strings")
        runner.expect(
            voicing.hasAllDefiningTones,
            "\(voicing.name) sounds every note the chord implies (has \(voicing.pitchClasses.sorted()), wants \(voicing.chordPitchClasses.sorted()))"
        )
    }

    let ids = ChordLibrary.guitar.map(\.id)
    runner.equal(Set(ids).count, ids.count, "voicing ids are unique")

    // Spot-check a few shapes against their frets.
    if let c = ChordLibrary.voicing(id: "C") {
        runner.equal(c.notes.map { $0.description() }, ["C3", "E3", "G3", "C4", "E4"], "open C notes")
        runner.equal(c.frets.compactMap { $0 }.count, 5, "open C sounds five strings")
    }
    if let e = ChordLibrary.voicing(id: "E") {
        runner.equal(e.notes.map { $0.description() }, ["E2", "B2", "E3", "G♯3", "B3", "E4"], "open E notes")
    }
    if let am7 = ChordLibrary.voicing(id: "Am7"), let c6 = ChordLibrary.voicing(id: "C6") {
        runner.equal(
            am7.chordPitchClasses,
            c6.chordPitchClasses,
            "Am7 and C6 are the same notes (the detector must use the bass to choose)"
        )
    }

    // MARK: - Detection

    runner.group("Chord detection")

    let analyzer = ChromaAnalyzer()
    let detector = ChordDetector()

    let silent = analyzer.analyze(samples: [Float](repeating: 0, count: 8192), sampleRate: 48_000)
    runner.expect(silent.isSilent, "silence produces no chroma")
    runner.isNil(detector.detect(silent).name, "silence detects no chord")

    let noise = CheckSignals.whiteNoise(count: 8192, amplitude: 0.2, seed: 3)
    let noiseDetection = detector.detect(analyzer.analyze(samples: noise, sampleRate: 48_000))
    runner.less(noiseDetection.confidence, 0.4, "white noise is not a confident chord")

    // A single note is not a chord.
    let singleNote = renderChord(
        ChordVoicing(id: "E2", root: .e, quality: .power, frets: [0, nil, nil, nil, nil, nil])
    )
    var singleDetection = ChordDetection.none
    detect(singleNote, detection: &singleDetection, analyzer: analyzer, detector: detector)
    runner.isNil(singleDetection.name, "a lone low E is not reported as a chord")
    runner.expect(
        singleDetection.quality != .major,
        "a lone low E does not become an E major (harmonics are not folded into the chroma)"
    )

    // Every voicing in the library should be recognised as itself.
    var correct = 0
    var mismatches: [String] = []
    for voicing in ChordLibrary.guitar {
        let audio = renderChord(voicing)
        var result = ChordDetection.none
        detect(audio, detection: &result, analyzer: analyzer, detector: detector)
        if result.name == voicing.name {
            correct += 1
        } else {
            mismatches.append("\(voicing.name) → \(result.name ?? "—") (\(String(format: "%.2f", result.score)))")
        }
    }
    runner.equal(correct, ChordLibrary.guitar.count, "every library voicing is identified (misses: \(mismatches.joined(separator: ", ")))")

    // MARK: - Chord quality

    let qualityCases: [(id: String, quality: ChordQuality)] = [
        ("E", .major), ("Em", .minor), ("E7", .dominantSeventh), ("Emaj7", .majorSeventh),
        ("Em7", .minorSeventh), ("Esus4", .sus4), ("E5", .power),
        ("A", .major), ("Am", .minor), ("Am7", .minorSeventh), ("Amaj7", .majorSeventh),
        ("D7", .dominantSeventh), ("Dm7", .minorSeventh), ("Bm7♭5", .halfDiminished),
        ("C6", .six), ("Cadd9", .addNine), ("Asus2", .sus2), ("Csus4", .sus4),
    ]
    for testCase in qualityCases {
        guard let voicing = ChordLibrary.voicing(id: testCase.id) else {
            runner.expect(false, "library is missing \(testCase.id)")
            continue
        }
        var result = ChordDetection.none
        detect(renderChord(voicing), detection: &result, analyzer: analyzer, detector: detector)
        runner.equal(
            result.quality,
            testCase.quality,
            "\(testCase.id) is heard as \(testCase.quality.displayName) (got \(result.name ?? "—"))"
        )
        runner.equal(result.root, voicing.root, "\(testCase.id) root")
    }

    // Detuned by a fifth of a semitone: still the same chord.
    if let voicing = ChordLibrary.voicing(id: "G") {
        var result = ChordDetection.none
        detect(renderChord(voicing, detuneCents: -20), detection: &result, analyzer: analyzer, detector: detector)
        runner.equal(result.name, "G", "G major is still G 20 cents flat")
        detect(renderChord(voicing, detuneCents: 20), detection: &result, analyzer: analyzer, detector: detector)
        runner.equal(result.name, "G", "G major is still G 20 cents sharp")
    }

    // Confidence ordering: a clean chord beats noise.
    if let voicing = ChordLibrary.voicing(id: "C") {
        var clean = ChordDetection.none
        detect(renderChord(voicing), detection: &clean, analyzer: analyzer, detector: detector)
        runner.greater(clean.confidence, 0.5, "a clean C major is confident (\(String(format: "%.2f", clean.confidence)))")
        runner.greater(clean.confidence, noiseDetection.confidence, "clean chord is more confident than noise")
    }

    // MARK: - Practice evaluation

    runner.group("Chord practice")

    let evaluator = ChordEvaluator()
    guard let cMajor = ChordLibrary.voicing(id: "C") else {
        runner.expect(false, "library is missing C")
        return
    }

    var detection = ChordDetection.none
    detect(renderChord(cMajor), detection: &detection, analyzer: analyzer, detector: detector)
    let perfect = evaluator.evaluate(
        chroma: analyzer.analyze(samples: renderChord(cMajor), sampleRate: 48_000),
        target: cMajor,
        detection: detection
    )
    runner.expect(perfect.isCorrect, "a clean C major passes (score \(String(format: "%.2f", perfect.score)), \(perfect.summary))")
    runner.equal(perfect.missingNoteNames, [], "no notes are missing")
    runner.equal(perfect.unexpectedNoteNames, [], "no extra notes")

    // The 3rd string is the only source of G in an open C: mute it and the G must be
    // reported missing (that is the useful feedback for a learner).
    let missingG = evaluator.evaluate(
        chroma: analyzer.analyze(samples: renderChord(cMajor, mutedStrings: [3]), sampleRate: 48_000),
        target: cMajor,
        detection: nil
    )
    runner.equal(missingG.missingNoteNames, ["G"], "muting the 3rd string is reported as a missing G")
    runner.expect(!missingG.isCorrect, "an incomplete chord is not correct")
    runner.less(missingG.score, perfect.score, "incomplete chord scores lower")

    // An F♯ does not belong in C major.
    let extraSharp = evaluator.evaluate(
        chroma: analyzer.analyze(
            samples: renderChord(cMajor, extraMIDINotes: [66]), // F♯4
            sampleRate: 48_000
        ),
        target: cMajor,
        detection: nil
    )
    runner.equal(extraSharp.unexpectedNoteNames, ["F♯"], "an added F♯ is reported as extra")
    runner.expect(!extraSharp.isCorrect, "a chord with an extra note is not correct")

    // Playing a different chord than the target must not score as correct.
    if let gMajor = ChordLibrary.voicing(id: "G") {
        let wrongChord = evaluator.evaluate(
            chroma: analyzer.analyze(samples: renderChord(gMajor), sampleRate: 48_000),
            target: cMajor,
            detection: nil
        )
        runner.expect(!wrongChord.isCorrect, "playing G against a C target is not correct")
        runner.expect(
            !wrongChord.missingNoteNames.isEmpty || !wrongChord.unexpectedNoteNames.isEmpty,
            "the wrong chord is explained (\(wrongChord.summary))"
        )
    }

    // Per-string feedback: every sounding string of a clean chord reads correct.
    let stringVerdicts = perfect.strings.map(\.verdict)
    runner.expect(
        stringVerdicts.allSatisfy { $0 == .correct },
        "every string of a clean open C reads correct (\(perfect.strings.map { "\($0.label):\($0.verdict.rawValue)" }.joined(separator: " ")))"
    )
}
