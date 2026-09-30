import SwiftUI

enum IllustrationKind {
    case readings, medicines, symptoms, conversation
}

/// Original decorative artwork. Give the view an explicit frame at the call site.
struct HarbourIllustration: View {
    var kind: IllustrationKind
    var animated: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private var shouldFloat: Bool {
        animated && kind == .conversation && !reduceMotion
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 200)
            var board = IllustrationBoard(context: context, dark: colorScheme == .dark)
            board.context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 200 * scale) / 2)
            board.context.scaleBy(x: scale, y: scale)
            switch kind {
            case .readings: board.readings()
            case .medicines: board.medicines()
            case .symptoms: board.symptoms()
            case .conversation: board.conversation()
            }
        }
        .offset(y: shouldFloat && floating ? -3 : 0)
        .animation(shouldFloat ? .easeInOut(duration: 3.4).repeatForever(autoreverses: true) : nil, value: floating)
        .onAppear { floating = shouldFloat }
        .onChange(of: shouldFloat) { _, enabled in floating = enabled }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct IllustrationBoard {
    var context: GraphicsContext
    let dark: Bool
    private let cobalt = Color(red: 0.15, green: 0.30, blue: 0.86)
    private let blue = Color(red: 0.44, green: 0.65, blue: 0.98)
    private let deepBlue = Color(red: 0.09, green: 0.17, blue: 0.50)
    private let coral = Color(red: 0.94, green: 0.40, blue: 0.31)
    private let darkCoral = Color(red: 0.70, green: 0.23, blue: 0.19)
    private let ochre = Color(red: 0.90, green: 0.66, blue: 0.24)
    private let darkOchre = Color(red: 0.64, green: 0.43, blue: 0.15)
    private let cream = Color(red: 0.99, green: 0.95, blue: 0.85)
    private let ink = Color(red: 0.18, green: 0.20, blue: 0.23)
    private var pale: Color {
        dark ? Color(red: 0.29, green: 0.34, blue: 0.44) : Color(red: 0.83, green: 0.88, blue: 0.99)
    }
    private var shadow: Color { ink.opacity(dark ? 0.28 : 0.12) }

    private func fill(_ path: Path, _ color: Color, lifted: Bool = false) {
        var layer = context
        if lifted { layer.addFilter(.shadow(color: shadow, radius: 7, x: 0, y: 7)) }
        layer.fill(path, with: .color(color))
    }

    private func stroke(_ path: Path, _ color: Color, width: CGFloat, dash: [CGFloat] = []) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height))
    }

    private func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func sparkle(at center: CGPoint, size: CGFloat, color: Color) {
        let path = Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y - size))
            path.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size), control: center)
        }
        fill(path, color)
    }

    func readings() {
        fill(ellipse(37, 162, 166, 18), shadow)
        fill(ellipse(49, 33, 144, 144), pale)
        fill(ellipse(70, 54, 103, 103), dark ? ink : cream)

        // A solid offset rim gives the torus its depth without a gradient.
        stroke(ellipse(54, 43, 139, 131), deepBlue, width: 21)
        stroke(ellipse(51, 35, 139, 131), cobalt, width: 21)
        let upperArc = Path { path in
            path.move(to: CGPoint(x: 69, y: 70))
            path.addCurve(to: CGPoint(x: 151, y: 46), control1: CGPoint(x: 84, y: 40), control2: CGPoint(x: 119, y: 32))
        }
        stroke(upperArc, blue, width: 4)

        fill(ellipse(154, 16, 45, 45), darkCoral, lifted: true)
        fill(ellipse(151, 11, 45, 45), coral)
        stroke(Path { path in
            path.move(to: CGPoint(x: 162, y: 22))
            path.addQuadCurve(to: CGPoint(x: 177, y: 17), control: CGPoint(x: 168, y: 15))
        }, cream.opacity(0.70), width: 3)

        let pulse = line([
            CGPoint(x: 26, y: 107), CGPoint(x: 65, y: 107),
            CGPoint(x: 80, y: 92), CGPoint(x: 96, y: 129),
            CGPoint(x: 116, y: 72), CGPoint(x: 137, y: 112),
            CGPoint(x: 153, y: 100), CGPoint(x: 210, y: 100)
        ])
        var lower = context
        lower.translateBy(x: 0, y: 4)
        lower.stroke(pulse, with: .color(darkOchre), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
        stroke(pulse, ochre, width: 11)
        fill(ellipse(202, 92, 16, 16), cream, lifted: true)
        fill(ellipse(207, 97, 6, 6), ochre)
        sparkle(at: CGPoint(x: 29, y: 48), size: 10, color: coral)
        fill(ellipse(208, 145, 7, 7), blue)
        fill(ellipse(27, 139, 5, 5), ochre)
    }

    func medicines() {
        fill(ellipse(43, 166, 160, 15), shadow)
        fill(ellipse(124, 38, 81, 81), pale)
        stroke(ellipse(137, 48, 57, 57), blue, width: 2)
        fill(ellipse(155, 66, 21, 21), dark ? ink : cream)

        capsule(center: CGPoint(x: 85, y: 100), angle: -38, length: 118, width: 46, first: coral, second: cream, rim: darkCoral)
        capsule(center: CGPoint(x: 153, y: 127), angle: 36, length: 111, width: 42, first: cobalt, second: ochre, rim: deepBlue)

        // A small tablet has a visible edge, score line, and reflected light.
        fill(ellipse(60, 145, 45, 25), darkOchre, lifted: true)
        fill(ellipse(60, 140, 45, 25), ochre)
        stroke(line([CGPoint(x: 71, y: 142), CGPoint(x: 91, y: 161)]), darkOchre.opacity(0.8), width: 2)
        stroke(Path { path in
            path.move(to: CGPoint(x: 66, y: 150))
            path.addQuadCurve(to: CGPoint(x: 76, y: 145), control: CGPoint(x: 68, y: 146))
        }, cream.opacity(0.7), width: 2)
        sparkle(at: CGPoint(x: 48, y: 44), size: 9, color: cobalt)
        sparkle(at: CGPoint(x: 206, y: 137), size: 8, color: coral)
        fill(ellipse(202, 45, 6, 6), ochre)
        fill(ellipse(31, 119, 6, 6), blue)
    }

    private func capsule(center: CGPoint, angle: Double, length: CGFloat, width: CGFloat, first: Color, second: Color, rim: Color) {
        var pill = self
        pill.context.translateBy(x: center.x, y: center.y)
        pill.context.rotate(by: .degrees(angle))
        let shape = rounded(-length / 2, -width / 2, length, width, radius: width / 2)
        var edge = pill.context
        edge.translateBy(x: 1, y: 5)
        edge.addFilter(.shadow(color: shadow, radius: 5, x: 0, y: 4))
        edge.fill(shape, with: .color(rim))
        pill.fill(shape, first)
        var half = pill.context
        half.clip(to: shape)
        half.fill(Path(CGRect(x: 0, y: -width / 2, width: length / 2, height: width)), with: .color(second))
        pill.stroke(line([CGPoint(x: 0, y: -width / 2 + 2), CGPoint(x: 0, y: width / 2 - 2)]), rim.opacity(0.3), width: 1.2)
        pill.stroke(line([CGPoint(x: -length / 2 + 20, y: -width / 2 + 9), CGPoint(x: -8, y: -width / 2 + 9)]), cream.opacity(0.65), width: 3)
        pill.stroke(line([CGPoint(x: 9, y: width / 2 - 5), CGPoint(x: length / 2 - 20, y: width / 2 - 5)]), rim.opacity(0.13), width: 3)
    }

    func symptoms() {
        fill(ellipse(40, 165, 167, 15), shadow)
        fill(ellipse(24, 48, 125, 125), pale)
        var book = self
        book.context.translateBy(x: 106, y: 97)
        book.context.rotate(by: .degrees(-9))
        book.fill(rounded(-55, -68, 103, 141, radius: 8), deepBlue, lifted: true)
        book.fill(rounded(-55, -73, 103, 141, radius: 8), cobalt)
        book.fill(rounded(-44, -68, 90, 132, radius: 5), darkOchre)
        book.fill(rounded(-44, -71, 90, 130, radius: 5), cream)
        book.fill(rounded(-55, -73, 13, 141, radius: 5), blue)
        for index in 0..<6 {
            let y = CGFloat(index) * 20 - 56
            book.stroke(ellipse(-59, y, 17, 8), deepBlue, width: 3)
            book.stroke(Path { path in
                path.move(to: CGPoint(x: -57, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: -44, y: y + 2), control: CGPoint(x: -51, y: y - 3))
            }, blue, width: 2)
        }
        for (index, width) in [CGFloat(45), 54, 38].enumerated() {
            book.stroke(line([CGPoint(x: -25, y: CGFloat(index) * 12 - 34), CGPoint(x: -25 + width, y: CGFloat(index) * 12 - 34)]), ochre.opacity(0.65), width: 3)
        }
        let fold = Path { path in
            path.move(to: CGPoint(x: 28, y: 59))
            path.addLine(to: CGPoint(x: 46, y: 41))
            path.addLine(to: CGPoint(x: 28, y: 41))
            path.closeSubpath()
        }
        book.fill(fold, ochre)

        var bandage = self
        bandage.context.translateBy(x: 153, y: 122)
        bandage.context.rotate(by: .degrees(31))
        bandage.fill(rounded(-57, -22, 118, 48, radius: 23), darkCoral, lifted: true)
        bandage.fill(rounded(-60, -27, 118, 48, radius: 23), coral)
        bandage.fill(rounded(-20, -24, 38, 42, radius: 8), cream)
        bandage.fill(rounded(-16, -20, 30, 34, radius: 6), Color(red: 0.97, green: 0.85, blue: 0.70))
        for x in [CGFloat(-45), -33, 31, 43] {
            for y in [CGFloat(-12), 0, 12] { bandage.fill(ellipse(x - 1.3, y - 1.3, 2.6, 2.6), darkCoral.opacity(0.65)) }
        }
        sparkle(at: CGPoint(x: 188, y: 42), size: 12, color: ochre)
        fill(ellipse(207, 80, 6, 6), coral)
        fill(ellipse(29, 143, 7, 7), cobalt)
    }

    func conversation() {
        // The orbit passes behind and in front of the mark, giving spatial depth.
        var orbit = self
        orbit.context.translateBy(x: 119, y: 103)
        orbit.context.rotate(by: .degrees(-24))
        orbit.stroke(ellipse(-99, -43, 198, 86), pale, width: 2)
        fill(ellipse(59, 166, 132, 13), shadow)
        fill(ellipse(55, 35, 133, 133), pale.opacity(dark ? 0.65 : 0.7))
        var mark = self
        mark.context.translateBy(x: 120, y: 101)
        mark.context.rotate(by: .degrees(-12))
        for x in [CGFloat(-49), 6] {
            for y in [CGFloat(-49), 6] {
                mark.fill(rounded(x + 2, y + 6, 43, 43, radius: 12), deepBlue, lifted: true)
                mark.fill(rounded(x, y, 43, 43, radius: 12), cobalt)
                mark.stroke(line([CGPoint(x: x + 10, y: y + 7), CGPoint(x: x + 31, y: y + 7)]), blue, width: 2.5)
            }
        }
        bubble(at: CGPoint(x: 182, y: 48), angle: 10, color: coral, edge: darkCoral, dots: cream)
        bubble(at: CGPoint(x: 47, y: 137), angle: -12, color: ochre, edge: darkOchre, dots: ink)
        let foregroundOrbit = Path { path in
            path.move(to: CGPoint(x: 64, y: 161))
            path.addCurve(to: CGPoint(x: 215, y: 82), control1: CGPoint(x: 133, y: 164), control2: CGPoint(x: 218, y: 109))
        }
        stroke(foregroundOrbit, blue, width: 2)
        fill(ellipse(199, 112, 12, 12), cream, lifted: true)
        fill(ellipse(202, 115, 6, 6), cobalt)
        sparkle(at: CGPoint(x: 39, y: 55), size: 9, color: blue)
        fill(ellipse(145, 17, 5, 5), ochre)
        fill(ellipse(184, 170, 7, 7), coral)
    }

    private func bubble(at center: CGPoint, angle: Double, color: Color, edge: Color, dots: Color) {
        var bubble = self
        bubble.context.translateBy(x: center.x, y: center.y)
        bubble.context.rotate(by: .degrees(angle))
        let shape = Path { path in
            path.move(to: CGPoint(x: -11, y: -19))
            path.addLine(to: CGPoint(x: 11, y: -19))
            path.addQuadCurve(to: CGPoint(x: 27, y: -3), control: CGPoint(x: 27, y: -19))
            path.addLine(to: CGPoint(x: 27, y: 3))
            path.addQuadCurve(to: CGPoint(x: 11, y: 19), control: CGPoint(x: 27, y: 19))
            path.addLine(to: CGPoint(x: 1, y: 19))
            path.addQuadCurve(to: CGPoint(x: -18, y: 29), control: CGPoint(x: -6, y: 27))
            path.addLine(to: CGPoint(x: -13, y: 18))
            path.addQuadCurve(to: CGPoint(x: -27, y: 3), control: CGPoint(x: -27, y: 18))
            path.addLine(to: CGPoint(x: -27, y: -3))
            path.addQuadCurve(to: CGPoint(x: -11, y: -19), control: CGPoint(x: -27, y: -19))
            path.closeSubpath()
        }
        var lower = bubble.context
        lower.translateBy(x: 1, y: 4)
        lower.addFilter(.shadow(color: shadow, radius: 4, x: 0, y: 3))
        lower.fill(shape, with: .color(edge))
        bubble.fill(shape, color)
        for x in [CGFloat(-12), 0, 12] { bubble.fill(ellipse(x - 2.5, -3, 5, 5), dots) }
    }
}
