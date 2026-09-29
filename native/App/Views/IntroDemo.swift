import CoreGraphics
import CrucibleCore
import SwiftUI

/// A small moving picture on each page of the introduction, doing what the page says.
///
/// Not a recorded video: the real engines, tiny, running live. So it always matches what the app really does, it
/// costs nothing to ship, and a change to the physics changes the introduction with it. A ghost finger shows where a
/// touch would be.
struct IntroDemo: View {
    /// Which page: the same order as `LabIntroduction.steps`.
    let page: Int

    @State private var player: IntroDemoPlayer?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            // Worked out here, on the main thread, and handed to the canvas finished: a canvas may draw elsewhere.
            let frame = player?.frame(at: timeline.date)
            Canvas { context, size in
                frame?.draw(in: &context, size: size)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .onAppear { if player == nil { player = IntroDemoPlayer(page: page) } }
        .onDisappear { player = nil }
        .accessibilityHidden(true)
    }
}

/// Runs one page's demo. A class so the engines live between frames; only ever touched on the main thread.
@MainActor
final class IntroDemoPlayer {
    private let page: Int
    private let started = Date()
    private var lastStep = Date.distantPast
    private var moments = 0

    private var powder: PowderEngine
    private var field: ParticleEngine?
    private let history = PowderHistory(maximumSteps: 2)
    private var finger: CGPoint?
    private var undoGlow = 0.0
    private var chosen = 0

    private static let gridWidth = 96
    private static let gridHeight = 72

    init(page: Int) {
        self.page = page
        powder = PowderEngine(width: Self.gridWidth, height: Self.gridHeight, seed: 7)
        reset()
    }

    // MARK: Setting each page up

    private func reset() {
        powder = PowderEngine(width: Self.gridWidth, height: Self.gridHeight, seed: UInt32(7 + page))
        moments = 0
        finger = nil
        undoGlow = 0
        switch page {
        case 0:
            let field = ParticleEngine(width: 200, height: 150, seed: 3)
            field.spawnGalaxy(count: 260)
            self.field = field
        case 2:
            // A floor of sand, a pool of water on the left, a pool of lava on the right.
            for x in 0 ..< Self.gridWidth {
                for y in (Self.gridHeight - 8) ..< Self.gridHeight { powder.setElement(x, y, Element.sand) }
            }
            for x in 6 ..< 36 { for y in (Self.gridHeight - 14) ..< (Self.gridHeight - 8) { powder.setElement(x, y, Element.water) } }
            for x in 60 ..< 90 {
                for y in (Self.gridHeight - 13) ..< (Self.gridHeight - 8) { powder.setElement(x, y, Element.lava, temp: 1_600) }
            }
        case 3:
            for x in 20 ..< 76 { for y in 30 ..< 60 { powder.setElement(x, y, (x + y) % 3 == 0 ? Element.water : Element.sand) } }
        case 4:
            for x in 0 ..< Self.gridWidth { powder.setElement(x, Self.gridHeight - 1, Element.stone) }
            history.push(powder)
        default:
            field = nil
        }
    }

    // MARK: Each moment

    private func advance(time t: Double) {
        moments += 1
        switch page {
        case 0:
            // Sand and water pouring on the left half; the right half is the particle field.
            pour(Element.sand, atX: Self.gridWidth / 4 - 4, width: 3)
            pour(Element.water, atX: Self.gridWidth / 4 + 5, width: 3)
            if moments % 360 == 0 { reset() }
            field?.step()
        case 1:
            // A finger drawing a wave of sand, then lifting, then starting again on a clean world.
            let cycle = moments % 300
            if cycle < 150 {
                let along = Double(cycle) / 150
                let point = CGPoint(x: 0.12 + along * 0.76, y: 0.35 + sin(along * .pi * 3) * 0.12)
                finger = point
                paint(Element.sand, at: point, radius: 2)
            } else {
                finger = nil
            }
            if cycle == 299 { reset() }
        case 2:
            // Lava dropped on the sand on the left, water poured on the lava on the right.
            if moments % 500 < 200 {
                pour(Element.lava, atX: 20, width: 2, temp: 1_600)
                pour(Element.water, atX: 74, width: 2)
            }
            if moments % 500 == 499 { reset() }
        case 3:
            // Gravity swinging as a phone is tipped one way and the other.
            let angle = sin(t * 0.9) * 1.0
            powder.gravityX = sin(angle)
            powder.gravityY = cos(angle)
        case 4:
            // Pour a pile, then undo it — the world goes back to exactly how it was.
            let cycle = moments % 260
            if cycle < 150 { pour(Element.sand, atX: Self.gridWidth / 2, width: 4) }
            if cycle == 200, history.undo(powder) {
                undoGlow = 1
                history.push(powder)
            }
        default:
            // The five materials of the smaller lab, one after another from the same finger.
            let cycle = moments % 120
            if cycle == 0 { chosen = (chosen + 1) % SimpleLab.materials.count }
            if cycle < 70 {
                let along = Double(cycle) / 70
                let point = CGPoint(x: 0.15 + Double(chosen) * 0.17, y: 0.3 + along * 0.15)
                finger = point
                paint(SimpleLab.materials[chosen], at: point, radius: 2)
            } else {
                finger = nil
            }
            if moments % 1_200 == 1_199 { reset() }
        }
        powder.step()
        undoGlow = max(0, undoGlow - 0.02)
    }

