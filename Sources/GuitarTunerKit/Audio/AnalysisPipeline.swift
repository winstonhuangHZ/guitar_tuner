import Foundation

/// Owns the audio-analysis loop: it pulls the newest samples out of the ring buffer,
/// runs the detector on a private serial queue and hands finished readings to the UI.
///
/// Everything below runs off the main actor; only `onReading` hops back.
final class AnalysisPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.guitartuner.analysis", qos: .userInitiated)
    private let ringBuffer: AudioSampleRingBuffer
    private let updateInterval: TimeInterval

    private var detector: PitchDetector
    private var stabilizer: PitchStabilizer
    private var evaluator: TunerEvaluator
    private var noiseFloor: NoiseFloorEstimator
    private var selection: TuningSelection
    private var window: [Float] = []

    private var timer: DispatchSourceTimer?
    private var isRunning = false

    /// Called on an arbitrary thread for every finished frame.
    var onReading: (@Sendable (TunerReading) -> Void)?

    init(
        ringBuffer: AudioSampleRingBuffer,
        selection: TuningSelection,
        updateInterval: TimeInterval = 0.05
    ) {
        self.ringBuffer = ringBuffer
        self.selection = selection
        self.updateInterval = max(0.02, updateInterval)
        self.detector = PitchDetector()
        self.stabilizer = PitchStabilizer()
        self.evaluator = TunerEvaluator()
        self.noiseFloor = NoiseFloorEstimator()
        updateProfileLocked(AnalysisProfile.make(inputMode: .microphone, selection: selection))
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            let interval = self.updateInterval
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(4))
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.isRunning = false
            self.resetLocked()
        }
    }

    // MARK: - Configuration

    func update(selection: TuningSelection, profile: AnalysisProfile) {
        queue.async { [weak self] in
            guard let self else { return }
            let presetChanged = self.selection.preset.id != selection.preset.id
            let referenceChanged = self.selection.referencePitch != selection.referencePitch
            self.selection = selection
            if presetChanged || referenceChanged {
                self.evaluator.reset()
                self.stabilizer.reset()
            }
            self.updateProfileLocked(profile)
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.resetLocked()
        }
    }

    private func updateProfileLocked(_ profile: AnalysisProfile) {
        var configuration = detector.configuration
        configuration.minFrequency = profile.minFrequency
        configuration.maxFrequency = profile.maxFrequency
        detector.configuration = configuration
    }

    private func resetLocked() {
        stabilizer.reset()
        evaluator.reset()
        noiseFloor.reset()
    }

    // MARK: - Loop

    private func tick() {
        let sampleRate = ringBuffer.sampleRate
        let available = ringBuffer.availableSampleCount
        guard sampleRate > 0, available > 0 else { return }

        let requested = min(max(detector.configuration.analysisWindowSize, 1024), available)
        let count = ringBuffer.latest(count: requested, into: &window)
        guard count >= detector.configuration.minimumSampleCount else { return }

        let frame = window
        let now = Date.timeIntervalSinceReferenceDate
        let analysis = detector.analyze(samples: frame, sampleRate: sampleRate, gate: noiseFloor.gate)
        noiseFloor.update(rms: analysis.rms, isSignalPresent: analysis.frequency != nil)

        let stabilized = stabilizer.process(analysis, at: now)
        let reading = evaluator.evaluate(stabilized, selection: selection, timestamp: now)
        onReading?(reading)
    }
}
