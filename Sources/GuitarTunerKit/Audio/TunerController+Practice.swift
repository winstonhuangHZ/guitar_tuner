import Foundation

/// Reference tones, metronome, progressions, input devices and the tuning history.
///
/// Split from the core controller file so the audio-graph code stays readable; these
/// members are internal for exactly that reason.
@MainActor
public extension TunerController {
    // MARK: - Read-only views of the practice state

    /// Settings as they will be written to disk; handy for a settings screen.
    var settings: TunerSettings { tunerSettings }

    var progressionScores: [ProgressionTrainer.StepScore] { trainer.scores }
    var progressionAccuracy: Double { trainer.accuracy }
    var progressionBestStreak: Int { trainer.bestStreak }
    var progressionCurrentVoicing: ChordVoicing? { trainer.currentVoicing }
    var progressionIsFinished: Bool { trainer.isFinished }

    /// The target currently being listened for, including the capo.
    var capoedPracticeTarget: ChordVoicing? {
        guard let target = practiceTarget else { return nil }
        return target
    }

    // MARK: - Reference tones

    /// Plays the current target of a string, so the player can compare by ear.
    func playReferenceTone(stringIndex: Int) {
        let strings = selection.preset.strings(capoFret: selection.capoFret)
        guard let string = strings.first(where: { $0.id == stringIndex }) ?? strings.first else { return }
        playReferenceTone(midiNumber: Double(string.midiNumber))
    }

    func playReferenceTone(midiNumber: Double) {
        let frequency = NoteMath.frequency(midiNumber: midiNumber, referencePitch: selection.referencePitch)
        let rate = outputSampleRate
        // Synthesising a couple of seconds of audio is fast but not free; keep it off the
        // main actor so the UI does not hitch when a button is tapped.
        Task { [weak self] in
            guard let self else { return }
            // The player node only exists once the engine has been built, so starting a
            // tone has to bring the engine up first — otherwise the tap on "play" would
            // silently do nothing.
            if !self.isRunning { await self.start() }
            guard self.isRunning else { return }
            let samples = await Self.synthesizeTone(frequency: frequency, sampleRate: rate)
            guard !samples.isEmpty else { return }
            self.playback.playTone(samples)
        }
    }

    /// Plays the whole practice chord — the fastest way to hear what a shape should sound
    /// like before trying to play it.
    func playPracticeChord() {
        guard let target = practiceTarget else { return }
        let frequencies = ToneSynthesizer.frequencies(
            of: target,
            capoFret: selection.capoFret,
            referencePitch: selection.referencePitch
        )
        let rate = outputSampleRate
        Task { [weak self] in
            guard let self else { return }
            if !self.isRunning { await self.start() }
            guard self.isRunning else { return }
            let samples = await Self.synthesizeChord(frequencies: frequencies, sampleRate: rate)
            guard !samples.isEmpty else { return }
            self.playback.playTone(samples)
        }
    }

    /// Plays a whole progression once, so the player can hear the changes before trying.
    func playProgressionReference() {
        let rate = outputSampleRate
        let steps = progression.steps.map { step -> (frequencies: [Double], seconds: Double) in
            let frequencies = ToneSynthesizer.frequencies(
                of: step.voicing,
                capoFret: selection.capoFret,
                referencePitch: selection.referencePitch
            )
            let seconds = Double(step.beats) * metronomePattern.beatDuration(tempo: metronomeTempo)
            return (frequencies, seconds)
        }

        Task { [weak self] in
            guard let self else { return }
            if !self.isRunning { await self.start() }
            guard self.isRunning else { return }
            let samples = await Self.synthesizeProgression(steps: steps, sampleRate: rate)
            guard !samples.isEmpty else { return }
            self.playback.playTone(samples)
        }
    }

    // MARK: - Synthesis (off the main actor)

    /// `nonisolated` + `async` puts the rendering work on the cooperative pool, and the
    /// caller resumes on the main actor afterwards.
    nonisolated static func synthesizeTone(frequency: Double, sampleRate: Double) async -> [Float] {
        ToneSynthesizer.plucked(
            frequency: frequency,
            duration: 1.6,
            sampleRate: sampleRate,
            amplitude: 0.5
        )
    }