    private func pour(_ id: ElementID, atX x: Int, width: Int, temp: Double? = nil) {
        guard moments % 2 == 0 else { return }
        for dx in 0 ..< width where powder.typeAt(x + dx, 1) == Element.empty {
            powder.setElement(x + dx, 1, id, temp: temp)
        }
    }

    private func paint(_ id: ElementID, at point: CGPoint, radius: Int) {
        let cx = Int(point.x * Double(Self.gridWidth))
        let cy = Int(point.y * Double(Self.gridHeight))
        for dy in -radius ... radius {
            for dx in -radius ... radius where dx * dx + dy * dy <= radius * radius {
                if powder.typeAt(cx + dx, cy + dy) == Element.empty { powder.setElement(cx + dx, cy + dy, id) }
            }
        }
    }

    // MARK: Frames

    /// Moves the demo on to this moment and says what it looks like.
    func frame(at date: Date) -> IntroDemoFrame {
        let t = date.timeIntervalSince(started)
        // Thirty moments a second whatever the screen's own rate, and never more than a few to catch up.
        if lastStep == .distantPast { lastStep = date }
        var catchUp = 0
        while date.timeIntervalSince(lastStep) >= 1.0 / 30.0, catchUp < 3 {
            advance(time: t)
            lastStep = lastStep.addingTimeInterval(1.0 / 30.0)
            catchUp += 1
        }
        if date.timeIntervalSince(lastStep) > 0.5 { lastStep = date }

        var dots: [IntroDemoFrame.Dot] = []
        var fieldSize = CGSize(width: 1, height: 1)
        if let field {
            fieldSize = CGSize(width: field.width, height: field.height)
            dots = field.particles.map { body in
                IntroDemoFrame.Dot(
                    x: body.x, y: body.y, radius: body.radius,
                    red: Double(body.color.r) / 255, green: Double(body.color.g) / 255, blue: Double(body.color.b) / 255
                )
            }
        }
        return IntroDemoFrame(
            page: page,
            image: powderImage(),
            gridSize: CGSize(width: Self.gridWidth, height: Self.gridHeight),
            dots: dots,
            fieldSize: fieldSize,
            finger: finger,
            tilt: sin(t * 0.9) * 1.0,
            undoGlow: undoGlow,
            chosen: chosen
        )
    }

    private func powderImage() -> CGImage? {
        var pixels = powder.renderToArray()
        let width = Self.gridWidth
        let height = Self.gridHeight
        guard pixels.count == width * height else { return nil }
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let bitmap = CGContext(
                      data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return nil }
            return bitmap.makeImage()
        }
    }
}

/// One finished picture of a demo, with nothing left to ask the engines.
struct IntroDemoFrame {
    struct Dot {
        var x: Double
        var y: Double
        var radius: Double
        var red: Double
        var green: Double
        var blue: Double
    }

    let page: Int
    let image: CGImage?
    let gridSize: CGSize
    let dots: [Dot]
    let fieldSize: CGSize
    let finger: CGPoint?
    let tilt: Double
    let undoGlow: Double
    let chosen: Int

