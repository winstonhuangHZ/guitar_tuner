import Foundation
import GuitarTunerKit

/// A chroma profile that looks like the given chord is being played.
private func chroma(for voicing: ChordVoicing, strength: Double = 1.0) -> ChromaProfile {
    var weights = [Double](repeating: 0, count: ChromaProfile.pitchClassCount)
    for pitchClass in voicing.pitchClasses { weights[pitchClass] = strength }
    return ChromaProfile(
        weights: weights,
        noteStrengths: [],
        firstMIDINote: ChromaAnalyzer.defaultFirstMIDINote,
        isSilent: false
    )
}

private func scratchSettingsStore(_ name: String) -> SettingsStore {
    let suite = "guitar-tuner-checks-\(name)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return SettingsStore(defaults: defaults, key: "settings")
}

func runSettingsChecks(_ runner: CheckRunner) {
    runner.group("Settings")

    let store = scratchSettingsStore("settings")
    let loaded = store.load()
    runner.equal(loaded.preset.id, TuningPreset.standardGuitar.id, "empty store falls back to defaults")
    runner.equal(loaded.referencePitch, 440, "default reference pitch")
    runner.equal(loaded.metronomePatternID, MetronomePattern.commonTime.id, "default metronome pattern")

    var settings = TunerSettings.default
    settings.presetID = "guitar-drop-d"
    settings.referencePitch = 442
    settings.inputMode = .pickup
    settings.capoFret = 3
    settings.lockedStringID = 2
    settings.metronomePatternID = "7-8-2-2-3"
    settings.metronomeTempo = 132
    settings.metronomeVolume = 0.4
    settings.inputDeviceID = "device-42"
    settings.practiceVoicingID = "Am7"
    settings.progressionID = Progression.popFour.id
    settings.recordsTuningHistory = false
    store.save(settings)

    let restored = store.load()
    runner.equal(restored.presetID, "guitar-drop-d", "preset survives a restart")
    runner.equal(restored.referencePitch, 442, "reference pitch survives a restart")
    runner.equal(restored.inputMode, .pickup, "input mode survives a restart")
    runner.equal(restored.capoFret, 3, "capo survives a restart")
    runner.equal(restored.lockedStringID, 2, "locked string survives a restart")
    runner.equal(restored.metronomePatternID, "7-8-2-2-3", "metronome pattern survives a restart")
    runner.near(restored.metronomeTempo, 132, accuracy: 0.001, "tempo survives a restart")
    runner.equal(restored.inputDeviceID, "device-42", "input device survives a restart")
    runner.equal(restored.practiceVoicingID, "Am7", "practice chord survives a restart")
    runner.equal(restored.recordsTuningHistory, false, "history opt-out survives a restart")

    store.clear()
    runner.equal(store.load().presetID, TuningPreset.standardGuitar.id, "clearing restores defaults")

    // A file written by an older or edited build must not produce nonsense.
    var broken = TunerSettings.default
    broken.referencePitch = 900
    broken.inTuneToleranceCents = 99
    broken.capoFret = 40
    broken.metronomeTempo = 9000
    broken.metronomeVolume = 5
    broken.presetID = "does-not-exist"
    broken.metronomePatternID = "nope"
    broken.progressionID = "nope"
    broken.practiceVoicingID = "nope"
    broken.lockedStringID = 99
    let fixed = broken.sanitized()
    runner.equal(fixed.referencePitch, 466, "reference pitch is clamped")
    runner.equal(fixed.inTuneToleranceCents, 25, "tolerance is clamped")
    runner.equal(fixed.capoFret, TuningPreset.maximumCapoFret, "capo is clamped")
    runner.equal(fixed.metronomeTempo, MetronomePattern.maximumTempo, "tempo is clamped")
    runner.near(fixed.metronomeVolume, 1, accuracy: 1e-9, "volume is clamped")
    runner.equal(fixed.preset.id, TuningPreset.standardGuitar.id, "unknown preset falls back")
    runner.equal(fixed.metronomePatternID, MetronomePattern.commonTime.id, "unknown pattern falls back")
    runner.equal(fixed.progressionID, Progression.all.first?.id, "unknown progression falls back")
    runner.isNil(fixed.lockedStringID, "impossible string lock is dropped")
    runner.equal(fixed.preset.strings.count, 6, "fallback preset is playable")
}

