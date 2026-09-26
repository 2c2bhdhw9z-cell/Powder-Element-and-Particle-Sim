/// The field in 3D: the switch, and the box the bodies live in.
///
/// ## What changes when it is on
///
/// Every body gains a depth — how far into the screen it is — and moves through it, so the world is a box
/// rather than a sheet. Gravity still points down. The walls of the box are its front and back as well as its
/// sides, and they bounce, wrap round or swallow bodies exactly as the sides do. Everything that pushes or
/// pulls works in all three directions: black holes, charges, springs, the liquid, the pull between bodies,
/// the wind, flocking, collisions and every tool a finger can hold.
///
/// Walls somebody draws and wind somebody paints are drawn on the screen, so they reach all the way through
/// the box: a wall is a panel from the front to the back along the line that was drawn.
///
/// ## What turning it on or off does to what is showing
///
/// An arrangement is rebuilt in its other form — the galaxy becomes a disc lying level in the box, the
/// sierpinski triangle becomes the pyramid made of pyramids, the tornado a real funnel — because that is what
/// somebody switching to 3D is asking to see. Anything else is lifted into the box or laid flat again. Either
/// way it is one step of undo, which brings back exactly what was there, flat or not.
extension ParticleEngine {
    /// Whether the field is in 3D.
    public var depthEnabled: Bool { storedDepthEnabled }

    /// How deep the box is, as a share of the world's shorter side. One is a box as deep as the screen is
    /// wide.
    public var depthRatio: Double {
        get { storedDepthRatio }
        set { storedDepthRatio = Self.usableDepthRatio(newValue) }
    }

    /// The shallowest and deepest the box can be made.
    public static let depthRatioRange: ClosedRange<Double> = 0.25 ... 2

    static func usableDepthRatio(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(depthRatioRange.upperBound, max(depthRatioRange.lowerBound, value))
    }

    /// How deep the world is, in its pixels. Nought on a flat field.
    ///
    /// Worked out from the world's own size, so zooming out — which grows the world — gives more room in
    /// depth as well as across.
    public var worldDepth: Double {
        guard storedDepthEnabled else { return 0 }
        return max(1, min(width, height)) * storedDepthRatio
    }

    /// Half of ``worldDepth``: the box runs from this far in front of the middle to this far behind it.
    var halfDepth: Double { worldDepth * 0.5 }

    /// Turns 3D on or off.
    ///
    /// - Returns: whether anything changed.
    @discardableResult
    public func setDepthEnabled(_ enabled: Bool) -> Bool {
        guard enabled != storedDepthEnabled else { return false }
        // One step of undo for the whole change, taken while the field is still in its old form.
        pushUndo()
        storedDepthEnabled = enabled
        undoSuppressed = true
        defer { undoSuppressed = false }

        if let id = storedArrangement, id != "text", ParticleArrangement.named(id)?.kind == .scene {
            // Something that only exists in depth has no flat form to go back to, so turning 3D off with one
            // showing clears it rather than drawing it flattened into a scribble.
            if !enabled, ParticleArrangement.named(id)?.depth == .only {
                clear()
                return true
            }
            loadArrangement(id)
        } else if enabled {
            liftIntoDepth()
        } else {
            flattenDepth()
        }
        return true
    }

    /// Spreads what is in the field through the box, for a field that was flat and has nothing to rebuild.
    ///
    /// Loose bodies go to random depths through the middle half of the box and drift a little, so a crowd
    /// visibly fills out into it. A body holding a place in a shape keeps it — a word or a shape stays a flat
    /// sign hanging in the middle of the box, which can then be looked at from the side.
    func liftIntoDepth() {
        let spread = halfDepth * 0.5
        for index in 0 ..< swarm.count where swarm.home(at: index) == nil {
            swarm.setDepth((rng.next() * 2 - 1) * spread, velocity: (rng.next() - 0.5) * 0.6, at: index)
        }
        for index in particles.indices where !particles[index].isFixed && particles[index].kind == .standard {
            particles[index].z = (rng.next() * 2 - 1) * spread
            particles[index].velocityZ = (rng.next() - 0.5) * 0.6
            particles[index].trail.removeAll()
        }
    }

    /// Lays everything back on the middle of the box, for a field going flat with nothing to rebuild.
    func flattenDepth() {
        swarm.flattenDepth()
        for index in particles.indices {
            particles[index].z = 0
            particles[index].velocityZ = 0
            particles[index].originZ = 0
            particles[index].trail.removeAll()
        }
    }
}
