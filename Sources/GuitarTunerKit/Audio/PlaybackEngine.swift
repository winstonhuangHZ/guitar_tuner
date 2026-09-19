import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// One scheduled beat, published so the UI can flash in time.
public struct MetronomeBeat: Sendable, Equatable {
    public var tickIndex: Int
    public var accent: MetronomeAccent
    /// Host time the click is scheduled for.
    public var hostTime: UInt64
    /// Seconds between ticks.
    public var duration: Double
    public var beatNumber: Int
    public var barNumber: Int
}

/// Plays reference tones and the metronome.
///
/// Two deliberate choices:
///
/// - `AVAudioPlayerNode` with pre-rendered buffers, not a source node with a render
///   callback. Scheduling needs no Swift closure on the audio thread, which is the class
///   of bug that crashed this app once already: a closure created inside a `@MainActor`
///   method inherits main-actor isolation, and AVFAudio calling it from its own thread
///   trips a runtime assertion.
/// - All of it runs on the main actor. Timing accuracy does not come from the timer — it
///   comes from the sample times handed to `scheduleBuffer(at:)`, so a main-thread timer
///   waking up a few hundred milliseconds early or late changes nothing.
@MainActor
final class PlaybackEngine {
    #if canImport(AVFoundation)
    private let player = AVAudioPlayerNode()
    private var accentClick: AVAudioPCMBuffer?
    private var plainClick: AVAudioPCMBuffer?
    private var bufferFormat: AVAudioFormat?
    private var timer: Timer?
    private var connectedSampleRate: Double?
    #endif

    private var clock = MetronomeClock()
    private var nextTickSampleTime: AVAudioFramePosition = 0
    private var accentsEnabled = true
    private var volume: Double = 0.7

    private(set) var isMetronomeRunning = false
    /// Called on the main actor for every scheduled click.
    var onBeat: ((MetronomeBeat) -> Void)?

    init() {}

    #if canImport(AVFoundation)
    /// Attaches the player node and renders the click sounds.
    func attach(to engine: AVAudioEngine, sampleRate: Double) {
        // Prefer the rate we were handed, then the output hardware, then a sane default.
        // Returning early on 0 Hz is what silenced playback: before the graph is prepared
        // the mixer can still report no format at all.
        let rate = [sampleRate, engine.outputNode.outputFormat(forBus: 0).sampleRate, 48_000]
            .first { $0 > 0 } ?? 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        TunerLog.trace("playback attached at \(rate) Hz")
        if player.engine == nil {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedSampleRate = sampleRate
        } else if connectedSampleRate != sampleRate {
            // A device change moves the hardware rate; the clicks have to be re-rendered
            // and the connection re-made, or they play back at the wrong pitch.
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedSampleRate = sampleRate
        }
        bufferFormat = format
        accentClick = Self.makeBuffer(
            samples: ToneSynthesizer.click(accented: true, sampleRate: sampleRate),
            format: format
        )
        plainClick = Self.makeBuffer(
            samples: ToneSynthesizer.click(accented: false, sampleRate: sampleRate),
            format: format
        )
        player.volume = Float(volume)
    }

    /// Plays a synthesised buffer once, replacing whatever tone was playing.
    func playTone(_ samples: [Float]) {
        guard player.engine != nil, let bufferFormat, !samples.isEmpty,
              let buffer = Self.makeBuffer(samples: samples, format: bufferFormat) else { return }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
    }

    /// Stops a reference tone. The metronome keeps its own schedule, so it is only stopped
    /// when it is not running.
    func stopTone() {
        guard !isMetronomeRunning else { return }
        player.stop()
    }

    func startMetronome(pattern: MetronomePattern, tempo: Double, accents: Bool, volume: Double) {
        guard player.engine != nil else { return }
        stopMetronome()
        clock = MetronomeClock(pattern: pattern, tempo: tempo)
        accentsEnabled = accents
        self.volume = volume
        player.volume = Float(volume)
        nextTickSampleTime = 0
        isMetronomeRunning = true
        if !player.isPlaying { player.play() }
        scheduleAhead()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleAhead()
            }
        }
    }

    func updateMetronome(
        pattern: MetronomePattern? = nil,
        tempo: Double? = nil,
        accents: Bool? = nil,
        volume: Double? = nil
    ) {
        if let accents { accentsEnabled = accents }
        if let volume {
            self.volume = volume
            player.volume = Float(volume)
        }
        guard isMetronomeRunning else {
            clock.update(pattern: pattern, tempo: tempo)
            return
        }
        if let pattern, pattern != clock.pattern {
            // A new time signature restarts the bar: keeping the tick index would put the
            // accents in the wrong places.
            startMetronome(
                pattern: pattern,
                tempo: tempo ?? clock.tempo,
                accents: accentsEnabled,
                volume: self.volume
            )
            return
        }
        clock.update(pattern: pattern, tempo: tempo)
    }

    func stopMetronome() {
        timer?.invalidate()
        timer = nil
        isMetronomeRunning = false
        player.stop()
    }

    func stopAll() {
        stopMetronome()
    }

    /// Schedules every tick that falls inside the look-ahead window.
    private func scheduleAhead() {
        guard isMetronomeRunning, let accentClick, let plainClick else { return }
        guard let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime),
              playerTime.sampleRate > 0 else { return }

        let sampleRate = playerTime.sampleRate
        let target = playerTime.sampleTime + AVAudioFramePosition(1.2 * sampleRate)
        var scheduled = 0

        while nextTickSampleTime < target, scheduled < 256 {
            scheduled += 1
            let accent = clock.accent
            let useAccent = accentsEnabled && (accent == .downbeat || accent == .groupStart)
            let buffer = useAccent ? accentClick : plainClick
            let when = AVAudioTime(sampleTime: nextTickSampleTime, atRate: sampleRate)
            player.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)

            let offset = max(Double(nextTickSampleTime - playerTime.sampleTime) / sampleRate, 0)
            onBeat?(
                MetronomeBeat(
                    tickIndex: clock.tickIndex,
                    accent: accent,
                    hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: offset),
                    duration: clock.tickDuration,
                    beatNumber: clock.beatNumber,
                    barNumber: clock.barNumber
                )
            )

            nextTickSampleTime += AVAudioFramePosition((clock.tickDuration * sampleRate).rounded())
            clock.advance()
        }
    }

    private static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            channel[index] = samples[index]
        }
        return buffer
    }
    #else
    func attach(to engine: AnyObject, sampleRate: Double) {}
    func playTone(_ samples: [Float]) {}
    func stopTone() {}
    func startMetronome(pattern: MetronomePattern, tempo: Double, accents: Bool, volume: Double) {}
    func updateMetronome(pattern: MetronomePattern? = nil, tempo: Double? = nil, accents: Bool? = nil, volume: Double? = nil) {}
    func stopMetronome() {}
    func stopAll() {}
    #endif
}