func runCapoChecks(_ runner: CheckRunner) {
    runner.group("Capo")

    let standard = TuningPreset.standardGuitar
    let open = standard.strings(capoFret: 0).map(\.noteName)
    runner.equal(open, ["E2", "A2", "D3", "G3", "B3", "E4"], "no capo keeps the open strings")

    let capoTwo = standard.strings(capoFret: 2)
    runner.equal(
        capoTwo.map(\.noteName),
        ["F♯2", "B2", "E3", "A3", "C♯4", "F♯4"],
        "capo 2 moves every target up a whole tone"
    )
    runner.equal(capoTwo.map(\.label), standard.strings.map(\.label), "string positions keep their labels")
    runner.equal(capoTwo.map(\.id), standard.strings.map(\.id), "string ids stay stable")

    let capoSeven = standard.strings(capoFret: 7)
    runner.near(
        capoSeven[0].frequency(),
        NoteMath.frequency(of: Note(midiNumber: 47)),
        accuracy: 0.001,
        "capo 7 on the low E gives B2"
    )
    runner.near(
        standard.frequencyRange(capoFret: 3)?.lowerBound ?? 0,
        NoteMath.frequency(of: Note(midiNumber: 43)),
        accuracy: 0.001,
        "frequency range moves with the capo"
    )

    // The evaluator must compare against the capoed pitch, not the open string.
    var evaluator = TunerEvaluator()
    var selection = TuningSelection.default
    selection.capoFret = 2
    let capoedLowE = NoteMath.frequency(of: Note(midiNumber: 42)) // F♯2
    let stabilized = StabilizedPitch(
        frequency: capoedLowE,
        rawFrequency: capoedLowE,
        clarity: 0.95,
        analysis: PitchAnalysis(
            rms: 0.05,
            level: 0.5,
            gate: 0.003,
            frequency: capoedLowE,
            clarity: 0.95,
            lag: nil,
            isGated: false
        ),
        isHeld: false
    )
    let reading = evaluator.evaluate(stabilized, selection: selection, timestamp: 0)
    runner.equal(reading.target?.noteName, "F♯2", "capo 2 retargets the low string to F♯2")
    runner.near(reading.cents ?? .nan, 0, accuracy: 0.05, "capoed string reads in tune")

    // Locking a string still works with a capo.
    var locked = selection
    locked.stringSelection = .locked(5)
    let lockedReading = evaluator.evaluate(stabilized, selection: locked, timestamp: 0)
    runner.equal(lockedReading.target?.noteName, "F♯4", "locked 1st string with capo 2 targets F♯4")
}

func runMetronomeChecks(_ runner: CheckRunner) {
    runner.group("Metronome")

    runner.greater(MetronomePattern.all.count, 15, "pattern library size")
    for pattern in MetronomePattern.all {
        runner.equal(
            pattern.grouping.reduce(0, +),
            pattern.beats,
            "\(pattern.displayName) grouping adds up"
        )
        runner.greater(pattern.beats, 0, "\(pattern.displayName) has beats")
        runner.expect(
            [4, 8, 16].contains(pattern.noteValue),
            "\(pattern.displayName) uses a real note value"
        )
    }

    // Odd metres: the grouping is the point.
    guard let sevenEight = MetronomePattern.pattern(id: "7-8-2-2-3") else {
        runner.expect(false, "7/8 (2+2+3) is in the library")
        return
    }
    runner.equal(sevenEight.beats, 7, "7/8 has seven beats")
    runner.equal(sevenEight.noteValue, 8, "7/8 counts eighths")
    runner.equal(sevenEight.accent(atTick: 0), .downbeat, "7/8 accents the first beat")
    runner.equal(sevenEight.accent(atTick: 1), .beat, "7/8 second beat is a plain beat")
    runner.equal(sevenEight.accent(atTick: 2), .groupStart, "7/8 accents the start of group 2")
    runner.equal(sevenEight.accent(atTick: 3), .beat, "7/8 beat 4 is plain")
    runner.equal(sevenEight.accent(atTick: 4), .groupStart, "7/8 accents the start of group 3")
    runner.equal(sevenEight.accent(atTick: 6), .beat, "7/8 last beat is plain")
    runner.equal(sevenEight.accent(atTick: 7), .downbeat, "the bar wraps back to the downbeat")

    if let nineEight = MetronomePattern.pattern(id: "9-8-2-2-2-3") {
        let accents = (0..<9).map { nineEight.accent(atTick: $0) }
        runner.equal(
            accents,
            [.downbeat, .beat, .groupStart, .beat, .groupStart, .beat, .groupStart, .beat, .beat],
            "9/8 (2+2+2+3) accents 1, 3, 5 and 7"
        )
    }
    if let tenEight = MetronomePattern.pattern(id: "10-8-3-3-2-2") {
        runner.equal(tenEight.beats, 10, "10/8 has ten beats")
        runner.equal(tenEight.accent(atTick: 3), .groupStart, "10/8 (3+3+2+2) accents beat 4")
        runner.equal(tenEight.accent(atTick: 6), .groupStart, "10/8 accents beat 7")
        runner.equal(tenEight.accent(atTick: 8), .groupStart, "10/8 accents beat 9")
    }

    // Subdivision adds ticks between beats without stealing the accents.
    let subdivided = MetronomePattern(id: "sub", name: "test", beats: 4, noteValue: 4, grouping: [4], subdivision: 2)
    runner.equal(subdivided.ticksPerBar, 8, "a subdivided bar has eight ticks")
    runner.equal(subdivided.accent(atTick: 0), .downbeat, "subdivided downbeat")
    runner.equal(subdivided.accent(atTick: 1), .subdivision, "the off-beat is a subdivision")
    runner.equal(subdivided.accent(atTick: 2), .beat, "beat two lands on tick 2")

    var clock = MetronomeClock(pattern: sevenEight, tempo: 120)
    // The tempo counts the note value of the time signature, the way a metronome does:
    // 120 in 7/8 means 120 eighth notes per minute, so each beat is half a second.
    runner.near(clock.tickDuration, 0.5, accuracy: 1e-9, "120 bpm in 7/8 is one beat every 0.5 s")
    runner.equal(clock.beatNumber, 1, "clock starts on beat 1")
    runner.equal(clock.barNumber, 1, "clock starts in bar 1")
    for _ in 0..<7 { clock.advance() }
    runner.equal(clock.beatNumber, 1, "after seven eighths the beat counter wraps")
    runner.equal(clock.barNumber, 2, "and the bar counter advances")
    clock.update(tempo: 60)
    runner.near(clock.tickDuration, 1.0, accuracy: 1e-9, "tempo changes take effect")
    clock.reset()
    runner.equal(clock.tickIndex, 0, "reset returns to the start")
}

