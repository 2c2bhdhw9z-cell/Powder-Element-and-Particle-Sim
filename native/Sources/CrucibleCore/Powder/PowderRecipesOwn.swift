/// Scenes this app has of its own, beyond the thirteen it shares with the website.
///
/// ## Why they are a separate list
///
/// The thirteen in ``powderRecipes`` are compared cell for cell with the website's, and the day's world is chosen
/// by counting through that list — so adding to it would change which world everybody gets on a given day, and
/// break the comparison, for scenes the website has never had. These are shown beside them and are otherwise
/// entirely separate.
public let ownPowderRecipes: [PowderRecipe] = [
    PowderRecipe(id: "hourglass", name: "Hourglass") { e, random in seedHourglass(e, &random) },
]

/// Every scene, the shared ones first. For finding one by name.
public var allPowderRecipes: [PowderRecipe] { powderRecipes + ownPowderRecipes }

// MARK: - Hourglass

/// The glass of an hourglass fitted to a world: where it is and how wide it is at each row.
///
/// Shared by the scene and its tests, so the tests check the glass the scene actually builds.
///
/// ## Why the neck is two grains wide, exactly
///
/// Sand here moves one cell a moment, and a grain cannot fall into a cell that another left in the same moment. So a
/// single column of falling sand carries at most one grain every other moment, however much is waiting above it.
/// What reaches the neck is the grain at the foot of each side's slope, sliding in sideways.
///
/// With a neck of one column, both sides compete for the same cell — and they do not take turns. That cell comes free
/// on alternate moments, always the same ones, and the rows are swept left to right and right to left on alternate
/// moments too, so the same side is always looked at first and always wins. One side drained completely while the
/// other sat untouched on its glass. A wider neck did the same thing less obviously: in its first version, of five,
/// one side emptied and the other was left as a wedge leaning on the glass, running out a grain at a time for minutes.
///
/// Two columns gives each side a column of its own. Neither ever has to compete, so the two sides run down together
/// and the surface sinks into the funnel a real hourglass shows. The glass is centred on the line between those two
/// columns, so it is exactly symmetric — and symmetric top to bottom about the middle of the world as well, so turning
/// the world over puts the glass back exactly where it was.
public struct HourglassShape: Sendable {
    /// The first column right of the middle line. The glass's inside at a row is `centreX - half ..< centreX + half`.
    public let centreX: Int
    /// The neck's upper row. The same as ``lowerNeckY`` in a world an odd number of rows tall.
    public let upperNeckY: Int
    /// The neck's lower row.
    public let lowerNeckY: Int
    /// The first row inside the glass, just under the top plate.
    public let topY: Int
    /// The last row inside the glass, just above the bottom plate.
    public let bottomY: Int
    /// Half the width of each bulb at its widest.
    public let bulbHalfWidth: Int
    /// How thick the glass is.
    public let wall: Int
    /// How thick the plates top and bottom are.
    public let plate: Int

    /// Half the neck's width: one column each side of the middle line.
    public static let neckHalfWidth = 1

    /// How far the glass may widen for each row it climbs away from the neck.
    ///
    /// Less than one. Sand here comes to rest on any slope of one cell across for each cell down, or gentler, so glass
    /// that gentle near the neck holds sand up on itself instead of letting it run to the neck.
    public static let widening = 0.7

    /// The tallest the glass is drawn, in cells.
    ///
    /// It pours about one grain a moment whatever its size, so a glass as tall as a finely detailed world would take
    /// many minutes to run through. Capped, it takes about a minute and a half at the usual detail, and sits in the
    /// middle of the screen rather than filling it.
    public static let tallest = 300

    /// The shape that fits a world, or nothing for a world too small to hold one.
    public init?(width: Int, height: Int) {
        // Tall and slim, whatever shape the world is: on a wide world it would otherwise become a squat drum, so the
        // width is limited by the height too.
        let glassHeight = min(Self.tallest, Int((Double(height) * 0.84).rounded(.down)))
        let bulbHalf = min(Int((Double(width) * 0.36).rounded(.down)), glassHeight * 22 / 100)
        guard glassHeight >= 24, bulbHalf >= 6 else { return nil }
        centreX = width / 2
        upperNeckY = (height - 1) / 2
        lowerNeckY = height / 2
        plate = max(2, glassHeight / 60)
        wall = max(1, bulbHalf / 30)
        bulbHalfWidth = bulbHalf
        let reach = glassHeight / 2 - plate
        topY = upperNeckY - reach
        bottomY = lowerNeckY + reach
    }

