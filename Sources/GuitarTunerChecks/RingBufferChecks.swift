import Foundation
import GuitarTunerKit

private func ramp(_ range: Range<Int>) -> [Float] {
    range.map { Float($0) }
}

private func append(_ samples: [Float], to buffer: AudioSampleRingBuffer) {
    _ = samples.withUnsafeBufferPointer { buffer.append($0) }
}

func runRingBufferChecks(_ runner: CheckRunner) {
    runner.group("Sample ring buffer")

    let buffer = AudioSampleRingBuffer(capacity: 4096)
    append(ramp(0..<1000), to: buffer)
    var destination: [Float] = []
    runner.equal(buffer.latest(count: 1000, into: &destination), 1000, "reads back every sample")
    runner.equal(destination, ramp(0..<1000), "chronological order")

    let wrapping = AudioSampleRingBuffer(capacity: 1024)
    append(ramp(0..<1500), to: wrapping)
    runner.equal(wrapping.latest(count: 100, into: &destination), 100, "wrap-around read")
    runner.equal(destination, ramp(1400..<1500), "newest samples survive the wrap")
    runner.equal(wrapping.availableSampleCount, 1024, "buffer fills to capacity")

    let small = AudioSampleRingBuffer(capacity: 4096)
    append(ramp(0..<10), to: small)
    runner.equal(small.latest(count: 1000, into: &destination), 10, "reads what exists")
    runner.equal(destination, ramp(0..<10), "short buffer contents")

    let boundary = AudioSampleRingBuffer(capacity: 1024)
    append(ramp(0..<1024), to: boundary)
    append(ramp(1024..<1040), to: boundary)
    runner.equal(boundary.latest(count: 64, into: &destination), 64, "read across the wrap boundary")
    runner.equal(destination, ramp(976..<1040), "wrap boundary contents")

    let empty = AudioSampleRingBuffer(capacity: 4096)
    var emptyDestination: [Float] = []
    runner.equal(empty.latest(count: 512, into: &emptyDestination), 0, "empty buffer returns nothing")
    runner.expect(emptyDestination.isEmpty, "empty buffer leaves the destination empty")

    let resettable = AudioSampleRingBuffer(capacity: 4096, sampleRate: 44_100)
    append(ramp(0..<2000), to: resettable)
    resettable.reset(sampleRate: 48_000)
    runner.equal(resettable.availableSampleCount, 0, "reset clears samples")
    runner.near(resettable.sampleRate, 48_000, accuracy: 0, "reset stores the new sample rate")
    runner.equal(resettable.latest(count: 256, into: &destination), 0, "nothing to read after reset")

    // The destination buffer is reused, not reallocated, when the length matches.
    let reuse = AudioSampleRingBuffer(capacity: 4096)
    append(ramp(0..<512), to: reuse)
    var reused = [Float](repeating: -1, count: 512)
    _ = reuse.latest(count: 512, into: &reused)
    runner.equal(reused.count, 512, "destination buffer length is kept")
    runner.equal(reused[511], 511, "destination buffer contents")
}
