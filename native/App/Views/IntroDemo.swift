import Foundation
import SwiftUI

/// A short, polished moving demonstration for one page of the first-run introduction.
///
/// These are deliberately drawn motion graphics, not a tiny simulation stretched until every cell is a block. The
/// earlier version was technically running the real engines, but it looked like rough programmer art and often showed
/// a vertical pipe or a meaningless pile instead of explaining the words above it. Each scene here has one job and
/// reads like a short video: a clear gesture, reaction or state change, looped without controls.
struct IntroDemo: View {
    let page: Int

    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 1.25 : timeline.date.timeIntervalSince(started)
            Canvas { context, size in
                IntroDemoFrame(page: page, seconds: elapsed).draw(in: &context, size: size)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.025, green: 0.03, blue: 0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

private struct IntroDemoFrame {
    let page: Int
    let seconds: Double

    private let gold = Color(red: 0.96, green: 0.73, blue: 0.22)
    private let paleGold = Color(red: 1.0, green: 0.88, blue: 0.46)
    private let blue = Color(red: 0.20, green: 0.63, blue: 0.96)
    private let cyan = Color(red: 0.40, green: 0.92, blue: 0.94)
    private let orange = Color(red: 1.0, green: 0.28, blue: 0.08)
    private let green = Color(red: 0.28, green: 0.88, blue: 0.40)
    private let violet = Color(red: 0.63, green: 0.44, blue: 1.0)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 20, size.height > 20 else { return }
        drawBackdrop(in: &context, size: size)

        // Every scene is composed on one known stage and scaled uniformly into whatever height the welcome screen can
        // offer. The previous fixed coordinates overlapped at the declared 160-point minimum. Uniform fitting keeps
        // circles round, labels apart and every timed state inside the frame on compact phones and split iPad views.
        let stageSize = CGSize(width: 400, height: 280)
        let scale = min(size.width / stageSize.width, size.height / stageSize.height)
        var stage = context
        stage.translateBy(
            x: (size.width - stageSize.width * scale) / 2,
            y: (size.height - stageSize.height * scale) / 2
        )
        stage.scaleBy(x: scale, y: scale)
        switch page {
        case 0: drawTwoWorlds(in: &stage, size: stageSize)
        case 1: drawPainting(in: &stage, size: stageSize)
        case 2: drawReactions(in: &stage, size: stageSize)
        case 3: drawTilt(in: &stage, size: stageSize)
        case 4: drawUndo(in: &stage, size: stageSize)
        default: drawSimple(in: &stage, size: stageSize)
        }
        drawPlayingMark(in: &stage, size: stageSize)
    }

    // MARK: - Common pieces

    private func drawBackdrop(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.065),
                    Color(red: 0.015, green: 0.018, blue: 0.026),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )

