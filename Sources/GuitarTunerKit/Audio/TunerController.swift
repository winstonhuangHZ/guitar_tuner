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
    public private(set) var sampleRate: Double = 0
    public private(set) var history: [HistorySample] = []
    /// Last target the tuner locked onto; kept so the display does not blank out the
    /// instant the string decays below the gate.
    public private(set) var lastStableTarget: PitchTarget?
    /// Filter + detector settings currently applied to the audio graph.
    public private(set) var activeProfile: AnalysisProfile

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
    private let engine = AVAudioEngine()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    #endif
    private let ringBuffer = AudioSampleRingBuffer()
    private let pipeline: AnalysisPipeline
    private let observerToken = NotificationToken()
    private var isEQAttached = false
    private var isTapInstalled = false
    private var nextHistoryID = 0
    private var wasInTune = false

    public init() {
        let selection = TuningSelection.default
        self.storedSelection = selection
        self.activeProfile = AnalysisProfile.make(inputMode: .microphone, selection: selection)
        self.pipeline = AnalysisPipeline(ringBuffer: ringBuffer, selection: selection)

        pipeline.onReading = { [weak self] reading in
            Task { @MainActor in
                self?.apply(reading: reading)
            }
        }

        #if canImport(AVFoundation)
        configureBands()
        observerToken.value = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
        #endif
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
        guard !isRunning else { return }
        status = .requestingPermission

        let permission = await MicrophonePermission.request()
        self.permission = permission
        guard permission == .granted else {
            status = .permissionDenied
            return
        }

        do {
            try startEngine()
            pipeline.start()
            status = .running
        } catch {
            stopEngine()
            status = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        pipeline.stop()
        stopEngine()
        status = .idle
        apply(reading: .idle)
        history.removeAll(keepingCapacity: true)
        lastStableTarget = nil
        wasInTune = false
    }

    // MARK: - Settings plumbing

    private func setInputMode(_ mode: AudioInputMode) {
        guard mode != storedInputMode else { return }
        storedInputMode = mode
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
        applyProfile()
    }

    private func applyProfile() {
        let profile = AnalysisProfile.make(inputMode: storedInputMode, selection: storedSelection)
        activeProfile = profile
        #if canImport(AVFoundation)
        configureBands()
        #endif
        pipeline.update(selection: storedSelection, profile: profile)
    }

    // MARK: - Readings

    private func apply(reading newReading: TunerReading) {
        reading = newReading
        if let target = newReading.target {
            lastStableTarget = target
        }
        appendHistoryPoint(cents: newReading.cents, isHeld: newReading.isHeld)
        updateHaptics(isInTune: newReading.isInTune)
    }

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
    private func startEngine() throws {
        #if os(iOS)
        try activateAudioSession()
        #endif

        tearDownGraph()

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
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        // Analysis only: the microphone is never monitored, so there is no feedback path.
        engine.mainMixerNode.outputVolume = 0

        let ring = ringBuffer
        eqNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            ring.append(buffer)
        }
        isTapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw TunerError.engineFailed(error.localizedDescription)
        }
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