    nonisolated static func synthesizeChord(frequencies: [Double], sampleRate: Double) async -> [Float] {
        ToneSynthesizer.chord(frequencies: frequencies, duration: 2.0, sampleRate: sampleRate)
    }

    nonisolated static func synthesizeProgression(
        steps: [(frequencies: [Double], seconds: Double)],
        sampleRate: Double
    ) async -> [Float] {
        var samples: [Float] = []
        for step in steps where !step.frequencies.isEmpty {
            samples += ToneSynthesizer.chord(
                frequencies: step.frequencies,
                duration: step.seconds,
                sampleRate: sampleRate,
                decay: 0.55
            )
        }
        return samples
    }

    func stopPlayback() {
        playback.stopAll()
        isMetronomeRunning = false
        lastBeat = nil
    }

    // MARK: - Metronome

    func toggleMetronome() {
        if isMetronomeRunning {
            stopMetronome()
        } else {
            Task { await startMetronomeWhenReady() }
        }
    }

    /// Brings the engine up first: the metronome plays through the same graph, and without
    /// it there is no player node to schedule clicks on.
    func startMetronomeWhenReady() async {
        if !isRunning { await start() }
        guard isRunning else { return }

        tunerSettings.metronomePatternID = metronomePattern.id
        tunerSettings.metronomeTempo = metronomeTempo
        tunerSettings.metronomeAccentsEnabled = metronomeAccentsEnabled
        tunerSettings.metronomeVolume = metronomeVolume
        scheduleSettingsSave()

        ensureEngineForPlayback()
        playback.startMetronome(
            pattern: metronomePattern,
            tempo: metronomeTempo,
            accents: metronomeAccentsEnabled,
            volume: metronomeVolume
        )
        isMetronomeRunning = true
    }

    func stopMetronome() {
        playback.stopMetronome()
        isMetronomeRunning = false
        lastBeat = nil
        if isProgressionRunning {
            isProgressionRunning = false
        }
    }

    func setMetronomePattern(_ pattern: MetronomePattern) {
        guard pattern != metronomePattern else { return }
        metronomePattern = pattern
        tunerSettings.metronomePatternID = pattern.id
        scheduleSettingsSave()
        playback.updateMetronome(pattern: pattern)
    }

    func setMetronomeTempo(_ tempo: Double) {
        let clamped = min(max(tempo, MetronomePattern.minimumTempo), MetronomePattern.maximumTempo)
        guard clamped != metronomeTempo else { return }
        metronomeTempo = clamped
        tunerSettings.metronomeTempo = clamped
        scheduleSettingsSave()
        playback.updateMetronome(tempo: clamped)
    }

    func setMetronomeAccents(_ enabled: Bool) {
        guard enabled != metronomeAccentsEnabled else { return }
        metronomeAccentsEnabled = enabled
        tunerSettings.metronomeAccentsEnabled = enabled
        scheduleSettingsSave()
        playback.updateMetronome(accents: enabled)
    }

