import Foundation

#if canImport(Accelerate)
import Accelerate
#endif

/// One frame of spectrum data ready for display: log-spaced bars between two
/// frequencies, normalised so the strongest partial sits at 1.
public struct SpectrumSnapshot: Sendable, Equatable {
    /// Bar heights, `0...1`, from `minFrequency` to `maxFrequency` on a log axis.
    public var levels: [Float]
    public var minFrequency: Double
    public var maxFrequency: Double
    /// Strongest partial in the frame (useful to sanity-check what the detector sees).
    public var peakFrequency: Double?

    public init(
        levels: [Float] = [],
        minFrequency: Double = 40,
        maxFrequency: Double = 4000,
        peakFrequency: Double? = nil
    ) {
        self.levels = levels
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.peakFrequency = peakFrequency
    }

    public static let empty = SpectrumSnapshot()

    public var isEmpty: Bool { levels.isEmpty }

    /// Position of a frequency on the 0...1 log axis, or `nil` when it is off screen.
    public func position(forFrequency frequency: Double) -> Double? {
        guard frequency > 0, minFrequency > 0, maxFrequency > minFrequency else { return nil }
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }
        return log(frequency / minFrequency) / log(maxFrequency / minFrequency)
    }
}

/// Hann-windowed FFT display analyser.
///
/// Notes on the design:
/// - It runs on the audio-analysis queue only (single owner), which is why it is
///   `@unchecked Sendable` with preallocated scratch buffers instead of allocating a new
///   FFT setup for every frame.
/// - Levels are normalised against the strongest partial of the frame with a 60 dB
///   window. A tuner's job is to show *which* partials are present, so relative shape
///   is more useful than the absolute level (which the level meter already shows).
public final class SpectrumAnalyzer: @unchecked Sendable {
    public let binCount: Int
    /// Display band. Follows the selected tuning (bass goes lower, ukulele higher).
    public private(set) var minFrequency: Double
    public private(set) var maxFrequency: Double
    /// Dynamic range below the strongest partial that still maps into the display.
    public let dynamicRangeDecibels: Double
    /// Upper bound for the FFT itself; must be a power of two.
    public let maximumWindowSize: Int

    private var levels: [Float] = []
    private var signal: [Float] = []
    private var realInput: [Float] = []
    private var imagInput: [Float] = []
    private var realOutput: [Float] = []
    private var imagOutput: [Float] = []
    private var magnitudes: [Float] = []
    private var window: [Float] = []
    #if canImport(Accelerate)
    /// `vDSP_DFT` is used instead of the `vDSP.FFT` wrapper because a DFT setup takes the
    /// transform length directly — no guessing about how a split-complex buffer maps onto
    /// `log2n`.
    private var dft: vDSP_DFT_Setup?
    #endif
    private var preparedSize = 0

    public init(
        binCount: Int = 96,
        minFrequency: Double = 40,
        maxFrequency: Double = 4000,
        dynamicRangeDecibels: Double = 60,
        maximumWindowSize: Int = 8192
    ) {
        self.binCount = max(16, binCount)
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.dynamicRangeDecibels = dynamicRangeDecibels
        self.maximumWindowSize = max(1024, maximumWindowSize)
    }

    /// Samples the analyser wants per frame so the low end of the band is resolved.
    public var windowSize: Int { maximumWindowSize }

    /// Called when the selected tuning changes the useful frequency band.
    public func setFrequencyRange(min: Double, max: Double) {
        let lower = Swift.max(20, min)
        let upper = Swift.max(lower * 4, max)
        guard lower != minFrequency || upper != maxFrequency else { return }
        minFrequency = lower
        maxFrequency = upper
    }

    public func analyze(samples: [Float], sampleRate: Double) -> SpectrumSnapshot {
        guard sampleRate > 0, samples.count >= 512 else { return .empty }
        let size = fftSize(for: Swift.min(samples.count, maximumWindowSize))
        guard size >= 512 else { return .empty }
        prepare(size: size)
        fillBuffers(samples: samples, size: size)
        transform(size: size)
        return snapshot(size: size, sampleRate: sampleRate)
    }

    // MARK: - Setup

    private func fftSize(for count: Int) -> Int {
        var size = 512
        while size * 2 <= count {
            size *= 2
        }
        return size
    }