func runToneSynthesizerChecks(_ runner: CheckRunner) {
    runner.group("Tone synthesis")

    let sampleRate = 48_000.0
    let tone = ToneSynthesizer.plucked(
        frequency: 196,
        duration: 1.0,
        sampleRate: sampleRate,
        amplitude: 0.5
    )
    runner.equal(tone.count, 48_000, "one second at 48 kHz")
    runner.expect(tone.allSatisfy { $0.isFinite }, "the tone has no NaN or infinity")
    runner.lessOrEqual(tone.map { abs($0) }.max() ?? 1, 0.95, "the tone does not clip")
    let early = tone.prefix(4800).map { abs($0) }.reduce(0, +) / 4800
    let late = tone.suffix(4800).map { abs($0) }.reduce(0, +) / 4800
    runner.greater(early, late * 4, "the tone decays like a plucked string")
    runner.near(Double(tone[0]), 0, accuracy: 1e-6, "the buffer starts at zero (no click)")
    runner.near(Double(tone[tone.count - 1]), 0, accuracy: 1e-3, "the buffer ends quietly")

    let highNote = ToneSynthesizer.plucked(frequency: 12_000, duration: 0.2, sampleRate: sampleRate)
    runner.expect(highNote.allSatisfy { $0.isFinite }, "partials above Nyquist are skipped, not aliased")

    runner.expect(ToneSynthesizer.plucked(frequency: 0, duration: 1, sampleRate: sampleRate).isEmpty, "0 Hz produces nothing")
    runner.expect(ToneSynthesizer.plucked(frequency: 440, duration: 0, sampleRate: sampleRate).isEmpty, "zero duration produces nothing")

    let chord = ToneSynthesizer.chord(
        frequencies: ToneSynthesizer.frequencies(of: ChordLibrary.voicing(id: "C")!),
        duration: 1.2,
        sampleRate: sampleRate
    )
    runner.equal(chord.count, 57_600, "chord buffer length")
    runner.lessOrEqual(chord.map { abs($0) }.max() ?? 1, 0.91, "chord mix stays below full scale")
    runner.expect(chord.allSatisfy { $0.isFinite }, "chord mix is finite")

    let accent = ToneSynthesizer.click(accented: true, sampleRate: sampleRate)
    let plain = ToneSynthesizer.click(accented: false, sampleRate: sampleRate)
    runner.greater(accent.count, plain.count, "the accent click is longer")
    runner.less(accent.count, Int(0.1 * sampleRate), "clicks stay short")
    runner.lessOrEqual(accent.map { abs($0) }.max() ?? 1, 0.81, "click level")
    runner.expect(accent.allSatisfy { $0.isFinite }, "click is finite")

    // Capo shifts a reference chord exactly like it shifts a target.
    if let c = ChordLibrary.voicing(id: "C") {
        let open = ToneSynthesizer.frequencies(of: c)
        let capoed = ToneSynthesizer.frequencies(of: c, capoFret: 2)
        runner.near(
            capoed[0] / open[0],
            pow(2, 2.0 / 12.0),
            accuracy: 0.001,
            "capo 2 raises a reference chord by a whole tone"
        )
    }
}