    func draw(in context: inout GraphicsContext, size: CGSize) {
        if page == 0 {
            let left = CGRect(x: 0, y: 0, width: size.width / 2 - 1, height: size.height)
            let right = CGRect(x: size.width / 2 + 1, y: 0, width: size.width / 2 - 1, height: size.height)
            drawPowder(in: &context, rect: left)
            drawField(in: &context, rect: right)
            context.fill(Path(CGRect(x: size.width / 2 - 1, y: 0, width: 2, height: size.height)),
                         with: .color(Palette.borderStrong))
            label("Powder", in: &context, at: CGPoint(x: 12, y: 10))
            label("Field", in: &context, at: CGPoint(x: size.width / 2 + 12, y: 10))
            return
        }
        drawPowder(in: &context, rect: CGRect(origin: .zero, size: size))

        if let finger {
            let point = CGPoint(x: finger.x * size.width, y: finger.y * size.height)
            let ring = Path(ellipseIn: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32))
            context.fill(ring, with: .color(Color.white.opacity(0.18)))
            context.stroke(ring, with: .color(Color.white.opacity(0.7)), lineWidth: 1.5)
        }

        switch page {
        case 3:
            // A little phone, tipped the way gravity is pointing.
            var phone = context
            phone.translateBy(x: size.width - 34, y: 34)
            phone.rotate(by: .radians(-tilt))
            let body = Path(roundedRect: CGRect(x: -11, y: -19, width: 22, height: 38), cornerRadius: 5)
            phone.stroke(body, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
        case 4:
            let chip = CGRect(x: 12, y: 12, width: 78, height: 28)
            context.fill(Path(roundedRect: chip, cornerRadius: 14),
                         with: .color(Color.white.opacity(0.08 + undoGlow * 0.6)))
            context.draw(
                Text("Undo").font(.labBody(12, .semiBold)).foregroundStyle(Palette.foreground),
                at: CGPoint(x: chip.midX, y: chip.midY)
            )
        case 5:
            let names = ["Sand", "Water", "Stone", "Lava", "Plant"]
            var x = 10.0
            for (index, name) in names.enumerated() {
                let width = Double(name.count) * 7 + 16
                let chip = CGRect(x: x, y: 10, width: width, height: 24)
                context.fill(Path(roundedRect: chip, cornerRadius: 12),
                             with: .color(index == chosen ? Palette.primary : Color.white.opacity(0.1)))
                context.draw(
                    Text(name).font(.labBody(11, .medium))
                        .foregroundStyle(index == chosen ? Palette.primaryForeground : Palette.foreground),
                    at: CGPoint(x: chip.midX, y: chip.midY)
                )
                x += width + 5
            }
        default:
            break
        }
    }

    private func label(_ text: String, in context: inout GraphicsContext, at point: CGPoint) {
        context.draw(
            Text(text).font(.labBody(11, .medium)).foregroundStyle(Palette.muted),
            at: point, anchor: .topLeading
        )
    }

    private func drawPowder(in context: inout GraphicsContext, rect: CGRect) {
        guard let image, gridSize.width > 0, gridSize.height > 0 else { return }
        // Filled edge to edge, keeping the cells square: cropped rather than stretched, resting on the bottom.
        let scale = max(rect.width / gridSize.width, rect.height / gridSize.height)
        let drawn = CGSize(width: gridSize.width * scale, height: gridSize.height * scale)
        let target = CGRect(x: rect.midX - drawn.width / 2, y: rect.maxY - drawn.height, width: drawn.width, height: drawn.height)
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.draw(Image(decorative: image, scale: 1).interpolation(.none), in: target)
    }

    private func drawField(in context: inout GraphicsContext, rect: CGRect) {
        guard fieldSize.width > 0, fieldSize.height > 0 else { return }
        let scale = min(rect.width / fieldSize.width, rect.height / fieldSize.height)
        let offsetX = rect.minX + (rect.width - fieldSize.width * scale) / 2
        let offsetY = rect.minY + (rect.height - fieldSize.height * scale) / 2
        for dot in dots {
            let x = offsetX + dot.x * scale
            let y = offsetY + dot.y * scale
            guard rect.contains(CGPoint(x: x, y: y)) else { continue }
            let r = max(1.2, dot.radius * scale * 0.6)
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(Color(red: dot.red, green: dot.green, blue: dot.blue))
            )
        }
    }
}
