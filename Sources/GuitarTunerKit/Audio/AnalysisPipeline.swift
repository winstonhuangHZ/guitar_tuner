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
    private let spectrumAnalyzer = SpectrumAnalyzer()
    private let chromaAnalyzer = ChromaAnalyzer()
    private var selection: TuningSelection
    private var window: [Float] = []
    private var frameIndex = 0

    private var timer: DispatchSourceTimer?
    private var isRunning = false

    /// Called on an arbitrary thread for every finished frame.
    var onReading: (@Sendable (TunerReading) -> Void)?
    /// Called on an arbitrary thread for every analysed spectrum frame.
    var onSpectrum: (@Sendable (SpectrumSnapshot) -> Void)?
    /// Called on an arbitrary thread for every analysed chroma frame.
    var onChroma: (@Sendable (ChromaProfile) -> Void)?

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
            TunerLog.trace("analysis loop started (\(Int(1 / interval)) Hz)")
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
            self.chromaAnalyzer.referencePitch = selection.referencePitch
            if presetChanged || referenceChanged {
                self.evaluator.reset()
                self.stabilizer.reset()
            }
            self.updateProfileLocked(profile)
        }
    }

    /// Keeps the spectrum display centred on the band that matters for this tuning.
    func updateSpectrumFrequencyRange(min: Double, max: Double) {
        queue.async { [weak self] in
            self?.spectrumAnalyzer.setFrequencyRange(min: min, max: max)
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

        updateAnalysisWindow(sampleRate: sampleRate)
        let requested = min(max(detector.configuration.analysisWindowSize, spectrumAnalyzer.windowSize), available)
        let count = ringBuffer.latest(count: requested, into: &window)
        guard count >= detector.configuration.minimumSampleCount else { return }

        let frame = window
        let now = Date.timeIntervalSinceReferenceDate
        // Easier to keep a note than to start one: a decaying string stays on the dial
        // after its clarity has dipped below the threshold needed to acquire it.
        let clarityThreshold = stabilizer.isTracking
            ? detector.configuration.retentionClarity
            : detector.configuration.minimumClarity
        let analysis = detector.analyze(
            samples: frame,
            sampleRate: sampleRate,
            gate: noiseFloor.gate,
            minimumClarity: clarityThreshold
        )
        noiseFloor.update(rms: analysis.rms, isSignalPresent: analysis.frequency != nil)

        frameIndex += 1
        if frameIndex == 1 || frameIndex % 100 == 0 {
            TunerLog.trace(
                "frame \(frameIndex): \(count) samples, rms \(String(format: "%.4f", analysis.rms))"
                    + ", clarity \(String(format: "%.2f", analysis.clarity))"
                    + ", pitch \(analysis.frequency.map { String(format: "%.1f Hz", $0) } ?? "—")"
            )
        }

        let stabilized = stabilizer.process(analysis, at: now)
        let reading = evaluator.evaluate(stabilized, selection: selection, timestamp: now)
        onReading?(reading)

        // The spectrum is a display element: 10 Hz is plenty and keeps the FFT cost
        // well below the detector's.
        if let onSpectrum, frameIndex % 2 == 0 {
            onSpectrum(spectrumAnalyzer.analyze(samples: frame, sampleRate: sampleRate))
        }
        if let onChroma, frameIndex % 2 == 1 {
            onChroma(chromaAnalyzer.analyze(samples: frame, sampleRate: sampleRate))
        }
    }

    /// Low tunings need a longer window to see enough periods: 8-string F♯1 (23 Hz) has a
    /// 43 ms period, so four periods already need ~170 ms — twice the default 4096-sample
    /// window at 48 kHz. The window grows with the tuning and stays where it is otherwise.
    private func updateAnalysisWindow(sampleRate: Double) {
        let minFrequency = max(detector.configuration.minFrequency, 1)
        let needed = Int(4 * sampleRate / minFrequency)
        let target = min(max(PitchDetectionConfiguration.default.analysisWindowSize, needed), 16384)
        if detector.configuration.analysisWindowSize != target {
            detector.configuration.analysisWindowSize = target
        }
    }
}