    /// Half the inside width at one row, or nothing outside the glass.
    public func halfWidth(atRow y: Int) -> Int? {
        guard y >= topY, y <= bottomY else { return nil }
        let reach = Double(upperNeckY - topY)
        let rows = Double(y < upperNeckY ? upperNeckY - y : (y > lowerNeckY ? y - lowerNeckY : 0))
        guard reach > 0 else { return Self.neckHalfWidth }
        let along = rows / reach
        // A cone out of the neck, never gentler than ``widening``, easing into straight sides — the shape of the glass
        // rather than of two cones point to point. The last few rows round in towards the plates.
        let cone = Double(Self.neckHalfWidth) + rows * Self.widening
        let rounding = along > 0.9 ? 1 - (along - 0.9) * 2.5 : 1
        let bulb = Double(bulbHalfWidth) * rounding
        // The smaller of the two with the corner between them rounded off. Always at or inside both, so the cone's
        // limit on how gently the glass may slope still holds through the shoulder.
        let softness = Double(bulbHalfWidth) * 0.35
        let difference = cone - bulb
        let half = (cone + bulb - (difference * difference + softness * softness).squareRoot()) * 0.5
        return max(Self.neckHalfWidth, Int(half.rounded(.down)))
    }

    /// Whether a cell is inside the glass.
    public func contains(_ x: Int, _ y: Int) -> Bool {
        guard let half = halfWidth(atRow: y) else { return false }
        return x >= centreX - half && x < centreX + half
    }

    /// How many grains the glass is given: enough for about a minute and a half, never more than it can comfortably
    /// hold.
    public var sandWanted: Int {
        var inside = 0
        for y in topY ... upperNeckY { inside += 2 * (halfWidth(atRow: y) ?? 0) }
        return min(5400, inside * 6 / 10)
    }
}

/// An hourglass of glass between two wooden plates, its upper bulb holding sand that pours through the neck.
///
/// Turn the world upside down to start it again: the sand that has run through is then at the top.
private func seedHourglass(_ e: PowderEngine, _ random: inout Mulberry32) {
    guard let shape = HourglassShape(width: e.width, height: e.height) else {
        // Too small for the glass to have an inside. A heap of sand is the honest version of an hourglass that size.
        for y in (e.height * 2 / 3) ..< e.height {
            for x in 0 ..< e.width { e.setElement(x, y, Element.sand) }
        }
        return
    }
    let cx = shape.centreX

    // The glass. Each row's wall reaches out as far as the rows beside it, so where the sides slope steeply near
    // the neck there is no diagonal gap for a grain to slip through.
    for y in shape.topY ... shape.bottomY {
        guard let inside = shape.halfWidth(atRow: y) else { continue }
        let above = shape.halfWidth(atRow: y - 1) ?? inside
        let below = shape.halfWidth(atRow: y + 1) ?? inside
        let thickness = max(inside, above, below) + shape.wall - inside
        for step in 1 ... thickness {
            e.setElement(cx - inside - step, y, Element.glass)
            e.setElement(cx + inside - 1 + step, y, Element.glass)
        }
    }

    // The plates, and the posts that hold them apart.
    let plateHalf = shape.bulbHalfWidth + shape.wall + 3
    for row in 0 ..< shape.plate {
        for x in (cx - plateHalf) ..< (cx + plateHalf) {
            e.setElement(x, shape.topY - 1 - row, Element.wood)
            e.setElement(x, shape.bottomY + 1 + row, Element.wood)
        }
    }
    let post = max(1, shape.plate / 2)
    for y in shape.topY ... shape.bottomY {
        for thickness in 0 ..< post {
            e.setElement(cx - plateHalf + thickness, y, Element.wood)
            e.setElement(cx + plateHalf - 1 - thickness, y, Element.wood)
        }
    }

    // The sand, resting in the bottom of the upper bulb as it would the moment after the glass was turned over, with
    // empty glass above it: laid from the neck upwards until there is enough. Its top rows are left slightly uneven,
    // as poured sand is — and so that no two hourglasses are identical.
    var laid = 0
    let wanted = shape.sandWanted
    var y = shape.upperNeckY - 1
    while y >= shape.topY, laid < wanted {
        guard let inside = shape.halfWidth(atRow: y) else { break }
        let nearlyThere = wanted - laid < inside * 4
        for x in (cx - inside) ..< (cx + inside) {
            if nearlyThere, random.next() < 0.35 { continue }
            e.setElement(x, y, Element.sand)
            laid += 1
        }
        y -= 1
    }
}