        // Barely-there depth, not a graph-paper grid.
        let gap: CGFloat = 44
        var lines = Path()
        var x: CGFloat = gap
        while x < size.width {
            lines.move(to: CGPoint(x: x, y: 0))
            lines.addLine(to: CGPoint(x: x, y: size.height))
            x += gap
        }
        var y: CGFloat = gap
        while y < size.height {
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: size.width, y: y))
            y += gap
        }
        context.stroke(lines, with: .color(Color.white.opacity(0.025)), lineWidth: 0.5)
    }

    private func drawPlayingMark(in context: inout GraphicsContext, size: CGSize) {
        let pulse = 0.55 + 0.45 * wave(seconds * 2.2)
        context.fill(
            Path(ellipseIn: CGRect(x: 14, y: 14, width: 6, height: 6)),
            with: .color(Color(red: 0.45, green: 1.0, blue: 0.68).opacity(pulse))
        )
        drawText(
            "DEMO",
            at: CGPoint(x: 25, y: 11),
            anchor: .topLeading,
            size: 9,
            colour: Color.white.opacity(0.48),
            in: &context
        )
    }

    private func drawText(
        _ text: String,
        at point: CGPoint,
        anchor: UnitPoint = .center,
        size: CGFloat = 11,
        weight: Font.Weight = .medium,
        colour: Color = .white,
        in context: inout GraphicsContext
    ) {
        context.draw(
            Text(text)
                .font(.system(size: size, weight: weight, design: .rounded))
                .foregroundStyle(colour),
            at: point,
            anchor: anchor
        )
    }

    private func dot(_ point: CGPoint, radius: CGFloat, colour: Color, in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(colour)
        )
    }

    private func capsule(_ rect: CGRect, colour: Color, in context: inout GraphicsContext) {
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(colour))
    }

    private func wave(_ value: Double) -> Double {
        (sin(value) + 1) * 0.5
    }

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    /// Stable pseudo-randomness for texture: no state, no popping between frames.
    private func noise(_ index: Int, salt: Double = 0) -> Double {
        fraction(sin(Double(index) * 12.9898 + salt * 78.233) * 43_758.5453)
    }

    private func loop(_ duration: Double) -> Double {
        let value = seconds.truncatingRemainder(dividingBy: duration)
        return value < 0 ? value + duration : value
    }

    // MARK: - Two worlds

    private func drawTwoWorlds(in context: inout GraphicsContext, size: CGSize) {
        let margin: CGFloat = 14
        let top: CGFloat = 35
        let bottom = size.height - 14
        let middle = size.width * 0.5
        let left = CGRect(x: margin, y: top, width: middle - margin - 4, height: bottom - top)
        let right = CGRect(x: middle + 4, y: top, width: size.width - middle - margin - 4, height: bottom - top)

        var divider = Path()
        divider.move(to: CGPoint(x: middle, y: top))
        divider.addLine(to: CGPoint(x: middle, y: bottom))
        context.stroke(divider, with: .color(Color.white.opacity(0.13)), lineWidth: 1)
        drawText("POWDER", at: CGPoint(x: left.midX, y: top + 4), size: 9, colour: .white.opacity(0.45), in: &context)
        drawText("FIELD", at: CGPoint(x: right.midX, y: top + 4), size: 9, colour: .white.opacity(0.45), in: &context)

        var leftLayer = context
        leftLayer.clip(to: Path(left))
        let fall = loop(2.4) / 2.4
        let floorY = bottom - 16

        // A shaped mound rather than a staircase of enlarged cells.
        var mound = Path()
        mound.move(to: CGPoint(x: left.minX + 8, y: floorY))
        mound.addCurve(
            to: CGPoint(x: left.maxX - 8, y: floorY),
            control1: CGPoint(x: left.minX + left.width * 0.32, y: floorY - 48),
            control2: CGPoint(x: left.minX + left.width * 0.68, y: floorY - 30)
        )
        mound.addLine(to: CGPoint(x: left.maxX - 8, y: bottom))
        mound.addLine(to: CGPoint(x: left.minX + 8, y: bottom))
        mound.closeSubpath()
        leftLayer.fill(
            mound,
            with: .linearGradient(
                Gradient(colors: [paleGold, gold.opacity(0.72)]),
                startPoint: CGPoint(x: 0, y: floorY - 50),
                endPoint: CGPoint(x: 0, y: bottom)
            )
        )

        // Two natural, broken streams: sand and water.
        for index in 0 ..< 34 {
            let phase = fraction(Double(index) / 34 + fall)
            let x = left.minX + left.width * 0.34 + CGFloat(noise(index, salt: 1) - 0.5) * 15
            let y = top + 25 + CGFloat(phase) * (floorY - top - 34)
            dot(CGPoint(x: x, y: y), radius: 1.4 + CGFloat(noise(index, salt: 2)), colour: paleGold, in: &leftLayer)
        }
        for index in 0 ..< 25 {
            let phase = fraction(Double(index) / 25 + fall * 0.82)
            let x = left.minX + left.width * 0.70 + CGFloat(noise(index, salt: 3) - 0.5) * 12
            let y = top + 32 + CGFloat(phase) * (floorY - top - 40)
            dot(CGPoint(x: x, y: y), radius: 1.3, colour: blue.opacity(0.86), in: &leftLayer)
        }
        var water = Path()
        water.move(to: CGPoint(x: left.midX + 5, y: floorY + 1))
        for step in 0 ... 24 {
            let along = CGFloat(step) / 24
            let x = left.midX + 5 + along * (left.maxX - left.midX - 12)
            let y = floorY - 5 + CGFloat(sin(Double(along) * 13 + seconds * 2.4)) * 2
            water.addLine(to: CGPoint(x: x, y: y))
        }
        water.addLine(to: CGPoint(x: left.maxX - 7, y: bottom))
        water.addLine(to: CGPoint(x: left.midX + 5, y: bottom))
        water.closeSubpath()
        leftLayer.fill(water, with: .color(blue.opacity(0.72)))

        // A clean orbital field, with three readable paths and bodies moving along them.
        var rightLayer = context
        rightLayer.clip(to: Path(right))
        let core = CGPoint(x: right.midX, y: right.midY + 8)
        for orbit in 0 ..< 4 {
            let width = right.width * (0.28 + CGFloat(orbit) * 0.15)
            let height = right.height * (0.16 + CGFloat(orbit) * 0.08)
            let box = CGRect(x: core.x - width / 2, y: core.y - height / 2, width: width, height: height)
            rightLayer.stroke(Path(ellipseIn: box), with: .color(cyan.opacity(0.10 + Double(orbit) * 0.025)), lineWidth: 0.8)
            for body in 0 ..< 5 {
                let angle = seconds * (0.55 + Double(orbit) * 0.13) + Double(body) / 5 * .pi * 2 + Double(orbit)
                let point = CGPoint(
                    x: core.x + CGFloat(cos(angle)) * width / 2,
                    y: core.y + CGFloat(sin(angle)) * height / 2
                )
                let colours = [cyan, violet, green, blue]
                dot(point, radius: body == 0 ? 2.3 : 1.4, colour: colours[orbit].opacity(0.9), in: &rightLayer)
            }
        }
        let corePulse = CGFloat(8 + wave(seconds * 3) * 3)
        dot(core, radius: corePulse * 1.8, colour: orange.opacity(0.10), in: &rightLayer)
        dot(core, radius: corePulse, colour: Color(red: 1, green: 0.22, blue: 0.36), in: &rightLayer)
    }

    // MARK: - Drag to paint

    private func drawPainting(in context: inout GraphicsContext, size: CGSize) {
        let cycle = loop(5)
        let drawing = min(1, cycle / 2.8)
        let fading = max(0, min(1, (5 - cycle) / 0.7))
        let rect = CGRect(x: 18, y: 38, width: size.width - 36, height: size.height - 54)

        // A deliberate S-stroke. The travelled part is a solid line with individual grains drifting below it.
        var stroke = Path()
        let samples = max(2, Int(drawing * 80))
        var cursor = CGPoint(x: rect.minX + 20, y: rect.midY)
        for index in 0 ..< samples {
            let along = CGFloat(index) / 79
            let x = rect.minX + 20 + along * (rect.width - 40)
            let y = rect.midY + CGFloat(sin(Double(along) * .pi * 2.2)) * rect.height * 0.23
            cursor = CGPoint(x: x, y: y)
            if index == 0 { stroke.move(to: cursor) } else { stroke.addLine(to: cursor) }
        }
        context.stroke(
            stroke,
            with: .linearGradient(
                Gradient(colors: [paleGold.opacity(fading), gold.opacity(fading)]),
                startPoint: CGPoint(x: rect.minX, y: 0),
                endPoint: CGPoint(x: rect.maxX, y: 0)
            ),
            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
        )

        for index in 0 ..< Int(drawing * 46) {
            let along = CGFloat(index) / 45
            let born = Double(along) * 2.8
            let age = max(0, cycle - born)
            let baseY = rect.midY + CGFloat(sin(Double(along) * .pi * 2.2)) * rect.height * 0.23
            let point = CGPoint(
                x: rect.minX + 20 + along * (rect.width - 40) + CGFloat(noise(index, salt: 5) - 0.5) * 8,
                y: min(rect.maxY - 5, baseY + CGFloat(age * age) * 5 + CGFloat(noise(index, salt: 6) * 7))
            )
            dot(point, radius: 1.4 + CGFloat(noise(index, salt: 7)), colour: paleGold.opacity(fading * 0.9), in: &context)
        }

        if cycle < 3.5 {
            dot(cursor, radius: 22, colour: Color.white.opacity(0.08), in: &context)
            dot(cursor, radius: 15, colour: Color.white.opacity(0.12), in: &context)
            context.stroke(
                Path(ellipseIn: CGRect(x: cursor.x - 16, y: cursor.y - 16, width: 32, height: 32)),
                with: .color(Color.white.opacity(0.75)),
                lineWidth: 1.5
            )
        }
        drawText("DRAG", at: CGPoint(x: rect.midX, y: rect.maxY - 10), size: 9, colour: .white.opacity(0.34), in: &context)
    }

    // MARK: - Materials react

    private func drawReactions(in context: inout GraphicsContext, size: CGSize) {
        let duration = 3.4
        let scene = Int(floor(seconds / duration)) % 3
        let local = loop(duration)
        let progress = min(1, local / 2.4)
        let area = CGRect(x: 20, y: 42, width: size.width - 40, height: size.height - 68)

        let titles = ["WATER PUTS FIRE OUT", "LAVA MELTS SAND", "PLANTS DRINK WATER"]
        drawText(titles[scene], at: CGPoint(x: area.midX, y: area.minY), size: 10, weight: .semibold,
                 colour: .white.opacity(0.60), in: &context)

        switch scene {
        case 0: drawWaterAndFire(progress: progress, in: &context, area: area)
        case 1: drawLavaAndSand(progress: progress, in: &context, area: area)
        default: drawPlantAndWater(progress: progress, in: &context, area: area)
        }

        let dotsY = area.maxY + 12
        for index in 0 ..< 3 {
            dot(CGPoint(x: area.midX + CGFloat(index - 1) * 16, y: dotsY), radius: index == scene ? 3.5 : 2,
                colour: index == scene ? .white.opacity(0.85) : .white.opacity(0.22), in: &context)
        }
    }

    private func drawWaterAndFire(progress: Double, in context: inout GraphicsContext, area: CGRect) {
        let ground = area.maxY - 12
        var floor = Path()
        floor.move(to: CGPoint(x: area.minX + 20, y: ground))
        floor.addLine(to: CGPoint(x: area.maxX - 20, y: ground))
        context.stroke(floor, with: .color(Color.white.opacity(0.16)), lineWidth: 2)

        let fire = max(0.08, 1 - progress * 1.2)
        for index in 0 ..< 9 {
            let x = area.midX + CGFloat(index - 4) * 9
            let height = CGFloat(25 + noise(index, salt: 11) * 38) * CGFloat(fire)
            var flame = Path()
            flame.move(to: CGPoint(x: x - 7, y: ground))
            flame.addCurve(
                to: CGPoint(x: x + 7, y: ground),
                control1: CGPoint(x: x - 4, y: ground - height * 0.35),
                control2: CGPoint(x: x + CGFloat(sin(seconds * 4 + Double(index))) * 7, y: ground - height)
            )
            flame.closeSubpath()
            context.fill(flame, with: .color((index % 2 == 0 ? orange : gold).opacity(0.85)))
        }

        for index in 0 ..< 18 {
            let phase = fraction(Double(index) / 18 + progress * 1.3)
            let point = CGPoint(
                x: area.midX + CGFloat(noise(index, salt: 12) - 0.5) * 115,
                y: area.minY + 30 + CGFloat(phase) * (ground - area.minY - 55)
            )
            dot(point, radius: 2.7, colour: blue.opacity(0.9), in: &context)
        }
        if progress > 0.45 {
            for index in 0 ..< 8 {
                let age = (progress - 0.45) * 1.8 + Double(index) * 0.08
                let x = area.midX + CGFloat(index - 4) * 12 + CGFloat(sin(seconds + Double(index))) * 4
                let y = ground - 35 - CGFloat(age * 55)
                dot(CGPoint(x: x, y: y), radius: 3.2 + CGFloat(age * 2), colour: .white.opacity(max(0, 0.22 - age * 0.12)), in: &context)
            }
        }
    }

    private func drawLavaAndSand(progress: Double, in context: inout GraphicsContext, area: CGRect) {
        let ground = area.maxY - 16
        let meeting = area.midX
        // Sand mound.
        var sand = Path()
        sand.move(to: CGPoint(x: area.minX + 20, y: ground))
        sand.addCurve(
            to: CGPoint(x: meeting + 25, y: ground),
            control1: CGPoint(x: area.minX + 80, y: ground - 8),
            control2: CGPoint(x: meeting - 45, y: ground - 75)
        )
        sand.closeSubpath()
        context.fill(sand, with: .color(gold.opacity(0.82)))

        // Lava approaches from the right as one coherent glowing flow.
        let front = area.maxX - 25 - CGFloat(progress) * (area.width * 0.43)
        var lava = Path()
        lava.move(to: CGPoint(x: area.maxX - 18, y: ground))
        lava.addLine(to: CGPoint(x: front, y: ground))
        lava.addCurve(
            to: CGPoint(x: area.maxX - 18, y: ground - 30),
            control1: CGPoint(x: front + 25, y: ground - 32 - CGFloat(wave(seconds * 3)) * 8),
            control2: CGPoint(x: area.maxX - 70, y: ground - 26)
        )
        lava.closeSubpath()
        context.fill(lava, with: .color(orange.opacity(0.88)))
        context.stroke(lava, with: .color(gold.opacity(0.7)), lineWidth: 2)

        if progress > 0.56 {
            let glassShare = min(1, (progress - 0.56) / 0.35)
            let glass = CGRect(x: meeting - 25, y: ground - 45, width: 50, height: 45)
            context.fill(
                Path(roundedRect: glass, cornerRadius: 12),
                with: .linearGradient(
                    Gradient(colors: [cyan.opacity(0.68 * glassShare), blue.opacity(0.20 * glassShare)]),
                    startPoint: glass.origin,
                    endPoint: CGPoint(x: glass.maxX, y: glass.maxY)
                )
            )
            drawText("GLASS", at: CGPoint(x: glass.midX, y: glass.midY), size: 9, weight: .bold,
                     colour: .white.opacity(glassShare * 0.85), in: &context)
        }
    }

    private func drawPlantAndWater(progress: Double, in context: inout GraphicsContext, area: CGRect) {
        let ground = area.maxY - 14
        let height = CGFloat(36 + progress * 105)
        var soil = Path()
        soil.move(to: CGPoint(x: area.minX + 20, y: ground))
        soil.addCurve(
            to: CGPoint(x: area.maxX - 20, y: ground),
            control1: CGPoint(x: area.midX - 70, y: ground - 38),
            control2: CGPoint(x: area.midX + 70, y: ground - 38)
        )
        soil.closeSubpath()
        context.fill(soil, with: .color(gold.opacity(0.52)))

        let stemX = area.midX
        var stem = Path()
        stem.move(to: CGPoint(x: stemX, y: ground - 18))
        stem.addCurve(
            to: CGPoint(x: stemX + 5, y: ground - height),
            control1: CGPoint(x: stemX - 10, y: ground - height * 0.35),
            control2: CGPoint(x: stemX + 14, y: ground - height * 0.7)
        )
        context.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        for index in 0 ..< 4 {
            let along = CGFloat(index + 1) / 5
            let y = ground - 18 - height * along
            let side: CGFloat = index % 2 == 0 ? -1 : 1
            let leaf = CGRect(x: stemX + side * 18 - 12, y: y - 8, width: 24, height: 14)
            context.fill(Path(ellipseIn: leaf), with: .color(green.opacity(0.55 + Double(index) * 0.1)))
        }
        for index in 0 ..< 14 {
            let phase = fraction(Double(index) / 14 + progress * 1.3)
            let x = area.midX + 80 + CGFloat(noise(index, salt: 16) - 0.5) * 35
            let y = area.minY + 30 + CGFloat(phase) * (ground - area.minY - 45)
            dot(CGPoint(x: x, y: y), radius: 2.5, colour: blue.opacity(0.9), in: &context)
        }
        // A fine root line visibly reaching toward the water.
        var root = Path()
        root.move(to: CGPoint(x: stemX, y: ground - 5))
        root.addCurve(
            to: CGPoint(x: stemX + 76 * CGFloat(progress), y: ground - 4),
            control1: CGPoint(x: stemX + 20, y: ground + 8),
            control2: CGPoint(x: stemX + 50, y: ground - 14)
        )
        context.stroke(root, with: .color(green.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Tilt

    private func drawTilt(in context: inout GraphicsContext, size: CGSize) {
        let angle = sin(seconds * 0.8) * 0.23
        let phoneSize = CGSize(width: min(230, size.width * 0.55), height: min(280, size.height * 0.72))
        var phone = context
        phone.translateBy(x: size.width / 2, y: size.height / 2 + 10)
        phone.rotate(by: .radians(angle))
        let body = CGRect(x: -phoneSize.width / 2, y: -phoneSize.height / 2, width: phoneSize.width, height: phoneSize.height)
        phone.fill(Path(roundedRect: body, cornerRadius: 30), with: .color(Color.white.opacity(0.055)))
        phone.stroke(Path(roundedRect: body, cornerRadius: 30), with: .color(Color.white.opacity(0.55)), lineWidth: 2)
        let screen = body.insetBy(dx: 10, dy: 12)
        phone.stroke(Path(roundedRect: screen, cornerRadius: 22), with: .color(Color.white.opacity(0.10)), lineWidth: 1)

        var contents = phone
        contents.clip(to: Path(roundedRect: screen, cornerRadius: 22))
        let lean = CGFloat(sin(seconds * 0.8))
        for index in 0 ..< 88 {
            let x0 = CGFloat(noise(index, salt: 20)) * screen.width + screen.minX
            let depth = CGFloat(noise(index, salt: 21)) * 58
            // Grains gather at the low edge as the phone tips.
            let shifted = x0 + lean * 58
            let x = min(screen.maxX - 3, max(screen.minX + 3, shifted))
            let slope = -lean * (x - screen.midX) * 0.42
            let y = screen.maxY - 10 - depth + slope
            dot(CGPoint(x: x, y: y), radius: 2.0 + CGFloat(noise(index, salt: 22)), colour: paleGold.opacity(0.86), in: &contents)
        }
        // Gravity belongs to the room, not the phone. Draw this in the unrotated canvas so it stays screen-down while
        // the device turns around it.
        let arrowX = size.width / 2
        let arrowTop = size.height / 2 - 25
        let arrowBottom = size.height / 2 + 16
        var arrow = Path()
        arrow.move(to: CGPoint(x: arrowX, y: arrowTop))
        arrow.addLine(to: CGPoint(x: arrowX, y: arrowBottom))
        arrow.move(to: CGPoint(x: arrowX - 7, y: arrowBottom - 8))
        arrow.addLine(to: CGPoint(x: arrowX, y: arrowBottom))
        arrow.addLine(to: CGPoint(x: arrowX + 7, y: arrowBottom - 8))
        context.stroke(arrow, with: .color(blue.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        drawText("TIP THE PHONE", at: CGPoint(x: size.width / 2, y: size.height - 18), size: 9,
                 colour: .white.opacity(0.38), in: &context)
    }

    // MARK: - Undo and rewind

    private func drawUndo(in context: inout GraphicsContext, size: CGSize) {
        let cycle = loop(6)
        let amount: Double
        if cycle < 2.2 { amount = cycle / 2.2 }
        else if cycle < 3.0 { amount = 1 }
        else if cycle < 4.2 { amount = 1 - (cycle - 3.0) / 1.2 }
        else { amount = 0 }
        let world = CGRect(x: 18, y: 50, width: size.width - 36, height: size.height - 100)
        context.fill(Path(roundedRect: world, cornerRadius: 16), with: .color(Color.black.opacity(0.20)))
        context.stroke(Path(roundedRect: world, cornerRadius: 16), with: .color(Color.white.opacity(0.09)), lineWidth: 1)

        // A recognizable spiral stroke appears, then visibly unwinds.
        var stroke = Path()
        let points = max(1, Int(amount * 100))
        for index in 0 ..< points {
            let along = CGFloat(index) / 99
            let angle = Double(along) * .pi * 4
            let radius = along * min(world.width, world.height) * 0.34
            let point = CGPoint(
                x: world.midX + CGFloat(cos(angle)) * radius,
                y: world.midY + CGFloat(sin(angle)) * radius * 0.62
            )
            if index == 0 { stroke.move(to: point) } else { stroke.addLine(to: point) }
        }
        context.stroke(
            stroke,
            with: .linearGradient(
                Gradient(colors: [cyan, violet, Color(red: 1, green: 0.25, blue: 0.55)]),
                startPoint: CGPoint(x: world.minX, y: world.midY),
                endPoint: CGPoint(x: world.maxX, y: world.midY)
            ),
            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
        )

        let undoing = cycle >= 3.0 && cycle < 4.2
        let undo = CGRect(x: 18, y: 12, width: 88, height: 28)
        capsule(undo, colour: undoing ? Color.white.opacity(0.88) : Color.white.opacity(0.10), in: &context)
        drawText("↶  UNDO", at: CGPoint(x: undo.midX, y: undo.midY), size: 10, weight: .semibold,
                 colour: undoing ? Color.black.opacity(0.85) : Color.white.opacity(0.62), in: &context)

        let track = CGRect(x: 128, y: 23, width: size.width - 150, height: 4)
        capsule(track, colour: Color.white.opacity(0.12), in: &context)
        let rewind = cycle < 3 ? 1.0 : max(0, 1 - (cycle - 3) / 1.2)
        capsule(CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(rewind), height: track.height),
                colour: blue.opacity(0.8), in: &context)
        dot(CGPoint(x: track.minX + track.width * CGFloat(rewind), y: track.midY), radius: 7,
            colour: Color.white.opacity(0.9), in: &context)
        drawText("REWIND", at: CGPoint(x: track.midX, y: 36), size: 8, colour: .white.opacity(0.30), in: &context)
    }

    // MARK: - Simple mode

    private func drawSimple(in context: inout GraphicsContext, size: CGSize) {
        let names = ["Sand", "Water", "Stone", "Lava", "Plant"]
        let colours = [gold, blue, Color(red: 0.58, green: 0.60, blue: 0.66), orange, green]
        let active = Int(floor(seconds / 1.7)) % names.count
        let local = loop(1.7) / 1.7
        var x: CGFloat = 15
        for index in names.indices {
            let width = CGFloat(names[index].count) * 6.3 + 18
            let rect = CGRect(x: x, y: 36, width: width, height: 25)
            capsule(rect, colour: index == active ? Color.white.opacity(0.88) : Color.white.opacity(0.09), in: &context)
            drawText(names[index], at: CGPoint(x: rect.midX, y: rect.midY), size: 9.5, weight: .semibold,
                     colour: index == active ? Color.black.opacity(0.86) : Color.white.opacity(0.58), in: &context)
            x += width + 5
        }

        let area = CGRect(x: 18, y: 75, width: size.width - 36, height: size.height - 112)
        let cursor = CGPoint(
            x: area.minX + 35 + CGFloat(local) * (area.width - 70),
            y: area.midY - 30 + CGFloat(sin(local * .pi * 2)) * 24
        )
        switch active {
        case 0:
            for index in 0 ..< 42 {
                let phase = fraction(Double(index) / 42 + local)
                let point = CGPoint(x: cursor.x + CGFloat(noise(index, salt: 31) - 0.5) * 18,
                                    y: area.minY + CGFloat(phase) * area.height)
                dot(point, radius: 1.8, colour: paleGold.opacity(0.9), in: &context)
            }
        case 1:
            var wavePath = Path()
            wavePath.move(to: CGPoint(x: area.minX, y: area.maxY - 35))
            for index in 0 ... 40 {
                let along = CGFloat(index) / 40
                wavePath.addLine(to: CGPoint(
                    x: area.minX + along * area.width,
                    y: area.maxY - 35 + CGFloat(sin(Double(along) * 12 + seconds * 3)) * 5
                ))
            }
            wavePath.addLine(to: CGPoint(x: area.maxX, y: area.maxY))
            wavePath.addLine(to: CGPoint(x: area.minX, y: area.maxY))
            wavePath.closeSubpath()
            context.fill(wavePath, with: .color(blue.opacity(0.72)))
        case 2:
            for row in 0 ..< 4 {
                for column in 0 ..< 6 {
                    let rect = CGRect(x: area.midX - 90 + CGFloat(column) * 31 + CGFloat(row % 2) * 8,
                                      y: area.maxY - 30 - CGFloat(row) * 25, width: 27, height: 20)
                    context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(colours[2].opacity(0.72)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.10)), lineWidth: 0.7)
                }
            }
        case 3:
            for index in 0 ..< 12 {
                let angle = Double(index) / 12 * .pi * 2 + seconds * 0.25
                let radius = 28 + CGFloat(noise(index, salt: 34) * 50)
                let point = CGPoint(x: area.midX + CGFloat(cos(angle)) * radius,
                                    y: area.midY + CGFloat(sin(angle)) * radius * 0.55)
                dot(point, radius: 9 + CGFloat(noise(index, salt: 35) * 7), colour: orange.opacity(0.70), in: &context)
                dot(point, radius: 3, colour: paleGold.opacity(0.85), in: &context)
            }
        default:
            let stem = CGRect(x: area.midX - 3, y: area.maxY - 125, width: 6, height: 100)
            context.fill(Path(roundedRect: stem, cornerRadius: 3), with: .color(green.opacity(0.85)))
            for index in 0 ..< 5 {
                let side: CGFloat = index % 2 == 0 ? -1 : 1
                let leaf = CGRect(x: area.midX + side * 22 - 14,
                                  y: area.maxY - 110 + CGFloat(index) * 16, width: 28, height: 15)
                context.fill(Path(ellipseIn: leaf), with: .color(green.opacity(0.55 + Double(index) * 0.08)))
            }
        }

        // A consistent fingertip says these are choices somebody is making, not unrelated animations.
        dot(cursor, radius: 18, colour: Color.white.opacity(0.07), in: &context)
        context.stroke(Path(ellipseIn: CGRect(x: cursor.x - 14, y: cursor.y - 14, width: 28, height: 28)),
                       with: .color(Color.white.opacity(0.68)), lineWidth: 1.3)
        drawText("FIVE MATERIALS  •  THREE BRUSHES", at: CGPoint(x: area.midX, y: size.height - 17), size: 8.5,
                 weight: .semibold, colour: .white.opacity(0.34), in: &context)
    }
}
