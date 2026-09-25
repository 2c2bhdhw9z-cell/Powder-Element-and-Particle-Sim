import CrucibleCore
import SwiftUI

/// A small picture of one of the shapes a body can be drawn as.
///
/// Used in the picker, so the choice is made by looking rather than by reading ten words. It exists at
/// all because the real shapes are drawn by the graphics card and a button cannot show one.
///
/// ## The one honest caveat
///
/// This is a second drawing of the same ten shapes, and two drawings of one thing is how they drift.
/// The reference implementation this project took the shapes from has exactly that problem: its two
/// graphics paths disagree about which way up a triangle and a heart go, and one of them rounds off the
/// corners of its squares. So these are kept as plain as possible and make no attempt to reproduce the
/// shader's edge softening — they are labels for a choice, and the engine's own tests are what settle
/// what each shape actually is.
struct ShapeSwatch: View {
    let shape: ParticleShape

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let box = CGRect(
                x: (geometry.size.width - size) / 2,
                y: (geometry.size.height - size) / 2,
                width: size,
                height: size
            )
            Path { path in
                Self.draw(shape, in: box, into: &path)
            }
            .fill(style: FillStyle(eoFill: true))
        }
    }

    /// Builds one shape's outline inside a box.
    ///
    /// The maths here is the same *description* as `ParticleShape`, laid out as line segments rather
    /// than as a measurement, because that is what a vector drawing wants. Where a shape is round it is
    /// drawn round; where it has corners they are placed at the fractions of the box the engine's
    /// version puts them at.
    private static func draw(_ shape: ParticleShape, in box: CGRect, into path: inout Path) {
        let centre = CGPoint(x: box.midX, y: box.midY)
        let radius = box.width / 2

        /// A point at a fraction of the way across and up the box, matching the engine's coordinates:
        /// minus one to one, with y upward.
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: centre.x + radius * x, y: centre.y - radius * y)
        }

        switch shape {
        case .circle:
            path.addEllipse(in: box)

        case .square:
            path.addRect(box)

        case .ring:
            // Two circles, drawn with the even-odd rule so the inner one becomes a hole. Radii seven
            // tenths plus and minus the band's own half-width, as the engine has it.
            path.addEllipse(in: box)
            let hole = box.insetBy(dx: radius * 0.55, dy: radius * 0.55)
            path.addEllipse(in: hole)

        case .diamond:
            path.move(to: at(0, 1))
            path.addLine(to: at(1, 0))
            path.addLine(to: at(0, -1))
            path.addLine(to: at(-1, 0))
            path.closeSubpath()

        case .triangle:
            // Apex at the top, base cut off a little above the bottom of the box — the engine stops it
            // at seventy-two hundredths, and the half-width there is eighty-five hundredths.
            path.move(to: at(0, 1))
            path.addLine(to: at(0.85, -0.72))
            path.addLine(to: at(-0.85, -0.72))
            path.closeSubpath()

        case .star:
            // Ten alternating corners, a point at the top, valleys at thirty-eight hundredths.
            for step in 0 ..< 10 {
                let angle = Double.pi / 2 + Double(step) * Double.pi / 5
                let reach = step.isMultiple(of: 2) ? 1.0 : 0.38
                let point = at(cos(angle) * reach, sin(angle) * reach)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

        case .hexagon:
            // Points up and down, flats left and right, fitting the box exactly.
            for step in 0 ..< 6 {
                let angle = Double.pi / 2 + Double(step) * Double.pi / 3
                let point = at(cos(angle) * 0.866_025_403_784_438_6, sin(angle))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()

        case .plus:
            // Arms a little under a third of the box thick, which is one over three and a fifth.
            let arm = 1.0 / 3.2
            path.addRect(CGRect(
                x: box.minX,
                y: centre.y - radius * arm,
                width: box.width,
                height: radius * arm * 2
            ))
            path.addRect(CGRect(
                x: centre.x - radius * arm,
                y: box.minY,
                width: radius * arm * 2,
                height: box.height
            ))

        case .spark:
            // Four points with the sides curving inward. The waist sits where the engine's square-root
            // sum puts it: a quarter of the way out along each diagonal.
            let waist = 0.25
            path.move(to: at(0, 1))
            path.addQuadCurve(to: at(1, 0), control: at(waist, waist))
            path.addQuadCurve(to: at(0, -1), control: at(waist, -waist))
            path.addQuadCurve(to: at(-1, 0), control: at(-waist, -waist))
            path.addQuadCurve(to: at(0, 1), control: at(-waist, waist))
            path.closeSubpath()

        case .heart:
            // Two lobes over a point. The notch between them and the point at the bottom are what make
            // it a heart rather than a rounded blob, so both are drawn definitely.
            path.move(to: at(0, -0.95))
            path.addCurve(to: at(-0.95, 0.35), control1: at(-0.55, -0.45), control2: at(-0.95, -0.05))
            path.addCurve(to: at(0, 0.45), control1: at(-0.95, 0.8), control2: at(-0.35, 0.85))
            path.addCurve(to: at(0.95, 0.35), control1: at(0.35, 0.85), control2: at(0.95, 0.8))
            path.addCurve(to: at(0, -0.95), control1: at(0.95, -0.05), control2: at(0.55, -0.45))
            path.closeSubpath()
        }
    }
}
