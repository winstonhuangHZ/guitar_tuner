import Foundation

/// One measurement kept for later: how far a target was off, and when.
public struct TuningSample: Sendable, Equatable, Codable {
    /// Seconds since 1970.
    public var timestamp: TimeInterval
    /// `presetID:stringIndex` for a string, or `chromatic:MIDI` in chromatic mode.
    public var targetID: String
    public var label: String
    public var cents: Double
    public var referencePitch: Double

    public init(
        timestamp: TimeInterval,
        targetID: String,
        label: String,
        cents: Double,
        referencePitch: Double = NoteMath.defaultReferencePitch
    ) {
        self.timestamp = timestamp
        self.targetID = targetID
        self.label = label
        self.cents = cents
        self.referencePitch = referencePitch
    }
}

/// What the history says about each string.
public struct TuningHistorySummary: Sendable, Equatable {
    public struct StringStat: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var sampleCount: Int
        /// Mean deviation; negative means the string sits flat.
        public var averageCents: Double
        /// How often it was within the in-tune window.
        public var inTuneRatio: Double
        public var lastSeen: TimeInterval?

        /// A string that is consistently off in the same direction is worth a look —
        /// it usually means the instrument drifted, not the player.
        public var hint: String? {
            guard sampleCount >= 5 else { return nil }
            if averageCents <= -6 { return "\(label) has been sitting flat" }
            if averageCents >= 6 { return "\(label) has been sitting sharp" }
            if inTuneRatio < 0.4 { return "\(label) rarely settles in tune" }
            return nil
        }
    }

    public var stats: [StringStat]
    public var sampleCount: Int
    public var firstSample: TimeInterval?
    public var lastSample: TimeInterval?

    public static let empty = TuningHistorySummary(stats: [], sampleCount: 0, firstSample: nil, lastSample: nil)

    public var isEmpty: Bool { sampleCount == 0 }

    public var hints: [String] { stats.compactMap(\.hint) }
}

/// Append-only store for tuning measurements, kept as JSON so it stays inspectable.
public struct TuningHistoryStore: @unchecked Sendable {
    public var maximumSamples: Int
    public var inTuneToleranceCents: Double
    private let url: URL
    private let fileManager: FileManager

    public init(
        url: URL? = nil,
        maximumSamples: Int = 5000,
        inTuneToleranceCents: Double = 5,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.maximumSamples = max(100, maximumSamples)
        self.inTuneToleranceCents = inTuneToleranceCents
        if let url {
            self.url = url
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.url = base
                .appendingPathComponent("GuitarTuner", isDirectory: true)
                .appendingPathComponent("tuning-history.json")
        }
    }

    public var fileURL: URL { url }

    public func load() -> [TuningSample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TuningSample].self, from: data)) ?? []
    }

    /// Appends samples, trims to `maximumSamples`, and writes the file back.
    @discardableResult
    public func append(contentsOf samples: [TuningSample]) -> [TuningSample] {
        guard !samples.isEmpty else { return load() }
        var all = load()
        all.append(contentsOf: samples)
        if all.count > maximumSamples {
            all.removeFirst(all.count - maximumSamples)
        }
        save(all)
        return all
    }

    public func clear() {
        try? fileManager.removeItem(at: url)
    }

    private func save(_ samples: [TuningSample]) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(samples)
            try data.write(to: url, options: .atomic)
        } catch {
            TunerLog.trace("history write failed: \(error.localizedDescription)")
        }
    }

    public func summary(since: TimeInterval? = nil) -> TuningHistorySummary {
        var samples = load()
        if let since {
            samples = samples.filter { $0.timestamp >= since }
        }
        guard !samples.isEmpty else { return .empty }

        var groups: [String: [TuningSample]] = [:]
        for sample in samples {
            groups[sample.targetID, default: []].append(sample)
        }

        let stats = groups.map { id, group -> TuningHistorySummary.StringStat in
            let cents = group.map(\.cents)
            let average = cents.reduce(0, +) / Double(cents.count)
            let inTune = cents.filter { abs($0) <= inTuneToleranceCents }.count
            return TuningHistorySummary.StringStat(
                id: id,
                label: group.last?.label ?? id,
                sampleCount: group.count,
                averageCents: average,
                inTuneRatio: Double(inTune) / Double(cents.count),
                lastSeen: group.map(\.timestamp).max()
            )
        }
        .sorted { $0.id < $1.id }

        return TuningHistorySummary(
            stats: stats,
            sampleCount: samples.count,
            firstSample: samples.map(\.timestamp).min(),
            lastSample: samples.map(\.timestamp).max()
        )
    }

    /// Records a reading if enough time has passed since the previous one, so a 20 Hz
    /// stream does not fill the file.
    public func shouldRecord(lastSample: TuningSample?, now: TimeInterval, minimumInterval: TimeInterval = 1) -> Bool {
        guard let lastSample else { return true }
        return now - lastSample.timestamp >= minimumInterval
    }
}
