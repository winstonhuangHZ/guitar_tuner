import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation
#endif
#if os(iOS)
import AVFAudio
#endif

public enum TunerError: LocalizedError, Sendable {
    case noInputAvailable
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noInputAvailable:
            "No audio input is available. Connect a microphone or check the system input settings."
        case let .engineFailed(message):
            "The audio engine could not start: \(message)"
        }
    }
}

/// The app-facing entry point: owns the audio graph, the DSP pipeline and the
/// observable state that the SwiftUI layer renders.
///
/// Threading model: audio tap (real-time) → ring buffer → analysis queue → main actor.
@MainActor
@Observable
public final class TunerController {
    public enum Status: Sendable, Equatable {
        case idle
        case requestingPermission
        case running
        case permissionDenied
        case failed(String)

        public var isRunning: Bool { self == .running }

        public var message: String? {
            switch self {
            case .idle: nil
            case .requestingPermission: "Waiting for microphone access…"
            case .running: nil
            case .permissionDenied: "Microphone access is off. Enable it in System Settings, then press Start."
            case let .failed(message): message
            }
        }
    }

    /// One point on the tuning history strip.
    public struct HistorySample: Sendable, Equatable, Identifiable {
        public let id: Int
        public let cents: Double
    }

    // MARK: - Observable state

    public private(set) var status: Status = .idle
    public private(set) var reading: TunerReading = .idle
    public private(set) var permission: MicrophonePermissionStatus = .undetermined
    /// True once the analysis loop has delivered frames since the last start.
    public private(set) var hasAudioFrames = false
    /// Set when the engine runs but nothing ever arrives, with a hint about why.
    public private(set) var audioDiagnostic: String?
    public private(set) var sampleRate: Double = 0
    public private(set) var history: [HistorySample] = []
    /// FFT display data for the spectrum view (updated at 10 Hz).
    public private(set) var spectrum: SpectrumSnapshot = .empty
    /// Twelve-bin pitch-class profile, and what it looks like as a chord (10 Hz).
    public private(set) var chroma: ChromaProfile = .silent
    public private(set) var chordDetection: ChordDetection = .none
    /// Last target the tuner locked onto; kept so the display does not blank out the
    /// instant the string decays below the gate.
    public private(set) var lastStableTarget: PitchTarget?
    /// Filter + detector settings currently applied to the audio graph.
    public private(set) var activeProfile: AnalysisProfile

    /// The shape the practice mode is listening for.
    public var practiceTarget: ChordVoicing? {
        didSet {
            updateChordEvaluation()
            tunerSettings.practiceVoicingID = practiceTarget?.id
            scheduleSettingsSave()
        }
    }
    /// How the current audio compares with `practiceTarget`.
    public private(set) var chordEvaluation: ChordEvaluation?

    // MARK: Metronome, progression and history

    // Read-only from outside the module, but the practice/settings extensions write them.
    public internal(set) var isMetronomeRunning = false
    public internal(set) var metronomePattern: MetronomePattern = .commonTime
    public internal(set) var metronomeTempo: Double = 90
    public internal(set) var metronomeAccentsEnabled = true
    public internal(set) var metronomeVolume: Double = 0.7
    /// Most recently scheduled click, for the visual metronome.
    public internal(set) var lastBeat: MetronomeBeat?
    public internal(set) var progression: Progression = .popFour
    public internal(set) var progressionUpdate: ProgressionTrainer.BeatUpdate?
    public internal(set) var isProgressionRunning = false
    public internal(set) var tuningHistorySummary: TuningHistorySummary = .empty
    public internal(set) var isRecordingHistory = true

    // MARK: Input devices

    public internal(set) var availableInputDevices: [AudioInputDevice] = []
    public internal(set) var selectedInputDeviceID: String?

    // MARK: - User settings

    private var storedInputMode: AudioInputMode = .microphone
    private var storedSelection: TuningSelection = .default

    public var inputMode: AudioInputMode {
        get { storedInputMode }
        set { setInputMode(newValue) }
    }

    public var selection: TuningSelection {
        get { storedSelection }
        set { apply(selection: newValue) }
    }

