/// Draw any outline and it becomes a jelly of that shape — which then drops, bounces and wobbles.
///
/// ## How an outline becomes a jelly
///
/// Bodies are laid round the outline an even step apart, and then through the inside on a honeycomb at the same
/// step. A honeycomb because it is the one even spacing in which every body has six neighbours at the same distance,
/// so the jelly is equally soft every way — laid out in rows and columns instead, it has lines of weakness along them.
/// The step is chosen from the size of what was drawn, so a small outline and a large one are made of about the same
/// number of bodies: a big jelly is a coarse one rather than one of thousands.
///
/// ## What holds it together
///
/// Not the springs alone, which was the first version, and it slumped to a puddle within a few seconds. A spring
/// here pushes back only as hard as it is squashed, so the bottom row of a jelly fifteen rows tall has to be squashed
/// by more than its own length before it holds up the fourteen rows above it — it cannot, and the whole thing
/// flattens. Stiffer springs do not help: past about a third of this engine's stiffness scale a body joined to six
/// neighbours shakes itself apart.
///
/// So each jelly remembers the shape it was drawn in, and every moment it works out where that shape would sit if it
/// were moved and turned to fit the bodies as they are now — the best fit, found exactly — and draws each body a
/// little way back toward its own place in it. That is a pull on the shape as a whole rather than on each pair, so a
/// tall jelly stands as well as a short one; it adds up to nothing overall, so it never moves the jelly anywhere by
/// itself or makes it spin; and the "little way" is what leaves it free to squash on landing, wobble, and spring
/// back. Soft springs between neighbours stay, for the jiggle and so the jelly is drawn as a mesh rather than as dots.
/// This way of holding a shape is Müller's shape matching, from the games that first did soft things well.
///
/// A flat thing only. A line on the glass has no depth to it to fill; in 3D the tool is not offered.
public struct ParticleJelly: Sendable, Hashable {
    /// The bodies it is made of, by identifier, which survives other bodies being removed where a place in the list
    /// would not.
    public var ids: [Int]
    /// Where each belongs in the shape as drawn, from the middle of it.
    public var restX: [Double]
    public var restY: [Double]
    /// How far back toward its place each body is drawn each moment, as a share of the way.
    public var firmness: Double

    public init(ids: [Int], restX: [Double], restY: [Double], firmness: Double = ParticleEngine.jellyFirmness) {
        let count = min(ids.count, restX.count, restY.count)
        self.ids = Array(ids.prefix(count))
        self.restX = Array(restX.prefix(count))
        self.restY = Array(restY.prefix(count))
        self.firmness = firmness.isFinite ? max(0, min(0.5, firmness)) : ParticleEngine.jellyFirmness
    }
}

extension ParticleEngine {
    /// How many bodies a jelly is made of, at most.
    public static let jellyMostBodies = 260
    /// How far each body is drawn back toward its place in the shape each moment. Enough to stand up; little enough
    /// to wobble.
    public static let jellyFirmness = 0.1
    /// How much of the difference between each body's speed and the whole jelly's is taken off each moment — what
    /// lets a wobble die away rather than going on for ever.
    public static let jellyInnerDrag = 0.04
    /// How many jellies there can be at once.
    public static let jellyLimit = 24

    /// The jellies in the field.
    public var jellies: [ParticleJelly] { storedJellies }
    /// The fewest square pixels an outline has to enclose to be a jelly rather than a scribble.
    public static let jellySmallestArea = 900.0

    /// The outline being drawn, for showing while the finger is still down.
    public var jellyOutline: [ParticleFingerPoint] { storedJellyOutline }

    /// Starts a new outline.
    public func beginJelly() {
        storedJellyOutline = []
    }

    /// Carries the outline on to where the finger is.
    public func extendJelly(toX x: Double, y: Double) {
        guard x.isFinite, y.isFinite, storedJellyOutline.count < 800 else { return }
        if let last = storedJellyOutline.last {
            let dx = x - last.x
            let dy = y - last.y
            guard dx * dx + dy * dy >= 9 else { return }
        }
        storedJellyOutline.append(ParticleFingerPoint(x: x, y: y))
    }

    /// Turns the outline drawn so far into a jelly, closing it from the last point back to the first.
    ///
    /// - Returns: how many bodies it was made of; nought for an outline that enclosed too little to fill.
    @discardableResult
    public func finishJelly() -> Int {
        let outline = storedJellyOutline
        storedJellyOutline = []
        return makeJelly(outline: outline)
    }