func runProgressionChecks(_ runner: CheckRunner) {
    runner.group("Progression practice")

    runner.greater(Progression.all.count, 5, "progression library size")
    for progression in Progression.all {
        runner.expect(!progression.steps.isEmpty, "\(progression.name) has steps")
        for step in progression.steps {
            runner.isNotNil(
                ChordLibrary.voicing(id: step.voicingID),
                "\(progression.name) uses a chord that exists (\(step.voicingID))"
            )
            runner.greater(step.beats, 0, "\(progression.name) steps last at least one beat")
        }
        runner.equal(
            progression.totalBeats,
            progression.steps.reduce(0) { $0 + $1.beats },
            "\(progression.name) total length"
        )
    }

    runner.equal(Progression.twelveBarBlues.steps.count, 12, "the blues is twelve bars")
    runner.equal(Progression.twelveBarBlues.chordNames.first, "E7", "the blues starts on E7")
    runner.equal(Progression.popFour.chordNames, ["C", "G", "Am", "F"], "I–V–vi–IV in C")

    guard let cMajor = ChordLibrary.voicing(id: "C"), let gMajor = ChordLibrary.voicing(id: "G") else {
        runner.expect(false, "library has C and G")
        return
    }

    // Playing the right chord scores; playing the wrong one does not.
    var trainer = ProgressionTrainer(progression: Progression.popFour)
    for _ in 0..<4 {
        _ = trainer.onBeat(chroma: chroma(for: cMajor))
    }
    runner.equal(trainer.scores.count, 1, "four beats complete one bar")
    runner.expect(trainer.scores.first?.isCorrect ?? false, "a correctly played C scores")
    runner.near(trainer.accuracy, 1, accuracy: 1e-9, "accuracy after one correct chord")
    runner.equal(trainer.bestStreak, 1, "streak counts")

    for _ in 0..<4 {
        _ = trainer.onBeat(chroma: chroma(for: cMajor)) // expected G
    }
    runner.expect(!(trainer.scores.last?.isCorrect ?? true), "the wrong chord is marked wrong")
    runner.near(trainer.accuracy, 0.5, accuracy: 1e-9, "accuracy reflects one of two")
    runner.equal(trainer.bestStreak, 1, "a wrong chord resets the streak")

    // Silence is a miss, not a pass.
    var silentTrainer = ProgressionTrainer(progression: Progression.popFour)
    for _ in 0..<4 {
        _ = silentTrainer.onBeat(chroma: .silent)
    }
    runner.expect(!(silentTrainer.scores.first?.isCorrect ?? true), "not playing is not correct")
    runner.near(silentTrainer.averageScore, 0, accuracy: 1e-9, "silence scores zero")

    // The first beat is a grace period: judging starts after it.
    var impatient = ProgressionTrainer(progression: Progression.popFour)
    let firstBeat = impatient.onBeat(chroma: chroma(for: gMajor))
    runner.expect(firstBeat?.isStepStart ?? false, "the first beat starts a step")
    runner.expect(impatient.scores.isEmpty, "nothing is scored on the first beat")

    // Running the whole progression finishes it.
    var full = ProgressionTrainer(progression: Progression.popFour)
    var finished = false
    for step in Progression.popFour.steps {
        guard let voicing = ChordLibrary.voicing(id: step.voicingID) else { continue }
        for _ in 0..<step.beats {
            if let update = full.onBeat(chroma: chroma(for: voicing)) {
                finished = update.isFinished
            }
        }
    }
    runner.expect(finished, "the progression reports when it is done")
    runner.equal(full.scores.count, Progression.popFour.steps.count, "one score per chord")
    runner.near(full.accuracy, 1, accuracy: 1e-9, "playing everything correctly is 100%")
    runner.equal(full.bestStreak, Progression.popFour.steps.count, "the streak counts every chord")

    full.reset()
    runner.equal(full.scores.count, 0, "reset clears the scores")
    runner.equal(full.stepIndex, 0, "reset returns to the first chord")

    // Switching progression restarts cleanly.
    full.update(progression: Progression.twelveBarBlues)
    runner.equal(full.progression.steps.count, 12, "switching progression works")
    runner.equal(full.stepIndex, 0, "switching progression restarts")
}