    public var preset: TuningPreset {
        get { storedSelection.preset }
        set {
            var updated = storedSelection
            updated.preset = newValue
            updated.stringSelection = .automatic
            apply(selection: updated)
        }
    }

    public var referencePitch: Double {
        get { storedSelection.referencePitch }
        set {
            var updated = storedSelection
            updated.referencePitch = min(max(newValue, 415), 466)
            apply(selection: updated)
        }
    }

    public var stringSelection: StringSelection {
        get { storedSelection.stringSelection }
        set {
            var updated = storedSelection
            updated.stringSelection = newValue
            apply(selection: updated)
        }
    }

    public var inTuneToleranceCents: Double {
        get { storedSelection.inTuneToleranceCents }
        set {
            var updated = storedSelection
            updated.inTuneToleranceCents = min(max(newValue, 1), 25)
            apply(selection: updated)
        }
    }

    /// Capo position in frets; every target string moves up with it.
    public var capoFret: Int {
        get { storedSelection.capoFret }
        set {
            var updated = storedSelection
            updated.capoFret = min(max(newValue, 0), TuningPreset.maximumCapoFret)
            updated.stringSelection = .automatic
            apply(selection: updated)
        }
    }

    // MARK: - Internals

    /// Keeps the engine-configuration observer alive without touching main-actor state
    /// from `deinit`.
    private final class NotificationToken: @unchecked Sendable {
        var value: NSObjectProtocol?

        deinit {
            if let value {
                NotificationCenter.default.removeObserver(value)
            }
        }
    }