    /// Makes a jelly in the shape of an outline.
    ///
    /// - Returns: how many bodies it was made of; nought for an outline that enclosed too little to fill.
    @discardableResult
    public func makeJelly(outline: [ParticleFingerPoint]) -> Int {
        let points = outline.filter { $0.x.isFinite && $0.y.isFinite }
        guard points.count >= 3 else { return 0 }
        let area = abs(Self.enclosedArea(points))
        guard area >= Self.jellySmallestArea else { return 0 }

        // About two hundred bodies whatever the size: the step that fills the area with that many on a honeycomb,
        // allowing for the ring round the edge.
        var step = (area / (Double(Self.jellyMostBodies) * 0.7 * 0.866)).squareRoot()
        step = max(5, step)
        var nodes = Self.jellyNodes(outline: points, step: step)
        // A long thin shape has more edge for its area than the estimate allowed; coarsen until it fits.
        while nodes.count > Self.jellyMostBodies {
            step *= 1.12
            nodes = Self.jellyNodes(outline: points, step: step)
        }
        guard nodes.count >= 3 else { return 0 }
        guard bodyCount + nodes.count <= maxParticles else { return 0 }
        guard storedJellies.count < Self.jellyLimit else { return 0 }

        pushUndo()
        let first = particles.count
        var ids: [Int] = []
        ids.reserveCapacity(nodes.count)
        let hue = rng.next() * 360
        let radius = max(1.5, step * 0.3)
        for (index, node) in nodes.enumerated() {
            let id = addParticle(
                x: node.x,
                y: node.y,
                velocityX: 0,
                velocityY: 0,
                radius: radius,
                mass: 1,
                charge: 0,
                // A little lighter at the edge, so the shape reads as a solid thing with a skin.
                color: PackedColor(hue: hue, saturation: 0.75, lightness: node.edge ? 0.7 : 0.58 + Double(index % 3) * 0.02)
            )
            ids.append(id)
        }
        // The shape as drawn, from its middle.
        let middleX = nodes.reduce(0) { $0 + $1.x } / Double(nodes.count)
        let middleY = nodes.reduce(0) { $0 + $1.y } / Double(nodes.count)
        storedJellies.append(ParticleJelly(
            ids: ids,
            restX: nodes.map { $0.x - middleX },
            restY: nodes.map { $0.y - middleY }
        ))
        // Neighbours on the honeycomb are one step apart and the next ring out is the square root of three steps;
        // reaching a little past one step catches every true neighbour and none of the next ring.
        let reach = step * 1.35
        let reachSquared = reach * reach
        for a in 0 ..< nodes.count {
            for b in (a + 1) ..< nodes.count {
                let dx = nodes[b].x - nodes[a].x
                let dy = nodes[b].y - nodes[a].y
                let apart = dx * dx + dy * dy
                guard apart <= reachSquared, apart > 0 else { continue }
                // Soft: the shape is held by the jelly as a whole, and these are for the jiggle.
                addSpring(a: first + a, b: first + b, rest: apart.squareRoot(), k: 0.05)
            }
        }
        return nodes.count
    }

