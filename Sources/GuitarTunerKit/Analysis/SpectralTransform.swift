import Foundation

#if canImport(Accelerate)
import Accelerate
#endif

/// Reusable Hann-windowed FFT.
///
/// Owned by the analysis queue and used from one thread, which is why it is
/// `@unchecked Sendable` with preallocated buffers instead of building an FFT setup per
/// frame. `vDSP_DFT` is used rather than the `vDSP.FFT` wrapper because a DFT setup takes
/// the transform length directly — no guessing about how a split-complex buffer maps onto
/// `log2n`.
final class SpectralTransform: @unchecked Sendable {
    private var window: [Float] = []
    private var realInput: [Float] = []
    private var imagInput: [Float] = []
    private var realOutput: [Float] = []
    private var imagOutput: [Float] = []
    private var magnitudes: [Float] = []
    #if canImport(Accelerate)
    private var dft: vDSP_DFT_Setup?
    #endif

    private(set) var size = 0

    deinit {
        #if canImport(Accelerate)
        if let dft { vDSP_DFT_DestroySetup(dft) }
        #endif
    }

    /// Largest power of two that fits, clamped to `maximum` and never below 512.
    static func preferredSize(for count: Int, maximum: Int) -> Int {
        var size = 512
        let limit = max(maximum, 512)
        while size * 2 <= count, size * 2 <= limit {
            size *= 2
        }
        return size
    }

    /// Magnitude spectrum (size / 2 bins) of the most recent `requestedSize` samples.
    /// Returns a copy-on-write share of the internal buffer, so the result stays valid
    /// even after the next call.
    func transform(samples: [Float], requestedSize: Int) -> [Float] {
        let size = requestedSize
        guard size >= 512, samples.count >= size, prepare(size: size) else { return [] }

        let start = samples.count - size
        for index in 0..<size {
            realInput[index] = samples[start + index] * window[index]
            imagInput[index] = 0
        }

        #if canImport(Accelerate)
        guard let dft else { return [] }
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
        #else
        return []
        #endif

        return magnitudes
    }

    private func prepare(size requestedSize: Int) -> Bool {
        guard requestedSize != size else { return true }
        size = requestedSize

        window = (0..<requestedSize).map { index in
            0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(requestedSize - 1))
        }
        realInput = [Float](repeating: 0, count: requestedSize)
        imagInput = [Float](repeating: 0, count: requestedSize)
        realOutput = [Float](repeating: 0, count: requestedSize)
        imagOutput = [Float](repeating: 0, count: requestedSize)
        magnitudes = [Float](repeating: 0, count: requestedSize / 2)

        #if canImport(Accelerate)
        if let dft { vDSP_DFT_DestroySetup(dft) }
        dft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(requestedSize), .FORWARD)
        return dft != nil
        #else
        return false
        #endif
    }
}
