// Where the two chambers meet.
//
// Ported from web/src/sim/hybrid.ts.
//
// The powder grid and the particle field are separate simulations with almost nothing in common, and
// three small bridges between them are what make the pair feel like one place rather than two apps
// sharing a window:
//
//   - an explosion in the powder world throws a shower of sparks into the field;
//   - particles that have come to rest quietly turn into sand or water;
//   - and all of it can be done at once, on purpose, with a button.
//
// ## Why this is a free function rather than a method
//
// Each needs both engines, and neither engine should know the other exists. The powder grid does not
// import the particle field and never will — it is the reason both can be tested in isolation. So the
// bridges live outside both, taking each as an argument.

/// The bridges between the two chambers.
public enum Hybrid {
    // MARK: Sparks from an explosion

    /// The two colours a spark can be. Warm, because it came out of a blast.
    static let sparkColors = [
        PackedColor(r: 0xF9, g: 0x73, b: 0x16),  // orange
        PackedColor(r: 0xEA, g: 0xB3, b: 0x08),  // amber
    ]

    /// Throws sparks into the field from an explosion in the powder world.
    ///
    /// The grid position is scaled into the field's own coordinates, since the two are different
    /// sizes — usually very different, because the grid is deliberately coarser than the screen.
    ///
    /// Draws from the **field's** generator, not the grid's. The particles are what is being created,
    /// so the field is what should account for the randomness; taking it from the grid would mean an
    /// explosion consumed a different number of the grid's random numbers depending on whether the
    /// bridge was switched on, and the whole powder world would then unfold differently.
    ///
    /// - Parameters:
    ///   - gridX: where the explosion was, in grid cells.
    ///   - gridY: likewise.
    ///   - radius: the explosion's radius in cells, which decides how many sparks there are.
    public static func burst(
        fromPowder powder: PowderEngine,
        into field: ParticleEngine,
        gridX: Int,
        gridY: Int,
        radius: Int
    ) {
        // Between two dozen and a couple of hundred, so a firecracker and a nuke look different
        // without a nuke flooding the field.
        let count = min(220, max(24, Int(JS.round(Double(radius) * 4))))
        let x = (Double(gridX) / Double(max(1, powder.width))) * field.width
        let y = (Double(gridY) / Double(max(1, powder.height))) * field.height

        for _ in 0 ..< count {
            let angle = field.rng.next() * 2 * Double.pi
            let speed = 2 + field.rng.next() * 7
            _ = field.addParticle(
                x: x + (field.rng.next() - 0.5) * 10,
                y: y + (field.rng.next() - 0.5) * 10,
                velocityX: jsCos(angle) * speed,
                // Biased upward, so a blast throws things up rather than sideways in a disc.
                velocityY: jsSin(angle) * speed - 2,
                radius: 1.6 + field.rng.next(),
                color: sparkColors[field.rng.next() < 0.5 ? 0 : 1],
                lifespan: 90 + field.rng.int(below: 50)
            )
        }
    }

    // MARK: Settling

    /// The colours that settle as water rather than sand.
    ///
    /// The reference decides this by looking for a substring in a CSS colour, which is exactly as
    /// fragile as it sounds — it also catches anything that merely happens to contain those digits.
    /// Here the colours are compared properly, which is the same intent stated in a way that cannot
    /// misfire.
    static let waterColors = [
        PackedColor(r: 0x06, g: 0xB6, b: 0xD4),  // cyan
        PackedColor(r: 0x3B, g: 0x82, b: 0xF6),  // blue
    ]

    /// Whether a body should become water rather than sand.
    static func settlesAsWater(_ body: ParticleObject) -> Bool {
        settlesAsWater(body.color)
    }

    /// Whether a colour reads as water: one of the two named ones, or anything clearly blue.
    ///
    /// The two exact colours alone missed nearly every blue in the field — the waterfall's own blue, the
    /// pour's liquid, the water scene's pool — so pouring a waterfall into the powder world made sand.
    static func settlesAsWater(_ colour: PackedColor) -> Bool {
        if waterColors.contains(where: { $0.r == colour.r && $0.g == colour.g && $0.b == colour.b }) {
            return true
        }
        let r = Double(colour.r) / 255
        let g = Double(colour.g) / 255
        let b = Double(colour.b) / 255
        let high = max(r, g, b)
        let low = min(r, g, b)
        let spread = high - low
        // Blue must be the strongest channel by a clear margin, and the colour must not be nearly grey.
        guard spread > 0.2, high == b else { return false }
        let hue = 60 * (4 + (r - g) / spread)
        return hue >= 180 && hue <= 250
    }

    /// Where a place in the field lands in the grid, or nothing if it lands outside it.
    ///
    /// Worked out in floating point and checked before becoming a whole number, because a body far outside
    /// the field — or a field of no size — used to reach a conversion that cannot hold the answer, and crash.
    static func gridCell(x: Double, y: Double, field: ParticleEngine, powder: PowderEngine) -> (Int, Int)? {
        guard field.width > 0, field.height > 0 else { return nil }
        let across = JS.trunc((x / field.width) * Double(powder.width))
        let down = JS.trunc((y / field.height) * Double(powder.height))
        guard across.isFinite, down.isFinite,
              across >= 0, across < Double(powder.width), down >= 0, down < Double(powder.height)
        else { return nil }
        return (Int(across), Int(down))
    }

