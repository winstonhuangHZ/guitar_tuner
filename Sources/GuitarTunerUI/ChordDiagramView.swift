import GuitarTunerKit
import SwiftUI

/// Fretboard diagram for one shape.
///
/// Strings run left (lowest) to right (highest) and the dots show which fret to press.
/// `stringVerdicts` colours each string while the practice mode listens, which is the
/// feedback a learner actually needs: not "the chord is wrong" but "this string is".
public struct ChordDiagramView: View {
    public var voicing: ChordVoicing
    /// Optional per-string feedback, indexed like `voicing.frets`.
    public var stringVerdicts: [ChordEvaluation.Verdict?]
    public var showsFretNumbers: Bool

    public init(
        voicing: ChordVoicing,
        stringVerdicts: [ChordEvaluation.Verdict?] = [],
        showsFretNumbers: Bool = false
    ) {
        self.voicing = voicing
        self.stringVerdicts = stringVerdicts
        self.showsFretNumbers = showsFretNumbers
    }

    private let topInset: CGFloat = 26
    private let labelHeight: CGFloat = 20
    private var stringCount: Int { voicing.frets.count }
    private var fretCount: Int { 5 }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: context, size: size)
            }
        }
        .aspectRatio(CGFloat(stringCount) / CGFloat(fretCount + 1) * 1.35, contentMode: .fit)
        .frame(maxWidth: 240)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let gridWidth = size.width
        let gridHeight = size.height - topInset - labelHeight
        guard gridWidth > 0, gridHeight > 0, stringCount > 1 else { return }

        let spacing = gridWidth / CGFloat(stringCount - 1)
        let fretHeight = gridHeight / CGFloat(fretCount)
        let nutY = topInset

        // Frets.
        for fret in 0...fretCount {
            let y = nutY + CGFloat(fret) * fretHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: gridWidth, y: y))
            let isNut = fret == 0 && voicing.baseFret <= 1
            context.stroke(
                line,
                with: .color(Color.black.opacity(isNut ? 0.75 : 0.22)),
                lineWidth: isNut ? 5 : 1
            )
        }

        // Strings.
        for string in 0..<stringCount {
            let x = CGFloat(string) * spacing
            var line = Path()
            line.move(to: CGPoint(x: x, y: nutY))
            line.addLine(to: CGPoint(x: x, y: nutY + gridHeight))
            context.stroke(line, with: .color(Color.black.opacity(0.35)), lineWidth: 1.5)
        }

        // Base fret marker, e.g. "3fr".
        if voicing.baseFret > 1 {
            let text = Text("\(voicing.baseFret)fr")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.5))
            context.draw(text, at: CGPoint(x: gridWidth + 14, y: nutY + fretHeight / 2), anchor: .center)
        }

        // Dots, open and muted markers.
        for (index, fret) in voicing.frets.enumerated() {
            let x = CGFloat(index) * spacing
            let verdict = index < stringVerdicts.count ? stringVerdicts[index] : nil
            let tone = color(for: verdict)

            guard let fret else {
                context.draw(
                    Text("×")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45)),
                    at: CGPoint(x: x, y: nutY - 13),
                    anchor: .center
                )
                continue
            }

            if fret == 0 {
                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - 5, y: nutY - 18, width: 10, height: 10))
                context.stroke(circle, with: .color(tone), lineWidth: 1.6)
                continue
            }

            let relativeFret = fret - voicing.baseFret + 1
            let y = nutY + (CGFloat(relativeFret) - 0.5) * fretHeight
            let radius = min(spacing, fretHeight) * 0.34
            let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(tone))

            if showsFretNumbers {
                context.draw(
                    Text("\(fret)")
                        .font(.system(size: radius * 1.1, weight: .semibold, design: .rounded))
                        .foregroundStyle(TunerTheme.onAccent),
                    at: CGPoint(x: x, y: y),
                    anchor: .center
                )
            }
        }

        // String labels under the grid.
        for index in 0..<stringCount {
            let x = CGFloat(index) * spacing
            guard let note = voicing.note(forStringIndex: index) else {
                context.draw(
                    Text("—")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.black.opacity(0.3)),
                    at: CGPoint(x: x, y: size.height - labelHeight / 2),
                    anchor: .center
                )
                continue
            }
            context.draw(
                Text(note.description())
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.45)),
                at: CGPoint(x: x, y: size.height - labelHeight / 2),
                anchor: .center
            )
        }
    }

    /// Dark when there is no feedback, otherwise the same colours the tuner uses.
    private func color(for verdict: ChordEvaluation.Verdict?) -> Color {
        switch verdict {
        case .correct: TunerTheme.inTune
        case .weak: TunerTheme.sharp
        case .missing: TunerTheme.sharp
        case .unexpected: Color.black.opacity(0.65)
        case nil: Color.black.opacity(0.78)
        }
    }
}