    private func prepare(size: Int) {
        guard preparedSize != size else { return }
        preparedSize = size
        let half = size / 2
        signal = [Float](repeating: 0, count: size)
        realInput = [Float](repeating: 0, count: size)
        imagInput = [Float](repeating: 0, count: size)
        realOutput = [Float](repeating: 0, count: size)
        imagOutput = [Float](repeating: 0, count: size)
        magnitudes = [Float](repeating: 0, count: half)
        window = (0..<size).map { index in
            0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(size - 1))
        }
        #if canImport(Accelerate)
        if let dft { vDSP_DFT_DestroySetup(dft) }
        dft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
        #endif
    }

    private func fillBuffers(samples: [Float], size: Int) {
        let start = samples.count - size
        for index in 0..<size {
            realInput[index] = samples[start + index] * window[index]
            imagInput[index] = 0
        }
    }

    // MARK: - FFT

    private func transform(size: Int) {
        #if canImport(Accelerate)
        guard let dft else { return }
        realInput.withUnsafeMutableBufferPointer { real in
            imagInput.withUnsafeMutableBufferPointer { imag in
                realOutput.withUnsafeMutableBufferPointer { outReal in
                    imagOutput.withUnsafeMutableBufferPointer { outImag in
                        guard
                            let realBase = real.baseAddress,
                            let imagBase = imag.baseAddress,
                            let outRealBase = outReal.baseAddress,
                            let outImagBase = outImag.baseAddress
                        else { return }

                        vDSP_DFT_Execute(dft, realBase, imagBase, outRealBase, outImagBase)

                        magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                            guard let magnitudeBase = magnitudeBuffer.baseAddress else { return }
                            var output = DSPSplitComplex(realp: outRealBase, imagp: outImagBase)
                            vDSP_zvabs(&output, 1, magnitudeBase, 1, vDSP_Length(size / 2))
                        }
                    }
                }
            }
        }
        #endif
    }

    deinit {
        #if canImport(Accelerate)
        if let dft { vDSP_DFT_DestroySetup(dft) }
        #endif
    }

    // MARK: - Display mapping

    private func snapshot(size: Int, sampleRate: Double) -> SpectrumSnapshot {
        if levels.count != binCount {
            levels = [Float](repeating: 0, count: binCount)
        } else {
            for index in levels.indices { levels[index] = 0 }
        }

        let half = size / 2
        guard half > 1, maxFrequency > minFrequency else { return .empty }

        let logSpan = log(maxFrequency / minFrequency)
        // Hann window coherent gain is 0.5, and a real sine splits its energy between
        // the positive and negative frequencies, hence the factor 4.
        let amplitudeScale = 4 / Float(size)

        var peakAmplitude: Float = 0
        var peakFrequency: Double?

        for bin in 1..<half {
            let frequency = Double(bin) * sampleRate / Double(size)
            guard frequency >= minFrequency, frequency <= maxFrequency else { continue }

            let amplitude = magnitudes[bin] * amplitudeScale
            if amplitude > peakAmplitude {
                peakAmplitude = amplitude
                peakFrequency = frequency
            }

            let position = log(frequency / minFrequency) / logSpan
            let index = Swift.min(binCount - 1, Swift.max(0, Int(position * Double(binCount))))
            levels[index] = Swift.max(levels[index], amplitude)
        }

        guard peakAmplitude > 1e-7 else {
            for index in levels.indices { levels[index] = 0 }
            return SpectrumSnapshot(levels: levels, minFrequency: minFrequency, maxFrequency: maxFrequency)
        }

        // Fill display bins that are narrower than the FFT resolution so the low end of
        // the axis has no holes in it.
        if binCount > 2 {
            for index in 1..<(binCount - 1) where levels[index] == 0 {
                levels[index] = Swift.max(levels[index - 1], levels[index + 1])
            }
        }

        let floor = Float(-dynamicRangeDecibels)
        for index in levels.indices {
            let decibels = 20 * log10(Swift.max(levels[index] / peakAmplitude, 1e-7))
            levels[index] = Swift.min(Swift.max((decibels - floor) / Float(dynamicRangeDecibels), 0), 1)
        }

        return SpectrumSnapshot(
            levels: levels,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency,
            peakFrequency: peakFrequency
        )
    }
}