    /// Whether a body is the sort of thing that can settle at all.
    ///
    /// Black holes and repulsors are machinery rather than matter, and a pinned body is part of a
    /// structure someone built — turning any of them into a grain of sand would be destructive rather
    /// than charming.
    static func canSettle(_ body: ParticleObject) -> Bool {
        body.kind != .blackhole && body.kind != .repulsor && !body.isFixed
    }

    /// Quietly turns a few resting bodies into powder.
    ///
    /// Meant to be called often and do very little — a handful at a time, so a field slowly silts up
    /// into the grid rather than vanishing all at once.
    ///
    /// - Parameter limit: the most to settle in one call.
    /// - Returns: how many settled.
    @discardableResult
    public static func autoSettle(
        from field: ParticleEngine,
        into powder: PowderEngine,
        limit: Int = 8
    ) -> Int {
        // Only bodies near the bottom, so things still in flight are left alone.
        let floor = field.height - 8
        var settled = 0
        var removeIDs: Set<Int> = []

        // Backwards, so the newest settle first — a stream pouring onto a pile should build the pile
        // from the top of the stream down.
        for body in field.particles.reversed() {
            if settled >= limit { break }
            guard canSettle(body) else { continue }

            let isSlow = body.velocityX * body.velocityX + body.velocityY * body.velocityY < 6
            guard body.y >= floor, isSlow else { continue }
            guard body.x.isFinite, body.y.isFinite else { continue }

            guard let cell = gridCell(x: body.x, y: body.y, field: field, powder: powder) else { continue }
            let gridX = cell.0
            // Kept clear of the very bottom rows, which are usually the floor someone built.
            let gridY = min(powder.height - 3, cell.1)
            guard powder.isValid(gridX, gridY) else { continue }
            guard powder.type[powder.index(gridX, gridY)] == Element.empty else { continue }

            powder.setElement(gridX, gridY, settlesAsWater(body) ? Element.water : Element.sand)
            removeIDs.insert(body.id)
            settled += 1
        }

        if !removeIDs.isEmpty {
            // Through the engine's own removal, so spring endpoints follow the shift. Taking them out
            // of the array directly renumbered every body and left every spring pointing one place
            // too high.
            _ = field.removeParticles { removeIDs.contains($0.id) }
        }
        return settled
    }

    /// Dumps as much of the field into the grid as will fit, all at once.
    ///
    /// The deliberate version, behind a button. More permissive than ``autoSettle(from:into:limit:)``:
    /// anything resting settles wherever it is rather than only near the floor, so a field can be
    /// emptied into the world on purpose.
    ///
    /// - Returns: how many settled.
    @discardableResult
    public static func settleAll(from field: ParticleEngine, into powder: PowderEngine) -> Int {
        let floor = field.height - 10
        var settled = 0
        var removeIDs: Set<Int> = []

        for body in field.particles {
            guard canSettle(body) else { continue }

            // Anything slow settles wherever it is; anything fast has to be near the floor first.
            let isSlow = body.velocityX * body.velocityX + body.velocityY * body.velocityY < 9
            if body.y < floor, !isSlow { continue }
            guard body.x.isFinite, body.y.isFinite else { continue }

            guard let cell = gridCell(x: body.x, y: body.y, field: field, powder: powder) else { continue }
            let gridX = cell.0
            let gridY = cell.1
            guard powder.isValid(gridX, gridY) else { continue }
            // An occupied cell means this one stays where it is rather than being destroyed.
            guard powder.type[powder.index(gridX, gridY)] == Element.empty else { continue }

            powder.setElement(gridX, gridY, settlesAsWater(body) ? Element.water : Element.sand)
            removeIDs.insert(body.id)
            settled += 1
        }

        if !removeIDs.isEmpty {
            _ = field.removeParticles { removeIDs.contains($0.id) }
        }

        // And the crowd. This used to settle the object bodies only, so pressing "Settle into powder" on a
        // sunflower, a fire, a pour or any crowd added with the population button did nothing at all —
        // almost everything in a busy field is in the crowd.
        let swarm = field.swarm
        var settledFromCrowd = 0
        for index in 0 ..< swarm.count {
            let pair = index * 2
            let x = Double(swarm.positions[pair])
            let y = Double(swarm.positions[pair + 1])
            let vx = Double(swarm.velocities[pair])
            let vy = Double(swarm.velocities[pair + 1])
            let isSlow = vx * vx + vy * vy < 9
            if y < floor, !isSlow { continue }
            guard let cell = gridCell(x: x, y: y, field: field, powder: powder) else { continue }
            guard powder.isValid(cell.0, cell.1), powder.type[powder.index(cell.0, cell.1)] == Element.empty else {
                continue
            }
            let colour = PackedColor(packedRGBA: swarm.colors[index])
            powder.setElement(cell.0, cell.1, settlesAsWater(colour) ? Element.water : Element.sand)
            swarm.markForRemoval(at: index)
            settledFromCrowd += 1
        }
        if settledFromCrowd > 0 { swarm.removeExpired() }
        return settled + settledFromCrowd
    }
}
