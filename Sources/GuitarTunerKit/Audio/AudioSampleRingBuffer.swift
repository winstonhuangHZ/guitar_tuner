import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Single-producer / single-consumer ring buffer between the real-time audio tap and
/// the analysis queue.
///
/// The writer (audio thread) only ever *tries* to take the lock, so it can never be
/// blocked by the analyser and cannot cause a priority inversion. If the lock happens
/// to be busy the block is dropped, which is inaudible for tuning purposes.
public final class AudioSampleRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float]
    private var writeIndex = 0
    private var filledCount = 0
    private var storedSampleRate: Double
    /// Reused by the multi-channel downmix path so the audio thread never allocates.
    private var downmixScratch = [Float](repeating: 0, count: 4096)

    public init(capacity: Int = 1 << 16, sampleRate: Double = 44_100) {
        let size = max(capacity, 1024)
        self.storage = [Float](repeating: 0, count: size)
        self.storedSampleRate = sampleRate
    }

    public var capacity: Int { storage.count }

    public var availableSampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return filledCount
    }

    public var sampleRate: Double {
        lock.lock()
        defer { lock.unlock() }
        return storedSampleRate
    }

    /// Called when the engine (re)starts or the hardware format changes.
    public func reset(sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        filledCount = 0
        storedSampleRate = sampleRate
    }

    /// Appends samples, overwriting the oldest data when the buffer is full.
    @discardableResult
    public func append(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        guard !samples.isEmpty, let source = samples.baseAddress else { return false }
        guard lock.try() else { return false }
        defer { lock.unlock() }

        let count = samples.count
        storage.withUnsafeMutableBufferPointer { destination in
            guard let base = destination.baseAddress, destination.count > 0 else { return }
            let firstChunk = min(count, destination.count - writeIndex)
            base.advanced(by: writeIndex).update(from: source, count: firstChunk)
            if count > firstChunk {
                base.update(from: source.advanced(by: firstChunk), count: count - firstChunk)
            }
        }
        writeIndex = (writeIndex + count) % storage.count
        filledCount = min(filledCount + count, storage.count)
        return true
    }

    /// Copies the newest `count` samples into `destination` in chronological order.
    /// `destination` is only resized when its length changes, so the analysis loop can
    /// reuse a single buffer for the lifetime of the app.
    @discardableResult
    public func latest(count requested: Int, into destination: inout [Float]) -> Int {
        guard requested > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        let count = min(requested, filledCount)
        guard count > 0 else { return 0 }

        if destination.count != count {
            destination = [Float](repeating: 0, count: count)
        }

        let start = (writeIndex - count + storage.count) % storage.count
        storage.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.withUnsafeMutableBufferPointer { target in
                guard let targetBase = target.baseAddress, target.count == count else { return }
                let firstChunk = min(count, storage.count - start)
                targetBase.update(from: base.advanced(by: start), count: firstChunk)
                if count > firstChunk {
                    targetBase.advanced(by: firstChunk).update(from: base, count: count - firstChunk)
                }
            }
        }
        return count
    }
}

#if canImport(AVFoundation)
public extension AudioSampleRingBuffer {
    /// Downmixes and appends an audio tap buffer. Runs on the audio thread: no
    /// allocation, no blocking.
    @discardableResult
    func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return false }
        let channelCount = max(1, Int(buffer.format.channelCount))

        if channelCount == 1 {
            return append(UnsafeBufferPointer(start: channels[0], count: frames))
        }

        // Average the channels: on a device with several capsules one may be quieter or
        // noisier than another, and averaging is cheaper than deciding which to trust.
        if downmixScratch.count < frames {
            downmixScratch = [Float](repeating: 0, count: frames)
        }
        downmixScratch.withUnsafeMutableBufferPointer { scratch in
            guard let scratchBase = scratch.baseAddress else { return }
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channels[channel][frame]
                }
                scratchBase[frame] = sum / Float(channelCount)
            }
        }
        return downmixScratch.withUnsafeBufferPointer { scratch in
            guard let scratchBase = scratch.baseAddress else { return false }
            return append(UnsafeBufferPointer(start: scratchBase, count: frames))
        }
    }
}
#endif
