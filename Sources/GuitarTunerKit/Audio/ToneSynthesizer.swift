import Foundation

/// Generates the sounds the app plays back: reference tones, chord references and
/// metronome clicks.
///
/// Everything is synthesised rather than bundled. A reference tone should sound like a
/// plucked string (a bare sine is harder to match against), a chord reference is several
/// of those at once, and a click is a short blip whose pitch marks the accent.
public enum ToneSynthesizer {
    /// Relative amplitudes of partials 1…6 of a plucked string.
    public static let pluckPartials: [Double] = [1.0, 0.55, 0.32, 0.2, 0.12, 0.07]

    /// A plucked-string-like tone with an exponential decay.
    public static func plucked(
        frequency: Double,
        duration: Double,
        sampleRate: Double,
        amplitude: Double = 0.5,
        decay: Double = 2.2,
        partials: [Double] = pluckPartials
    ) -> [Float] {
        guard frequency > 0, duration > 0, sampleRate > 0, !partials.isEmpty else { return [] }
        let count = max(1, Int(duration * sampleRate))
        var samples = [Float](repeating: 0, count: count)
        let nyquist = sampleRate / 2

        for (offset, weight) in partials.enumerated() {
            let partialFrequency = frequency * Double(offset + 1)
            guard partialFrequency < nyquist else { break }
            let step = 2 * Double.pi * partialFrequency / sampleRate
            for index in 0..<count {
                let time = Double(index) / sampleRate
                samples[index] += Float(amplitude * weight * exp(-time * decay) * sin(step * Double(index)))
            }
        }

        normalize(&samples, ceiling: 0.95)
        applyFades(&samples, sampleRate: sampleRate)
        return samples
    }

    /// Several notes at once, for a chord reference.
    public static func chord(
        frequencies: [Double],
        duration: Double,
        sampleRate: Double,
        amplitude: Double = 0.22,
        decay: Double = 1.1
    ) -> [Float] {
        let playable = frequencies.filter { $0 > 0 }
        guard !playable.isEmpty, duration > 0, sampleRate > 0 else { return [] }
        let count = max(1, Int(duration * sampleRate))
        var samples = [Float](repeating: 0, count: count)
        let nyquist = sampleRate / 2
        let perNote = amplitude / Double(playable.count).squareRoot()

        for frequency in playable {
            for (offset, weight) in pluckPartials.enumerated() {
                let partialFrequency = frequency * Double(offset + 1)
                guard partialFrequency < nyquist else { break }
                let step = 2 * Double.pi * partialFrequency / sampleRate
                for index in 0..<count {
                    let time = Double(index) / sampleRate
                    samples[index] += Float(perNote * weight * exp(-time * decay) * sin(step * Double(index)))
                }
            }
        }

        normalize(&samples, ceiling: 0.9)
        applyFades(&samples, sampleRate: sampleRate)
        return samples
    }

    /// Metronome click.
    public static func click(
        accented: Bool,
        sampleRate: Double,
        amplitude: Double = 0.8
    ) -> [Float] {
        plucked(
            frequency: accented ? 1760.0 : 1174.0,
            duration: accented ? 0.055 : 0.04,
            sampleRate: sampleRate,
            amplitude: amplitude,
            decay: accented ? 90 : 130,
            partials: [1.0, 0.35]
        )
    }

    /// Frequencies of a chord shape, in tuning order.
    public static func frequencies(
        of voicing: ChordVoicing,
        capoFret: Int = 0,
        referencePitch: Double = NoteMath.defaultReferencePitch
    ) -> [Double] {
        voicing.notes.map {
            NoteMath.frequency(midiNumber: Double($0.midiNumber + capoFret), referencePitch: referencePitch)
        }
    }

    private static func normalize(_ samples: inout [Float], ceiling: Float) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > ceiling else { return }
        let scale = ceiling / peak
        for index in samples.indices { samples[index] *= scale }
    }

    /// Short fades so a scheduled buffer never starts or ends with a click.
    private static func applyFades(_ samples: inout [Float], sampleRate: Double) {
        let fade = min(samples.count / 2, max(1, Int(0.004 * sampleRate)))
        guard fade > 1, samples.count > 2 * fade else { return }
        for index in 0..<fade {
            let gain = Float(index) / Float(fade)
            samples[index] *= gain
            samples[samples.count - 1 - index] *= gain
        }
    }
}