    /// Every jelly drawing itself back toward the shape it was drawn in.
    func stepJellies() {
        guard !storedJellies.isEmpty else { return }
        var where_: [Int: Int] = [:]
        where_.reserveCapacity(particles.count)
        for index in particles.indices { where_[particles[index].id] = index }

        var kept: [ParticleJelly] = []
        kept.reserveCapacity(storedJellies.count)
        for jelly in storedJellies {
            // The members still here, and where each belongs.
            var members: [(index: Int, restX: Double, restY: Double)] = []
            members.reserveCapacity(jelly.ids.count)
            for (at, id) in jelly.ids.enumerated() {
                guard let index = where_[id], particles[index].isFinite else { continue }
                members.append((index, jelly.restX[at], jelly.restY[at]))
            }
            // Too few left to have a shape: what remains is loose bodies, and the jelly is forgotten.
            guard members.count >= 3 else { continue }
            kept.append(jelly)

            let count = Double(members.count)
            var centreX = 0.0
            var centreY = 0.0
            var restCentreX = 0.0
            var restCentreY = 0.0
            var speedX = 0.0
            var speedY = 0.0
            for member in members {
                centreX += particles[member.index].x
                centreY += particles[member.index].y
                restCentreX += member.restX
                restCentreY += member.restY
                speedX += particles[member.index].velocityX
                speedY += particles[member.index].velocityY
            }
            centreX /= count
            centreY /= count
            restCentreX /= count
            restCentreY /= count
            speedX /= count
            speedY /= count

            // The turn that best fits the drawn shape to the bodies: in the flat, exactly the angle whose tangent is
            // the sum of the cross products over the sum of the dot products.
            var along = 0.0
            var across = 0.0
            for member in members {
                let qx = member.restX - restCentreX
                let qy = member.restY - restCentreY
                let px = particles[member.index].x - centreX
                let py = particles[member.index].y - centreY
                along += qx * px + qy * py
                across += qx * py - qy * px
            }
            let turn = JS.atan2(across, along)
            let cosTurn = jsCos(turn)
            let sinTurn = jsSin(turn)

            let firmness = jelly.firmness
            let drag = Self.jellyInnerDrag
            for member in members {
                let qx = member.restX - restCentreX
                let qy = member.restY - restCentreY
                let goalX = centreX + qx * cosTurn - qy * sinTurn
                let goalY = centreY + qx * sinTurn + qy * cosTurn
                let index = member.index
                guard !particles[index].isFixed else { continue }
                particles[index].velocityX += (goalX - particles[index].x) * firmness
                    - (particles[index].velocityX - speedX) * drag
                particles[index].velocityY += (goalY - particles[index].y) * firmness
                    - (particles[index].velocityY - speedY) * drag
            }
        }
        if kept.count != storedJellies.count { storedJellies = kept }
    }

    /// The area an outline encloses, closing it from its last point back to its first. Negative for an outline
    /// drawn the other way round.
    static func enclosedArea(_ points: [ParticleFingerPoint]) -> Double {
        var twice = 0.0
        for index in points.indices {
            let here = points[index]
            let next = points[(index + 1) % points.count]
            twice += here.x * next.y - next.x * here.y
        }
        return twice * 0.5
    }

    /// Whether a place is inside an outline.
    static func encloses(_ points: [ParticleFingerPoint], x: Double, y: Double) -> Bool {
        var inside = false
        var previous = points.count - 1
        for index in points.indices {
            let a = points[index]
            let b = points[previous]
            if (a.y > y) != (b.y > y) {
                let crossing = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
                if x < crossing { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    /// The bodies of a jelly: round the edge at an even step, then through the inside on a honeycomb.
    static func jellyNodes(outline points: [ParticleFingerPoint], step: Double) -> [(x: Double, y: Double, edge: Bool)] {
        var nodes: [(x: Double, y: Double, edge: Bool)] = []

        // Round the edge, an even step apart however unevenly the finger moved.
        var carried = 0.0
        for index in points.indices {
            let from = points[index]
            let to = points[(index + 1) % points.count]
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            var along = carried
            while along < length {
                let share = along / length
                nodes.append((from.x + dx * share, from.y + dy * share, true))
                along += step
            }
            carried = along - length
        }

        // Through the inside, keeping clear of the edge so no two bodies start squashed together.
        var left = Double.infinity
        var right = -Double.infinity
        var top = Double.infinity
        var bottom = -Double.infinity
        for point in points {
            left = min(left, point.x)
            right = max(right, point.x)
            top = min(top, point.y)
            bottom = max(bottom, point.y)
        }
        let rowStep = step * 0.866_025_403_784_438_6
        let clearance = step * 0.7
        let clearanceSquared = clearance * clearance
        let edgeCount = nodes.count
        var row = 0
        var y = top + rowStep * 0.5
        while y < bottom {
            var x = left + (row.isMultiple(of: 2) ? step * 0.5 : step)
            while x < right {
                if encloses(points, x: x, y: y) {
                    var clear = true
                    for edge in 0 ..< edgeCount {
                        let dx = nodes[edge].x - x
                        let dy = nodes[edge].y - y
                        if dx * dx + dy * dy < clearanceSquared {
                            clear = false
                            break
                        }
                    }
                    if clear { nodes.append((x, y, false)) }
                }
                x += step
            }
            y += rowStep
            row += 1
        }
        return nodes
    }
}