    func setMetronomeVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        guard clamped != metronomeVolume else { return }
        metronomeVolume = clamped
        tunerSettings.metronomeVolume = clamped
        scheduleSettingsSave()
        playback.updateMetronome(volume: clamped)
    }

    // MARK: - Progression practice

    func setProgression(_ newProgression: Progression) {
        guard newProgression.id != progression.id else { return }
        progression = newProgression
        trainer.update(progression: newProgression)
        progressionUpdate = nil
        tunerSettings.progressionID = newProgression.templateID
        tunerSettings.progressionKeyID = newProgression.key.id
        scheduleSettingsSave()
        if isProgressionRunning {
            setMetronomeTempo(newProgression.defaultTempo)
        }
    }

    /// Switches the key and rebuilds the progression's shapes.
    func setProgressionKey(_ key: ProgressionKey) {
        guard key != progressionKey else { return }
        progressionKey = key
        let template = ProgressionTemplate.template(id: progression.templateID) ?? .popFour
        setProgression(template.resolve(in: key))
    }

    /// Starts listening for the progression, with the metronome keeping time.
    func startProgression() {
        Task {
            trainer.reset()
            progressionUpdate = nil
            isProgressionRunning = true
            setMetronomeTempo(progression.defaultTempo)
            if !isMetronomeRunning {
                await startMetronomeWhenReady()
            }
        }
    }

    func stopProgression() {
        isProgressionRunning = false
        progressionUpdate = nil
    }

    func resetProgression() {
        trainer.reset()
        progressionUpdate = nil
    }

    /// Called on every metronome beat.
    func advanceProgressionIfNeeded() {
        guard isProgressionRunning else { return }
        let update = trainer.onBeat(chroma: chroma)
        progressionUpdate = update
        if update?.isFinished == true {
            isProgressionRunning = false
            playback.stopMetronome()
            isMetronomeRunning = false
        }
    }

    // MARK: - Input devices

    func refreshInputDevices() {
        availableInputDevices = AudioInputDevices.available()
        // Deliberately does not adopt the current device: `nil` means "let the system
        // decide", and only an explicit choice is pushed onto the audio unit.
        if let id = selectedInputDeviceID, !availableInputDevices.contains(where: { $0.id == id }) {
            selectedInputDeviceID = nil
        }
    }

    func selectInputDevice(id: String?) {
        selectedInputDeviceID = id
        tunerSettings.inputDeviceID = id
        scheduleSettingsSave()

        let wasRunning = isRunning
        if wasRunning {
            stop()
        }
        applyInputDevice()
        if wasRunning {
            Task { await start() }
        }
    }

    // MARK: - Tuning history

    func setHistoryRecording(_ enabled: Bool) {
        isRecordingHistory = enabled
        tunerSettings.recordsTuningHistory = enabled
        scheduleSettingsSave()
    }

    func refreshHistorySummary() {
        tuningHistorySummary = historyStore.summary()
    }

    func clearTuningHistory() {
        historyStore.clear()
        lastHistorySample = nil
        tuningHistorySummary = .empty
    }

    // MARK: - Internals shared with the controller

    var outputSampleRate: Double {
        let hardware = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        return hardware > 0 ? hardware : 48_000
    }

    func ensureEngineForPlayback() {
        guard !isRunning, status != .requestingPermission else { return }
        Task { await start() }
    }

    func applyInputDevice() {
        #if os(macOS)
        guard let id = selectedInputDeviceID else { return }
        // `AVAudioNode.audioUnit` is the only way to reach the HAL unit and set its input
        // device; it is deprecated but still the supported route for this.
        let applied = AudioInputDevices.select(deviceID: id, on: engine.inputNode.audioUnit)
        TunerLog.trace("input device \(id) \(applied ? "selected" : "could not be selected")")
        #elseif os(iOS)
        if let id = selectedInputDeviceID {
            let applied = AudioInputDevices.select(deviceID: id)
            TunerLog.trace("input device \(id) \(applied ? "selected" : "could not be selected")")
        }
        #endif
    }

    /// Writes the settings back after a short pause, so dragging a slider does not write
    /// on every frame.
    func scheduleSettingsSave() {
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.settingsStore.save(self.tunerSettings)
        }
    }

    /// Keeps one sample per second of stable, in-range readings.
    func recordTuningSample(from reading: TunerReading) {
        guard isRecordingHistory,
              !reading.isHeld,
              let cents = reading.cents,
              let target = reading.target else { return }

        let now = Date().timeIntervalSince1970
        guard historyStore.shouldRecord(lastSample: lastHistorySample, now: now) else { return }

        let sample = TuningSample(
            timestamp: now,
            targetID: "\(selection.preset.id):\(target.id)",
            label: target.detailedLabel,
            cents: cents,
            referencePitch: selection.referencePitch
        )
        lastHistorySample = sample
        historyStore.append(contentsOf: [sample])

        historyRecordCount += 1
        if historyRecordCount % 60 == 0 {
            refreshHistorySummary()
        }
    }
}
