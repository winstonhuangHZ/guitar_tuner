import Foundation

public extension InstrumentString {
    /// The same string with the instrument capoed at `semitones`: the shape is unchanged,
    /// the sounding pitch moves up. The label keeps the physical string position, while
    /// `noteName` reports what is actually heard.
    func transposed(by semitones: Int) -> InstrumentString {
        guard semitones != 0 else { return self }
        return InstrumentString(id: id, midiNumber: midiNumber + semitones, label: label)
    }

    func frequency(capoFret: Int, referencePitch: Double = NoteMath.defaultReferencePitch) -> Double {
        NoteMath.frequency(of: Note(midiNumber: midiNumber + capoFret), referencePitch: referencePitch)
    }
}

public extension TuningPreset {
    /// Target strings as heard with a capo at `capoFret`.
    func strings(capoFret: Int) -> [InstrumentString] {
        guard capoFret != 0 else { return strings }
        return strings.map { $0.transposed(by: capoFret) }
    }

    func frequencyRange(
        capoFret: Int,
        referencePitch: Double = NoteMath.defaultReferencePitch
    ) -> ClosedRange<Double>? {
        let frequencies = strings(capoFret: capoFret)
            .map { $0.frequency(referencePitch: referencePitch) }
            .filter { $0 > 0 }
        guard let lowest = frequencies.min(), let highest = frequencies.max() else { return nil }
        return lowest...highest
    }

    /// Highest fret a capo can reasonably sit at.
    static let maximumCapoFret = 12
}
