import Foundation
import GuitarTunerKit

private func temporaryHistoryURL(_ name: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("guitar-tuner-checks-\(name)", isDirectory: true)
        .appendingPathComponent("history.json")
}

func runHistoryChecks(_ runner: CheckRunner) {
    runner.group("Tuning history")

    let url = temporaryHistoryURL("history")
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    let store = TuningHistoryStore(url: url, maximumSamples: 120)

    runner.equal(store.load().count, 0, "a fresh store is empty")
    runner.expect(store.summary().isEmpty, "an empty store summarises to nothing")

    let base = Date().timeIntervalSince1970 - 3600
    var samples: [TuningSample] = []
    // Low E drifts flat, the A string sits in tune, the D string is always sharp.
    for index in 0..<30 {
        samples.append(TuningSample(timestamp: base + Double(index), targetID: "std:0", label: "E2 · 6th string", cents: -9))
        samples.append(TuningSample(timestamp: base + Double(index), targetID: "std:1", label: "A2 · 5th string", cents: 1))
        samples.append(TuningSample(timestamp: base + Double(index), targetID: "std:2", label: "D3 · 4th string", cents: 12))
    }
    store.append(contentsOf: samples)

    let loaded = store.load()
    runner.equal(loaded.count, samples.count, "every sample is written and read back")
    runner.equal(loaded.first?.targetID, "std:0", "order is preserved")
    runner.near(loaded.first?.cents ?? 0, -9, accuracy: 1e-9, "values survive the round trip")
    runner.equal(loaded.first?.label, "E2 · 6th string", "labels survive the round trip")

    let summary = store.summary()
    runner.equal(summary.sampleCount, 90, "summary counts every sample")
    runner.equal(summary.stats.count, 3, "one stat per string")
    runner.equal(summary.stats.first?.id, "std:0", "stats are sorted by target")
    runner.near(summary.stats[0].averageCents, -9, accuracy: 1e-9, "flat string average")
    runner.near(summary.stats[1].averageCents, 1, accuracy: 1e-9, "in-tune string average")
    runner.near(summary.stats[1].inTuneRatio, 1, accuracy: 1e-9, "in-tune ratio for a settled string")
    runner.near(summary.stats[2].inTuneRatio, 0, accuracy: 1e-9, "in-tune ratio for a sharp string")
    runner.isNotNil(summary.firstSample, "first sample timestamp")
    runner.isNotNil(summary.lastSample, "last sample timestamp")

    let hints = summary.hints
    runner.expect(
        hints.contains { $0.contains("flat") },
        "a consistently flat string is called out (\(hints.joined(separator: " / ")))"
    )
    runner.expect(hints.contains { $0.contains("sharp") }, "a consistently sharp string is called out")
    runner.equal(hints.count, 2, "the settled string gets no hint")

    // A short window only looks at recent samples.
    let recent = store.summary(since: base + 20)
    runner.equal(recent.sampleCount, 30, "a time window filters samples")

    // Trimming keeps the newest data.
    for index in 0..<200 {
        store.append(contentsOf: [
            TuningSample(timestamp: base + 100 + Double(index), targetID: "std:0", label: "E2 · 6th string", cents: 4)
        ])
    }
    let trimmed = store.load()
    runner.lessOrEqual(trimmed.count, store.maximumSamples, "the file is capped")
    runner.near(trimmed.last?.cents ?? 0, 4, accuracy: 1e-9, "the newest samples are the ones kept")

    // Recording cadence: one sample per second, not twenty.
    let first = TuningSample(timestamp: 100, targetID: "std:0", label: "E2", cents: 1)
    runner.expect(store.shouldRecord(lastSample: nil, now: 100), "the first reading is recorded")
    runner.expect(!store.shouldRecord(lastSample: first, now: 100.5), "half a second later is too soon")
    runner.expect(store.shouldRecord(lastSample: first, now: 101.2), "a second later is recorded")

    store.clear()
    runner.equal(store.load().count, 0, "clearing removes the file contents")

    // Two stores must not share state.
    let otherURL = temporaryHistoryURL("history-other")
    try? FileManager.default.removeItem(at: otherURL.deletingLastPathComponent())
    let other = TuningHistoryStore(url: otherURL)
    runner.equal(other.load().count, 0, "a second store starts empty")
    runner.expect(other.fileURL != store.fileURL, "stores use their own file")
}