    #if canImport(AVFoundation)
    // Internal rather than private so the practice/settings extensions in their own files
    // can reach them. They are not public API.
    let engine = AVAudioEngine()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    /// The analysis path is muted here, *after* the tap, so the microphone is never sent
    /// to the speakers while the metronome or a reference tone is playing.
    private let analysisMixer = AVAudioMixerNode()
    let playback = PlaybackEngine()
    let settingsStore: SettingsStore
    var tunerSettings = TunerSettings.default
    var historyStore: TuningHistoryStore
    var lastHistorySample: TuningSample?
    var settingsSaveTask: Task<Void, Never>?
    var trainer: ProgressionTrainer = ProgressionTrainer(progression: .popFour)
    var historyRecordCount = 0
    #endif
    private let ringBuffer = AudioSampleRingBuffer()
    private let pipeline: AnalysisPipeline
    private let observerToken = NotificationToken()
    private var isEQAttached = false
    private var isTapInstalled = false
    private var nextHistoryID = 0
    private var wasInTune = false
    private var watchdogTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore = SettingsStore(), historyStore: TuningHistoryStore = TuningHistoryStore()) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        let settings = settingsStore.load()
        self.tunerSettings = settings

        var selection = TuningSelection.default
        selection.preset = settings.preset
        selection.referencePitch = settings.referencePitch
        selection.stringSelection = settings.stringSelection
        selection.capoFret = settings.capoFret
        selection.inTuneToleranceCents = settings.inTuneToleranceCents
        self.storedSelection = selection
        self.storedInputMode = settings.inputMode
        self.selectedInputDeviceID = settings.inputDeviceID
        self.activeProfile = AnalysisProfile.make(inputMode: .microphone, selection: selection)
        self.pipeline = AnalysisPipeline(ringBuffer: ringBuffer, selection: selection)
        self.metronomePattern = MetronomePattern.pattern(id: settings.metronomePatternID) ?? .commonTime
        self.metronomeTempo = settings.metronomeTempo
        self.metronomeAccentsEnabled = settings.metronomeAccentsEnabled
        self.metronomeVolume = settings.metronomeVolume
        self.isRecordingHistory = settings.recordsTuningHistory
        self.practiceTarget = settings.practiceVoicingID.flatMap { ChordLibrary.voicing(id: $0) }
        self.progression = settings.progressionID.flatMap { Progression.progression(id: $0) } ?? .popFour
        self.trainer = ProgressionTrainer(progression: progression)

        pipeline.onReading = { [weak self] reading in
            Task { @MainActor in
                self?.apply(reading: reading)
            }
        }
        pipeline.onSpectrum = { [weak self] snapshot in
            Task { @MainActor in
                self?.spectrum = snapshot
            }
        }
        pipeline.onChroma = { [weak self] chroma in
            Task { @MainActor in
                self?.apply(chroma: chroma)
            }
        }

        #if canImport(AVFoundation)
        configureBands()
        observerToken.value = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main,
            using: Self.makeConfigurationChangeHandler(self)
        )
        #endif

        updateSpectrumRange()
        refreshInputDevices()
        refreshHistorySummary()

        playback.onBeat = { [weak self] beat in
            guard let self else { return }
            self.lastBeat = beat
            self.advanceProgressionIfNeeded()
        }
    }

    public var isRunning: Bool { status.isRunning }

    /// The target to show: the live reading, or the last one locked onto while the
    /// string is still ringing out.
    public var displayTarget: PitchTarget? {
        reading.target ?? lastStableTarget
    }

    // MARK: - Lifecycle

    public func toggle() async {
        if isRunning {
            stop()
        } else {
            await start()
        }
    }

    public func start() async {
        // Nothing to do while a start (including its permission request) is already in
        // flight — the request now has a deadline, so this cannot hang for long.
        guard !isRunning, status != .requestingPermission else { return }
        status = .requestingPermission
        hasAudioFrames = false
        audioDiagnostic = nil

        let permission = await MicrophonePermission.request()
        self.permission = permission
        TunerLog.trace("microphone permission: \(permission)")

        if permission == .denied {
            status = .permissionDenied
            return
        }

        // Granted — or still undetermined after the permission request timed out. In the
        // second case the capture attempt itself is the source of truth: if access is
        // really blocked the engine reports it, and if it is not, the user gets a working
        // tuner instead of a UI stuck on "waiting".
        do {
            try startEngine()
            pipeline.start()
            status = .running
            startAudioWatchdog()
            TunerLog.trace("engine running at \(sampleRate) Hz, \(activeProfile.minFrequency)–\(activeProfile.maxFrequency) Hz search range")
        } catch {
            stopEngine()
            status = .failed(error.localizedDescription)
            TunerLog.trace("engine failed: \(error.localizedDescription)")
        }
    }

    public func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        pipeline.stop()
        stopEngine()
        status = .idle
        apply(reading: .idle)
        history.removeAll(keepingCapacity: true)
        spectrum = .empty
        chroma = .silent
        chordDetection = .none
        chordEvaluation = nil
        hasAudioFrames = false
        audioDiagnostic = nil
        lastStableTarget = nil
        wasInTune = false
    }

    /// A running engine that never produces a frame is the one failure the audio stack
    /// does not report by itself, so it gets its own deadline and message.
    private func startAudioWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled, self.isRunning, !self.hasAudioFrames else { return }
            self.audioDiagnostic = """
                The engine is running but no audio is arriving. If you launched the bare \
                executable, macOS attributes the microphone to your terminal — build the \
                app bundle with Scripts/make-macos-app.sh and open it from there.
                """
        }
    }

    // MARK: - Settings plumbing

    private func setInputMode(_ mode: AudioInputMode) {
        guard mode != storedInputMode else { return }
        storedInputMode = mode
        tunerSettings.inputMode = mode
        scheduleSettingsSave()
        applyProfile()
    }

    private func apply(selection: TuningSelection) {
        guard selection != storedSelection else { return }
        let presetChanged = selection.preset.id != storedSelection.preset.id
        storedSelection = selection
        if presetChanged {
            lastStableTarget = nil
            history.removeAll(keepingCapacity: true)
        }
        tunerSettings.presetID = selection.preset.id
        tunerSettings.referencePitch = selection.referencePitch
        tunerSettings.capoFret = selection.capoFret
        tunerSettings.inTuneToleranceCents = selection.inTuneToleranceCents
        tunerSettings.lockedStringID = selection.stringSelection.lockedStringID
        scheduleSettingsSave()
        applyProfile()
    }

    private func applyProfile() {
        let profile = AnalysisProfile.make(inputMode: storedInputMode, selection: storedSelection)
        activeProfile = profile
        #if canImport(AVFoundation)
        configureBands()
        #endif
        pipeline.update(selection: storedSelection, profile: profile)
        updateSpectrumRange()
    }

    /// The spectrum axis follows the tuning: low enough for the lowest string, high
    /// enough to show its first few harmonics.
    private func updateSpectrumRange() {
        let presetRange = storedSelection.preset.frequencyRange(referencePitch: storedSelection.referencePitch)
        let lowest = presetRange?.lowerBound ?? 55
        let highest = presetRange?.upperBound ?? 1400
        let minFrequency = max(AnalysisProfile.absoluteMinFrequency, lowest * 0.55)
        let maxFrequency = min(8000, max(4000, highest * 5))
        pipeline.updateSpectrumFrequencyRange(min: minFrequency, max: maxFrequency)
    }

    // MARK: - Readings

    private func apply(reading newReading: TunerReading) {
        reading = newReading
        if isRunning {
            hasAudioFrames = true
            audioDiagnostic = nil
        }
        if let target = newReading.target {
            lastStableTarget = target
        }
        appendHistoryPoint(cents: newReading.cents, isHeld: newReading.isHeld)
        updateHaptics(isInTune: newReading.isInTune)
        recordTuningSample(from: newReading)
    }

    /// A chroma frame arrived: identify the chord and score it against the practice target.
    private func apply(chroma newChroma: ChromaProfile) {
        chroma = newChroma
        chordDetection = newChroma.isSilent ? .none : Self.chordDetector.detect(newChroma)
        updateChordEvaluation()
    }

    private func updateChordEvaluation() {
        guard let target = practiceTarget, !chroma.isSilent else {
            chordEvaluation = nil
            return
        }
        chordEvaluation = Self.chordEvaluator.evaluate(
            chroma: chroma,
            target: target,
            detection: chordDetection
        )
    }

    private static let chordDetector = ChordDetector()
    private static let chordEvaluator = ChordEvaluator()

    private func appendHistoryPoint(cents: Double?, isHeld: Bool) {
        guard let cents, !isHeld else { return }
        nextHistoryID += 1
        history.append(HistorySample(id: nextHistoryID, cents: cents))
        if history.count > 96 {
            history.removeFirst(history.count - 96)
        }
    }

    private func updateHaptics(isInTune: Bool) {
        defer { wasInTune = isInTune }
        guard isInTune, !wasInTune else { return }
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    // MARK: - Audio graph

    #if canImport(AVFoundation)
    /// Creates the audio tap closure *outside* the main actor.
    ///
    /// This is not cosmetic. A closure literal written inside a `@MainActor` method
    /// inherits that isolation whenever the API's parameter type is not `@Sendable` —
    /// which is the case for `AVAudioNodeTapBlock` in the current SDK. AVFAudio calls the
    /// tap on its own realtime messenger thread, so the Swift runtime's actor-isolation
    /// check traps (`dispatch_assert_queue_fail` → SIGILL) the first time a buffer
    /// arrives, and the app dies the moment the microphone starts delivering audio.
    /// Building the closure in a `nonisolated` function keeps it unisolated.
    private nonisolated static func makeTapHandler(
        _ ringBuffer: AudioSampleRingBuffer
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            ringBuffer.append(buffer)
        }
    }

    /// Same reasoning as `makeTapHandler`: build the observer closure outside the main
    /// actor and hop back with an explicit `Task { @MainActor in … }`.
    private nonisolated static func makeConfigurationChangeHandler(
        _ controller: TunerController
    ) -> @Sendable (Notification) -> Void {
        { _ in
            Task { @MainActor in
                controller.handleConfigurationChange()
            }
        }
    }

    private func startEngine() throws {
        #if os(iOS)
        try activateAudioSession()
        #endif

        do {
            try buildAndStartEngine()
        } catch {
            // A capture device that cannot be opened must not take the whole app down —
            // fall back to the system default once and try again.
            TunerLog.trace("engine failed to start: \(error.localizedDescription)")
            guard selectedInputDeviceID != nil else {
                throw TunerError.engineFailed(error.localizedDescription)
            }
            TunerLog.trace("retrying with the system default input device")
            selectedInputDeviceID = nil
            tunerSettings.inputDeviceID = nil
            scheduleSettingsSave()
            do {
                try buildAndStartEngine()
            } catch {
                throw TunerError.engineFailed(error.localizedDescription)
            }
        }
    }

    /// Builds the graph and starts it. Everything above is policy; this is the mechanics.
    private func buildAndStartEngine() throws {
        tearDownGraph()

        // Apply the chosen capture device *before* any format is read or any connection is
        // made. Changing the HAL device invalidates formats that are already bound to the
        // graph, which silently kills the input — or makes `engine.start()` fail.
        applyInputDevice()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TunerError.noInputAvailable
        }

        ringBuffer.reset(sampleRate: format.sampleRate)
        sampleRate = format.sampleRate

        if !isEQAttached {
            engine.attach(eqNode)
            isEQAttached = true
        }
        configureBands()

        engine.connect(input, to: eqNode, format: format)
        if analysisMixer.engine == nil {
            engine.attach(analysisMixer)
        }
        engine.connect(eqNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)
        // Analysis only: mute the microphone *after* the tap, so the metronome and
        // reference tones can play at full volume without ever monitoring the input.
        analysisMixer.outputVolume = 0
        engine.mainMixerNode.outputVolume = 1

        // `prepare()` before attaching the player: until the graph is prepared the mixer
        // can report a 0 Hz output format, and the player was silently skipped.
        engine.prepare()
        playback.attach(to: engine, sampleRate: outputSampleRate)

        eqNode.installTap(
            onBus: 0,
            bufferSize: 2048,
            format: format,
            block: Self.makeTapHandler(ringBuffer)
        )
        isTapInstalled = true

        try engine.start()
        TunerLog.trace("engine started: input \(format.sampleRate) Hz \(format.channelCount) ch, output \(outputSampleRate) Hz")
    }

    private func stopEngine() {
        tearDownGraph()
        #if os(iOS)
        deactivateAudioSession()
        #endif
    }

    private func tearDownGraph() {
        if isTapInstalled {
            eqNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        engine.disconnectNodeOutput(engine.inputNode)
        // Only tear down connections that exist: disconnecting a node that was never
        // attached (the very first start) is not allowed.
        if isEQAttached {
            engine.disconnectNodeOutput(eqNode)
        }
    }

    private func configureBands() {
        let profile = activeProfile
        let bands = eqNode.bands
        guard bands.count >= 2 else { return }
        apply(
            band: bands[0],
            filterType: .highPass,
            frequency: profile.highPassFrequency,
            bandwidth: profile.filterBandwidth
        )
        apply(
            band: bands[1],
            filterType: .lowPass,
            frequency: profile.lowPassFrequency,
            bandwidth: profile.filterBandwidth
        )
    }

    private func apply(
        band: AVAudioUnitEQFilterParameters,
        filterType: AVAudioUnitEQFilterType,
        frequency: Double?,
        bandwidth: Double
    ) {
        guard let frequency, frequency > 0 else {
            band.bypass = true
            return
        }
        band.filterType = filterType
        band.frequency = Float(frequency)
        band.bandwidth = Float(bandwidth)
        band.gain = 0
        band.bypass = false
    }

    /// Headphones plugged in, a Bluetooth device connected, the default device changed…
    /// the graph has to be rebuilt with the new hardware format.
    private func handleConfigurationChange() {
        guard isRunning else { return }
        do {
            try startEngine()
        } catch {
            pipeline.stop()
            stopEngine()
            status = .failed(error.localizedDescription)
        }
    }
    #else
    private func startEngine() throws { throw TunerError.noInputAvailable }
    private func stopEngine() {}
    private func handleConfigurationChange() {}
    #endif

    #if os(iOS)
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disables AGC and most input DSP, which is exactly what a
        // tuner wants: an honest, unprocessed signal.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: [])
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    #endif
}
