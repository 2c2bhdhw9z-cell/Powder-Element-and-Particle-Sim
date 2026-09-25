/// The built-in scenes: a volcano, an ant farm, a reactor, and ten more.
///
/// ## What was wrong with the old ones
///
/// Every scene was rectangles and circles at fixed fractions of the world. That gives a
/// dead-flat slab of ground with a perfectly straight top edge, seven identical trees at
/// exactly equal spacing, and reactor walls two cells thick with corners like a
/// spreadsheet. Forest was a green rectangle with seven lollipops on it. They read as a
/// diagram of a scene rather than a place — and the giveaway is that all thirteen were
/// *identical every time*, because the layout was computed purely from the width and the
/// height.
///
/// ## What they are now
///
/// Every scene takes the random source and uses it, so each is laid out differently while
/// staying reproducible from a seed. Three things do most of the work:
///
///   - **Ground is a surface, not a slab.** ``surface(_:_:_:_:_:)`` gives a height for every
///     column, interpolated smoothly between a few random control points, and ``layer`` fills
///     bands that follow it. So there is grass over dirt over stone, and the top of it rolls.
///   - **Nothing repeats evenly.** Trees, fuel rods, pebbles and drifts step along by random
///     intervals and vary in size.
///   - **Edges are rough.** ``blob`` and ``vein`` wander, so a pond has a shoreline and a lava
///     flow has a course.
///
/// ## The order of random draws is behaviour
///
/// This file and `web/src/sim/powder-recipes.ts` must consume the stream in exactly the same
/// order or the golden comparison fails — which is precisely what makes it worth having.
/// Anything added here goes into that file too, in the same order, and the fixture is
/// regenerated.
///
/// ## The basin, and why the repair tools must not touch it
///
/// Every scene starts with ``basin(_:)``: bedrock across the bottom two rows and up the two
/// outer columns, but only from 22% of the way down. The top of the world and the upper fifth
/// of the side walls are deliberately open, so things can be poured in and gas can escape.
/// That is why sealing the perimeter is a manual action and not part of the automatic repair
/// pass — running it over a scene destroys the shape the scene is.
///
/// ## Undo
///
/// Applying a recipe resets the grid but takes no snapshot; recording one is the caller's
/// business, because the engine does not own the undo record.

/// One scene.
public struct PowderRecipe: Sendable {
    public let id: String
    public let name: String
    /// Lays the scene out. Every scene consults the generator now.
    let build: @Sendable (PowderEngine, inout Mulberry32) -> Void

    /// Wipes the world and lays this scene out in it.
    ///
    /// - Parameter random: Every scene uses it. Pass a generator seeded from something shared
    ///   — the date, say — when every player must get the same world.
    public func apply(to engine: PowderEngine, random: inout Mulberry32) {
        engine.resetGrid()
        build(engine, &random)
    }

    /// Convenience for a caller that does not care which variation it gets.
    public func apply(to engine: PowderEngine) {
        var generator = Mulberry32(seed: 0)
        apply(to: engine, random: &generator)
    }
}

// MARK: - Drawing helpers

private func put(_ e: PowderEngine, _ x: Int, _ y: Int, _ id: ElementID, _ temp: Double? = nil) {
    // Out-of-range coordinates are dropped rather than clamped: a scene laid out in
    // fractions can legitimately compute a position off the edge on a very small world,
    // and folding it back inside would pile everything against the wall instead.
    guard e.isValid(x, y) else { return }
    e.setElement(x, y, id, temp: temp)
}

private func fillRect(
    _ e: PowderEngine,
    _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
    _ id: ElementID, _ temp: Double? = nil
) {
    for y in min(y0, y1) ... max(y0, y1) {
        for x in min(x0, x1) ... max(x0, x1) {
            put(e, x, y, id, temp)
        }
    }
}

private func fillCircle(
    _ e: PowderEngine,
    _ cx: Int, _ cy: Int, _ r: Int,
    _ id: ElementID, _ temp: Double? = nil
) {
    guard r >= 0 else { return }
    let rSquared = r * r
    for y in -r ... r {
        for x in -r ... r where x * x + y * y <= rSquared {
            put(e, cx + x, cy + y, id, temp)
        }
    }
}

/// A whole number in `lo ... hi`.
private func randInt(_ random: inout Mulberry32, _ lo: Int, _ hi: Int) -> Int {
    guard hi > lo else { return lo }
    return lo + Int((random.next() * Double(hi - lo + 1)).rounded(.down))
}

private func chance(_ random: inout Mulberry32, _ probability: Double) -> Bool {
    random.next() < probability
}

/// `Math.floor` on a fraction of a dimension, which is how the scenes are placed.
private func part(_ total: Int, _ fraction: Double) -> Int {
    Int((Double(total) * fraction).rounded(.down))
}

/// A ground height for every column.
///
/// A handful of random control points, interpolated with a smooth step so the joins are
/// curves rather than straight lines meeting at an angle. This is the single change that
/// stops every scene looking like a bar chart.
///
/// Draws `ridges + 1` numbers, before anything else uses the stream.
private func surface(
    _ width: Int,
    _ base: Int,
    _ amplitude: Int,
    _ ridges: Int,
    _ random: inout Mulberry32
) -> [Int] {
    let count = max(1, ridges)
    var points: [Double] = []
    for _ in 0 ... count { points.append(random.next()) }

    var out: [Int] = []
    out.reserveCapacity(max(0, width))
    let span = Double(max(1, width - 1))
    var x = 0
    while x < width {
        let t = Double(count) * Double(x) / span
        var i = Int(t.rounded(.down))
        if i >= count { i = count - 1 }
        let f = t - Double(i)
        // Smoothstep. Linear interpolation leaves visible creases where two runs meet.
        let s = f * f * (3 - 2 * f)
        let v = points[i] + (points[i + 1] - points[i]) * s
        out.append(base - Int((v * Double(amplitude)).rounded(.down)))
        x += 1
    }
    return out
}

/// Fills a band that follows a surface, from `from` cells below it to `to` cells below it.
private func layer(
    _ e: PowderEngine,
    _ top: [Int],
    _ from: Int,
    _ to: Int,
    _ id: ElementID,
    _ temp: Double? = nil
) {
    for x in 0 ..< top.count {
        let y0 = top[x] + from
        let y1 = top[x] + to
        var y = min(y0, y1)
        while y <= max(y0, y1) {
            put(e, x, y, id, temp)
            y += 1
        }
    }
}

/// Fills everything from a surface down to a given row.
private func layerDown(
    _ e: PowderEngine,
    _ top: [Int],
    _ from: Int,
    _ bottom: Int,
    _ id: ElementID,
    _ temp: Double? = nil
) {
    for x in 0 ..< top.count {
        var y = top[x] + from
        while y <= bottom {
            put(e, x, y, id, temp)
            y += 1
        }
    }
}

/// A disc with a ragged edge.
///
/// The radius wobbles per row, so a pond gets a shoreline and a boulder gets a silhouette.
/// Draws one number per row.
private func blob(
    _ e: PowderEngine,
    _ cx: Int,
    _ cy: Int,
    _ radius: Int,
    _ id: ElementID,
    _ random: inout Mulberry32,
    _ temp: Double? = nil
) {
    guard radius >= 1 else { return }
    var dy = -radius
    while dy <= radius {
        let straight = Double(max(0, radius * radius - dy * dy)).squareRoot()
        let wobble = 1 + (random.next() - 0.5) * 0.55
        let half = Int((straight * wobble).rounded(.down))
        var dx = -half
        while dx <= half {
            put(e, cx + dx, cy + dy, id, temp)
            dx += 1
        }
        dy += 1
    }
}

/// A wandering streak, one to two cells wide, heading down.
///
/// For lava on a hillside, ore in rock, a crack through ice. Draws two numbers per step.
private func vein(
    _ e: PowderEngine,
    _ x: Int,
    _ y: Int,
    _ steps: Int,
    _ id: ElementID,
    _ random: inout Mulberry32,
    _ temp: Double? = nil
) {
    var cx = x
    var i = 0
    while i < steps {
        put(e, cx, y + i, id, temp)
        if chance(&random, 0.55) { put(e, cx + 1, y + i, id, temp) }
        let drift = random.next()
        if drift < 0.3 {
            cx -= 1
        } else if drift > 0.7 {
            cx += 1
        }
        i += 1
    }
}

/// A tree: a trunk of its own height with a canopy of its own size.
///
/// Draws four numbers, so no two trees are the same shape.
private func tree(
    _ e: PowderEngine,
    _ x: Int,
    _ ground: Int,
    _ trunkId: ElementID,
    _ leafId: ElementID,
    _ scale: Int,
    _ random: inout Mulberry32
) {
    let height = randInt(&random, max(3, Int((Double(scale) * 0.55).rounded(.down))), max(4, scale))
    let canopy = randInt(
        &random,
        max(2, Int((Double(scale) * 0.3).rounded(.down))),
        max(3, Int((Double(scale) * 0.55).rounded(.down)))
    )
    let lean = randInt(&random, -1, 1)
    let top = ground - height

    var y = top
    while y <= ground {
        let offset = Int((Double((ground - y) * lean) / Double(max(1, height))).rounded(.down))
        put(e, x + offset, y, trunkId)
        if height > 9 { put(e, x + offset + 1, y, trunkId) }
        y += 1
    }
    blob(e, x + lean, top, canopy, leafId, &random)
}

/// Loose cells dropped over a region, so nothing is uniformly clean.
private func scatter(
    _ e: PowderEngine,
    _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
    _ count: Int,
    _ id: ElementID,
    _ random: inout Mulberry32,
    _ temp: Double? = nil
) {
    for _ in 0 ..< count {
        let x = randInt(&random, x0, x1)
        let y = randInt(&random, y0, y1)
        put(e, x, y, id, temp)
    }
}

/// The bowl every scene sits in. See the note at the top of this file.
private func basin(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    guard w > 2, h > 2 else { return }
    fillRect(e, 0, h - 2, w - 1, h - 1, Element.bedrock)
    fillRect(e, 0, part(h, 0.22), 1, h - 1, Element.bedrock)
    fillRect(e, w - 2, part(h, 0.22), w - 1, h - 1, Element.bedrock)
}

/// Reads a surface array safely, which the scenes need because a position can be off the edge.
private func at(_ values: [Int], _ x: Int) -> Int {
    guard !values.isEmpty else { return 0 }
    return values[max(0, min(values.count - 1, x))]
}

// MARK: - The scenes

private func seedVolcano(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let ground = surface(w, h - 3, max(2, part(h, 0.06)), 5, &random)
    layer(e, ground, 0, 2, Element.stone)
    layerDown(e, ground, 0, h - 3, Element.obsidian)

    let cx = part(w, 0.5) + randInt(&random, -part(w, 0.08), part(w, 0.08))
    let peak = part(h, 0.26) + randInt(&random, -part(h, 0.04), part(h, 0.04))
    let base = h - 4
    let half = part(w, 0.40)

    // The cone, one column at a time, with a rough edge rather than a clean triangle.
    var y = peak
    while y <= base {
        let t = Double(y - peak) / Double(max(1, base - peak))
        let span = max(2, Int((Double(half) * t * t * 0.85 + Double(half) * t * 0.2).rounded(.down)))
        let jitterL = randInt(&random, 0, 2)
        let jitterR = randInt(&random, 0, 2)
        var x = cx - span - jitterL
        while x <= cx + span + jitterR {
            let depth = abs(x - cx)
            // A crust of stone, obsidian deeper in where the old flows cooled.
            put(e, x, y, depth > span - 3 ? Element.stone : depth > span - 7 ? Element.obsidian : Element.dirt)
            x += 1
        }
        y += 1
    }

    // The throat, widening toward the top.
    let vent = max(1, part(w, 0.03))
    let throatBottom = part(h, 0.82)
    var ty = peak + 1
    while ty <= throatBottom {
        let t = 1 - Double(ty - peak) / Double(max(1, throatBottom - peak))
        let span = max(1, Int((Double(vent) * (0.5 + t)).rounded(.down)))
        fillRect(e, cx - span, ty, cx + span, ty, Element.lava, 1500)
        ty += 1
    }
    blob(e, cx, peak + 2, vent + 2, Element.lava, &random, 1650)

    // Flows spilling over the lip and down the flanks, each taking its own course.
    for i in 0 ..< 3 {
        let side = i % 2 == 0 ? -1 : 1
        let startX = cx + side * randInt(&random, vent, vent + 3)
        let length = randInt(&random, part(h, 0.18), part(h, 0.4))
        vein(e, startX, peak + 2, length, Element.lava, &random, 1300)
    }

    // Ash above the crater, thinning as it rises.
    for _ in 0 ..< 26 {
        let rise = randInt(&random, 1, max(2, part(h, 0.2)))
        let drift = randInt(&random, -rise, rise)
        put(e, cx + drift, peak - rise, chance(&random, 0.7) ? Element.smoke : Element.fire, 320)
    }
    scatter(e, cx - half, base - 4, cx + half, base, 24, Element.coal, &random)
}

private func seedAntFarm(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let ground = surface(w, part(h, 0.30), max(2, part(h, 0.05)), 4, &random)
    layer(e, ground, 0, 1, Element.plant)
    layer(e, ground, 1, 3, Element.dirt)
    layerDown(e, ground, 3, h - 3, Element.dirt)
    // Sand at the bottom, with an uneven top so the two soils interleave.
    let sandTop = surface(w, part(h, 0.74), max(2, part(h, 0.05)), 5, &random)
    layerDown(e, sandTop, 0, h - 3, Element.sand)

    // Tunnels: a random walk from the surface down, branching, rather than five straight runs.
    let mouths = randInt(&random, 2, 3)
    var chambers: [(x: Int, y: Int)] = []
    for _ in 0 ..< mouths {
        var x = randInt(&random, part(w, 0.12), part(w, 0.88))
        var y = at(ground, x) + 2
        let length = randInt(&random, part(h, 0.3), part(h, 0.55))
        for _ in 0 ..< length {
            let bore = randInt(&random, 1, 2)
            fillCircle(e, x, y, bore, Element.empty)
            // Mostly down, sometimes sideways, which is what makes it a tunnel and not a line.
            let turn = random.next()
            if turn < 0.28 {
                x -= randInt(&random, 1, 2)
            } else if turn < 0.56 {
                x += randInt(&random, 1, 2)
            } else {
                y += 1
            }
            if chance(&random, 0.12) { chambers.append((x, y)) }
            x = max(3, min(w - 4, x))
            y = min(h - 5, y)
        }
        chambers.append((x, y))
    }

    // Chambers hollowed out where the walk paused, then stocked.
    for spot in chambers {
        let size = randInt(&random, 2, 4)
        blob(e, spot.x, spot.y, size, Element.empty, &random)
    }
    for spot in chambers {
        if chance(&random, 0.45) {
            scatter(e, spot.x - 2, spot.y - 1, spot.x + 2, spot.y + 1, 4, Element.seed, &random)
        } else if chance(&random, 0.5) {
            scatter(e, spot.x - 2, spot.y - 1, spot.x + 2, spot.y + 1, 3, Element.honey, &random)
        }
    }
    // The colony, gathered near the chambers rather than sprinkled evenly.
    for spot in chambers {
        let crowd = randInt(&random, 2, 6)
        scatter(e, spot.x - 3, spot.y - 2, spot.x + 3, spot.y + 2, crowd, Element.ant, &random)
    }

    // A damp pocket, and roots reaching down from the grass.
    let pocketX = randInt(&random, part(w, 0.1), part(w, 0.3))
    let pocketR = randInt(&random, 3, 6)
    blob(e, pocketX, part(h, 0.82), pocketR, Element.water, &random)
    for _ in 0 ..< 5 {
        let x = randInt(&random, 4, w - 5)
        let depth = randInt(&random, 3, 8)
        vein(e, x, at(ground, x) + 1, depth, Element.plant, &random)
    }
}

private func seedOilFire(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let rock = surface(w, part(h, 0.72), max(2, part(h, 0.07)), 6, &random)
    layer(e, rock, 0, 2, Element.stone)
    layerDown(e, rock, 2, h - 3, Element.dirt)
    scatter(e, 3, part(h, 0.7), w - 4, h - 4, 30, Element.coal, &random)

    // A hollow scooped out of the rock, with oil pooled in it. Filled per column down to the
    // rock rather than as a rectangle, so the pool has a bed the shape of the ground under it.
    let hollowX = part(w, 0.5) + randInt(&random, -part(w, 0.1), part(w, 0.1))
    let hollowR = max(4, part(w, 0.3))
    let oilTop = part(h, 0.62)
    var x = hollowX - hollowR
    while x <= hollowX + hollowR {
        let across = Double(x - hollowX) / Double(hollowR)
        let depth = Int(((1 - across * across) * Double(part(h, 0.14))).rounded(.down))
        if depth > 0 {
            let bed = at(rock, x) + depth
            var y = oilTop
            while y <= bed {
                put(e, x, y, Element.oil)
                y += 1
            }
        }
        x += 1
    }

    // A gantry over it, with planks missing.
    let deck = part(h, 0.56)
    var gx = part(w, 0.14)
    while gx < w - part(w, 0.14) {
        let run = randInt(&random, 3, 7)
        fillRect(e, gx, deck, min(w - 4, gx + run), deck + 1, Element.wood)
        if chance(&random, 0.4) {
            let post = randInt(&random, 3, 6)
            fillRect(e, gx, deck + 2, gx, deck + post, Element.wood)
        }
        gx += run + randInt(&random, 1, 4)
    }

    // Alight at one end, so it has somewhere to spread to.
    let ignite = chance(&random, 0.5) ? part(w, 0.2) : part(w, 0.78)
    let flame = randInt(&random, 2, 4)
    blob(e, ignite, deck - 2, flame, Element.fire, &random, 820)
    scatter(e, ignite - 5, deck - 6, ignite + 5, deck - 3, 12, Element.smoke, &random)
    let puddleX = randInt(&random, part(w, 0.06), part(w, 0.16))
    let puddleR = randInt(&random, 3, 5)
    blob(e, puddleX, h - 6, puddleR, Element.water, &random)
}

private func seedIceDam(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let damX = part(w, 0.5) + randInt(&random, -part(w, 0.06), part(w, 0.06))

    // A gorge: rock either side, higher upstream.
    let bedUp = surface(w, part(h, 0.74), max(2, part(h, 0.05)), 4, &random)
    let bedDown = surface(w, part(h, 0.86), max(2, part(h, 0.04)), 5, &random)
    for x in 0 ..< w {
        let top = x < damX ? bedUp[x] : bedDown[x]
        var y = top
        while y <= h - 3 {
            put(e, x, y, y < top + 2 ? Element.stone : Element.dirt)
            y += 1
        }
    }

    // The wall, thicker at the bottom, with its face uneven.
    let damTop = part(h, 0.28) + randInt(&random, -part(h, 0.03), part(h, 0.03))
    var y = damTop
    while y <= h - 3 {
        let t = Double(y - damTop) / Double(max(1, h - 3 - damTop))
        let thickness = max(2, Int((3 + t * 5).rounded(.down)))
        let shift = randInt(&random, -1, 1)
        fillRect(e, damX + shift, y, damX + shift + thickness, y, Element.ice, -24)
        y += 1
    }
    // Cracks, which is where it will give way.
    for _ in 0 ..< 3 {
        let crackX = damX + randInt(&random, 0, 3)
        let crackY = damTop + randInt(&random, 2, max(3, part(h, 0.3)))
        let crackLen = randInt(&random, 3, 8)
        vein(e, crackX, crackY, crackLen, Element.water, &random, -2)
    }

    // The reservoir behind it, and a stream below.
    var rx = 2
    while rx < damX {
        var wy = part(h, 0.34) + randInt(&random, 0, 1)
        while wy < bedUp[max(0, min(w - 1, rx))] {
            put(e, rx, wy, Element.water)
            wy += 1
        }
        rx += 1
    }
    var sx2 = damX + 8
    while sx2 < w - 2 {
        let bed = bedDown[max(0, min(w - 1, sx2))]
        var wy = bed - randInt(&random, 0, 2)
        while wy < bed {
            put(e, sx2, wy, Element.water)
            wy += 1
        }
        sx2 += 1
    }

    // Snow on the upstream shoulders, and floes on the water.
    var sx = 3
    while sx < damX - 2 {
        let drift = randInt(&random, 1, 3)
        blob(e, sx, part(h, 0.32), drift, Element.snow, &random, -12)
        sx += randInt(&random, 3, 9)
    }
    for _ in 0 ..< 6 {
        let floeX = randInt(&random, 4, max(5, damX - 4))
        let floeR = randInt(&random, 1, 3)
        blob(e, floeX, part(h, 0.36), floeR, Element.ice, &random, -8)
    }
    for _ in 0 ..< 4 {
        let x = randInt(&random, damX + 10, max(damX + 11, w - 5))
        tree(e, x, at(bedDown, x) - 1, Element.wood, Element.plant, max(4, part(h, 0.12)), &random)
    }
}

private func seedReactor(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let floor = surface(w, part(h, 0.86), max(1, part(h, 0.03)), 4, &random)
    layerDown(e, floor, 0, h - 3, Element.concrete)

    let x0 = part(w, 0.24) + randInt(&random, -2, 2)
    let x1 = part(w, 0.76) + randInt(&random, -2, 2)
    let y0 = part(h, 0.24)
    let y1 = part(h, 0.80)
    let shell = max(2, part(w, 0.02))

    // A vessel with its corners taken off, which is most of what stops it reading as a box.
    let chamfer = max(2, Int((Double(x1 - x0) * 0.12).rounded(.down)))
    var y = y0
    while y <= y1 {
        var x = x0
        while x <= x1 {
            let fromTop = y - y0
            let fromBottom = y1 - y
            let fromLeft = x - x0
            let fromRight = x1 - x
            let corner = (fromTop + fromLeft < chamfer)
                || (fromTop + fromRight < chamfer)
                || (fromBottom + fromLeft < chamfer)
                || (fromBottom + fromRight < chamfer)
            if !corner {
                let wall = fromTop < shell || fromBottom < shell || fromLeft < shell || fromRight < shell
                put(e, x, y, wall ? Element.metal : Element.empty)
            }
            x += 1
        }
        y += 1
    }

    // Coolant, with a surface that is not a ruled line.
    let waterTop = surface(x1 - x0, part(h, 0.52), 2, 4, &random)
    for i in 0 ..< waterTop.count {
        var wy = waterTop[i]
        while wy <= y1 - shell - 1 {
            put(e, x0 + i, wy, Element.water)
            wy += 1
        }
    }

    // Fuel rods of differing length, at differing spacing.
    var rod = x0 + shell + randInt(&random, 2, 5)
    while rod < x1 - shell - 2 {
        let length = randInt(&random, part(h, 0.1), part(h, 0.26))
        let hot = chance(&random, 0.35)
        fillRect(
            e, rod, y0 + shell + 1, rod, y0 + shell + length,
            hot ? Element.thermite : Element.metal, hot ? 420 : nil
        )
        if chance(&random, 0.5) { put(e, rod, y0 + shell + length + 1, Element.spark, 900) }
        rod += randInt(&random, 3, 7)
    }

    // Gas collecting under the lid, a control spark, and shielding outside.
    scatter(e, x0 + shell + 1, y0 + shell + 1, x1 - shell - 1, part(h, 0.44), 40, Element.hydrogen, &random)
    blob(e, part(w, 0.5), y0 + shell + 2, 2, Element.spark, &random, 1200)
    let leftOut = randInt(&random, 3, 6)
    let leftUp = randInt(&random, 6, 12)
    fillRect(e, x0 - leftOut, y1 - leftUp, x0 - 1, y1, Element.concrete)
    let rightUp = randInt(&random, 6, 12)
    let rightOut = randInt(&random, 3, 6)
    fillRect(e, x1 + 1, y1 - rightUp, x1 + rightOut, y1, Element.concrete)
    scatter(e, 3, part(h, 0.88), part(w, 0.2), h - 4, 20, Element.water, &random)
}

private func seedStorm(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    // Rolling hills rather than a flat sea.
    let ground = surface(w, part(h, 0.72), max(3, part(h, 0.12)), 4, &random)
    layer(e, ground, 0, 1, Element.plant)
    layer(e, ground, 1, 4, Element.dirt)
    layerDown(e, ground, 4, h - 3, Element.stone)

    // The rod goes on the highest ground, which is where anyone would put it.
    var best = 0
    var bx = part(w, 0.2)
    while bx < part(w, 0.8) {
        if at(ground, bx) < at(ground, best) { best = bx }
        bx += 1
    }
    let rodTop = part(h, 0.2) + randInt(&random, -part(h, 0.04), part(h, 0.04))
    fillRect(e, best - 1, rodTop, best, at(ground, best), Element.copper)
    fillRect(e, best - 3, rodTop - 1, best + 2, rodTop, Element.metal)
    blob(e, best, rodTop - 2, 2, Element.spark, &random, 1250)

    // A band of cloud, thicker in places, with rain already falling from it.
    let cloud = part(h, 0.1)
    var cx = 2
    while cx < w - 2 {
        let run = randInt(&random, 4, 12)
        let depth = randInt(&random, 1, 3)
        fillRect(e, cx, cloud, min(w - 3, cx + run), cloud + depth, Element.smoke)
        if chance(&random, 0.6) {
            let drops = randInt(&random, 3, 9)
            scatter(e, cx, cloud + depth + 1, min(w - 3, cx + run), part(h, 0.4), drops, Element.water, &random)
        }
        cx += run + randInt(&random, 0, 3)
    }

    // Puddles in the dips, found rather than placed.
    for _ in 0 ..< 6 {
        let x = randInt(&random, 4, w - 5)
        let size = randInt(&random, 2, 4)
        blob(e, x, at(ground, x) - 1, size, Element.water, &random)
    }
    let shed = randInt(&random, part(w, 0.68), part(w, 0.84))
    let shedH = randInt(&random, 4, 7)
    let shedW = randInt(&random, 5, 9)
    fillRect(e, shed, at(ground, shed) - shedH, shed + shedW, at(ground, shed) - 1, Element.wood)
}

private func seedCircuit(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    // A board to mount things on.
    let boardTop = part(h, 0.36)
    let boardBottom = part(h, 0.8)
    fillRect(e, 3, boardTop, w - 4, boardBottom, Element.concrete)

    // Traces that branch and step instead of one straight wire.
    let rails = randInt(&random, 2, 4)
    var pads: [(x: Int, y: Int)] = []
    for r in 0 ..< rails {
        var y = boardTop + 3 + Int((Double((boardBottom - boardTop - 6) * r) / Double(max(1, rails - 1))).rounded(.down))
        var x = 6
        while x < w - 8 {
            let run = randInt(&random, 4, 10)
            fillRect(e, x, y, min(w - 8, x + run), y, Element.copper)
            x += run
            // A step up or down, so the trace has corners.
            if x < w - 12, chance(&random, 0.6) {
                let step = randInt(&random, -2, 2)
                let ny = max(boardTop + 2, min(boardBottom - 2, y + step))
                var yy = min(y, ny)
                while yy <= max(y, ny) {
                    put(e, x, yy, Element.copper)
                    yy += 1
                }
                y = ny
            }
            if chance(&random, 0.25) { pads.append((x, y)) }
        }
        pads.append((min(w - 8, x), y))
    }

    // A cell at the left driving it, pads and components along the way.
    fillRect(e, 4, boardTop + 2, 5, boardBottom - 2, Element.metal)
    blob(e, 5, part(h, 0.55), 2, Element.spark, &random, 1400)
    for pad in pads {
        fillRect(e, pad.x - 1, pad.y - 1, pad.x + 1, pad.y + 1, Element.metal)
    }
    for _ in 0 ..< 3 {
        let x = randInt(&random, part(w, 0.4), w - 12)
        let y = randInt(&random, boardTop + 3, boardBottom - 4)
        let size = randInt(&random, 2, 4)
        fillRect(e, x, y - 2, x + size, y + 2, chance(&random, 0.5) ? Element.c4 : Element.glass)
    }
    scatter(e, 4, boardTop + 1, w - 5, boardBottom - 1, 18, Element.fuseWire, &random)
}

private func seedVacuum(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let floor = surface(w, part(h, 0.88), max(1, part(h, 0.02)), 3, &random)
    layerDown(e, floor, 0, h - 3, Element.stone)

    let cx = part(w, 0.5)
    let cy = part(h, 0.52)
    let radius = max(6, min(part(w, 0.34), part(h, 0.26)))

    // A round vessel, which is what a vacuum chamber would be, rather than a rectangle.
    let shell = max(2, Int((Double(radius) * 0.12).rounded(.down)))
    var dy = -radius
    while dy <= radius {
        var dx = -radius
        while dx <= radius {
            let d = Double(dx * dx + dy * dy).squareRoot()
            if d <= Double(radius) {
                put(e, cx + dx, cy + dy, d > Double(radius - shell) ? Element.metal : Element.empty)
            }
            dx += 1
        }
        dy += 1
    }
    // A viewing port and a valve, so it is a made object.
    fillRect(e, cx - 2, cy - radius, cx + 2, cy - radius + shell, Element.glass)
    fillRect(e, cx + radius - shell, cy - 1, cx + radius + 3, cy + 1, Element.metal)

    blob(e, cx, cy, max(2, Int((Double(radius) * 0.22).rounded(.down))), Element.void, &random)

    // Gases still inside, in pockets rather than a neat block.
    let gases: [ElementID] = [Element.hydrogen, Element.oxygen, Element.helium]
    for _ in 0 ..< 5 {
        let angle = random.next() * Double.pi * 2
        let distance = Double(radius) * (0.4 + random.next() * 0.4)
        let pocketSize = randInt(&random, 2, 4)
        let gas = gases[randInt(&random, 0, gases.count - 1)]
        blob(
            e,
            cx + Int((jsCos(angle) * distance).rounded(.down)),
            cy + Int((jsSin(angle) * distance).rounded(.down)),
            pocketSize,
            gas,
            &random
        )
    }
    scatter(e, cx - radius + shell, cy, cx + radius - shell, cy + radius - shell, 16, Element.smoke, &random)
}

private func seedSnow(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let ground = surface(w, part(h, 0.74), max(4, part(h, 0.14)), 5, &random)
    layer(e, ground, 0, 2, Element.snow, -8)
    layer(e, ground, 2, 5, Element.ice, -14)
    layerDown(e, ground, 5, h - 3, Element.stone)

    // Drifts piled against the slopes, deeper where the ground rises.
    var x = 2
    while x < w - 2 {
        let slope = at(ground, x - 2) - at(ground, x + 2)
        let depth = max(0, Int((Double(slope) * 0.6).rounded(.down)))
        var y = at(ground, x) - depth
        while y < at(ground, x) {
            put(e, x, y, Element.snow, -6)
            y += 1
        }
        x += 1
    }

    // A pond frozen over in a dip.
    var low = part(w, 0.2)
    var lx = part(w, 0.2)
    while lx < part(w, 0.8) {
        if at(ground, lx) > at(ground, low) { low = lx }
        lx += 1
    }
    let pondR = randInt(&random, 4, 7)
    blob(e, low, at(ground, low) + 2, pondR, Element.water, &random, 1)
    fillRect(e, low - 6, at(ground, low) - 1, low + 6, at(ground, low), Element.ice, -3)

    // Evergreens: narrow, tall, snow-laden.
    var tx = randInt(&random, 4, 10)
    while tx < w - 6 {
        let groundY = at(ground, tx)
        tree(e, tx, groundY, Element.wood, Element.plant, max(5, part(h, 0.16)), &random)
        scatter(e, tx - 3, groundY - max(6, part(h, 0.16)), tx + 3, groundY - 3, 6, Element.snow, &random, -6)
        tx += randInt(&random, 6, max(7, part(w, 0.18)))
    }

    // Snow still coming down, in gusts rather than three ruled rows.
    for _ in 0 ..< max(20, part(w, 1.2)) {
        let fx = randInt(&random, 3, w - 4)
        let fy = randInt(&random, 3, part(h, 0.34))
        put(e, fx, fy, Element.snow, -10)
    }
}

private func seedBeach(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    // A shore that slopes into the water, with dunes behind it.
    let dune = surface(w, part(h, 0.62), max(3, part(h, 0.1)), 5, &random)
    let shoreline = part(w, 0.55) + randInt(&random, -part(w, 0.1), part(w, 0.1))
    var beach: [Int] = []
    beach.reserveCapacity(max(0, w))
    for x in 0 ..< w {
        let past = Double(x - shoreline) / Double(max(1, w - shoreline))
        let drop = x > shoreline ? Int((past * Double(part(h, 0.2))).rounded(.down)) : 0
        beach.append(dune[x] + drop)
    }
    layer(e, beach, 0, 3, Element.sand)
    layerDown(e, beach, 3, h - 3, Element.dirt)

    // Sea over the sloping part, its surface level.
    let seaLevel = part(h, 0.66)
    var sx = shoreline
    while sx < w - 2 {
        var y = seaLevel
        while y < at(beach, sx) {
            put(e, sx, y, Element.water)
            y += 1
        }
        sx += 1
    }
    // Wet sand where the two meet.
    let wetFrom = max(2, shoreline - randInt(&random, 4, 10))
    var wx = wetFrom
    while wx < shoreline + 3 {
        var y = at(beach, wx)
        while y < at(beach, wx) + 2 {
            put(e, wx, y, Element.wetMix)
            y += 1
        }
        wx += 1
    }

    // Rocks at one end, a palm, and shells up the beach.
    for _ in 0 ..< 4 {
        let x = randInt(&random, 3, part(w, 0.2))
        let sink = randInt(&random, 0, 2)
        let rockR = randInt(&random, 2, 4)
        blob(e, x, at(dune, x) - sink, rockR, Element.stone, &random)
    }
    let palm = randInt(&random, part(w, 0.22), max(part(w, 0.23), part(w, 0.45)))
    tree(e, palm, at(dune, palm), Element.wood, Element.plant, max(6, part(h, 0.18)), &random)
    scatter(e, 3, part(h, 0.58), shoreline, part(h, 0.64), 22, Element.salt, &random)
    scatter(e, shoreline, seaLevel, w - 4, seaLevel + 2, 10, Element.snow, &random)
}

private func seedForest(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    // Grass over dirt over stone, all following the same rolling surface.
    let ground = surface(w, part(h, 0.70), max(4, part(h, 0.13)), 5, &random)
    layer(e, ground, 0, 1, Element.plant)
    layer(e, ground, 1, 4, Element.dirt)
    layerDown(e, ground, 4, h - 3, Element.stone)

    // A pond in the lowest dip, with a shoreline.
    var low = part(w, 0.15)
    var lx = part(w, 0.15)
    while lx < part(w, 0.85) {
        if at(ground, lx) > at(ground, low) { low = lx }
        lx += 1
    }
    let pondR = randInt(&random, max(3, part(w, 0.06)), max(5, part(w, 0.14)))
    blob(e, low, at(ground, low) + pondR - 1, pondR, Element.empty, &random)
    blob(e, low, at(ground, low) + pondR - 1, pondR - 1, Element.water, &random)
    var mx = low - pondR
    while mx <= low + pondR {
        put(e, mx, at(ground, mx), Element.mud)
        mx += 1
    }

    // Trees of their own heights at their own spacing, thinning near the pond.
    var x = randInt(&random, 3, 8)
    while x < w - 5 {
        let groundY = at(ground, x)
        let nearPond = abs(x - low) < pondR + 2
        if !nearPond {
            tree(e, x, groundY, Element.wood, Element.plant, max(5, part(h, 0.2)), &random)
            // Undergrowth at the foot of it.
            if chance(&random, 0.6) {
                let bushes = randInt(&random, 2, 5)
                scatter(e, x - 3, groundY - 2, x + 3, groundY, bushes, Element.plant, &random)
            }
        }
        x += randInt(&random, 4, max(5, part(w, 0.16)))
    }

    // Seeds and fallen wood on the floor, and a mossy boulder or two.
    scatter(e, 3, part(h, 0.6), w - 4, part(h, 0.72), 20, Element.seed, &random)
    for _ in 0 ..< 3 {
        let bx = randInt(&random, 4, w - 5)
        let size = randInt(&random, 2, 3)
        blob(e, bx, at(ground, bx) - 1, size, Element.stone, &random)
    }
}

private func seedKiln(_ e: PowderEngine, _ random: inout Mulberry32) {
    let w = e.width
    let h = e.height
    basin(e)

    let floor = surface(w, part(h, 0.84), max(1, part(h, 0.02)), 3, &random)
    layerDown(e, floor, 0, h - 3, Element.dirt)

    let x0 = part(w, 0.26) + randInt(&random, -2, 2)
    let x1 = part(w, 0.74) + randInt(&random, -2, 2)
    let top = part(h, 0.34)
    let bottom = part(h, 0.82)
    let wall = max(2, part(w, 0.025))
    let cx = (x0 + x1) / 2

    // A domed kiln, not a rectangle: a barrel vault over straight sides.
    let domeR = (x1 - x0) / 2
    var y = bottom
    while y >= top + domeR {
        fillRect(e, x0, y, x0 + wall, y, Element.stone)
        fillRect(e, x1 - wall, y, x1, y, Element.stone)
        y -= 1
    }
    var dy = 0
    while dy <= domeR {
        let span = Int(Double(max(0, domeR * domeR - dy * dy)).squareRoot().rounded(.down))
        var dx = -span
        while dx <= span {
            let d = Double(dx * dx + dy * dy).squareRoot()
            if d > Double(domeR - wall) { put(e, cx + dx, top + domeR - dy, Element.stone) }
            dx += 1
        }
        dy += 1
    }
    fillRect(e, x0, bottom, x1, bottom + wall, Element.stone)

    // A stoking arch in the front wall, and a chimney out of the crown.
    let arch = randInt(&random, 3, 5)
    fillRect(e, x0, bottom - arch, x0 + wall, bottom - 1, Element.empty)
    let flue = max(1, Int((Double(wall) * 0.8).rounded(.down)))
    fillRect(e, cx - flue, part(h, 0.14), cx + flue, top + 1, Element.stone)
    fillRect(e, cx - flue + 1, part(h, 0.14), cx + flue - 1, top + 1, Element.empty)
    scatter(e, cx - flue, part(h, 0.06), cx + flue, part(h, 0.16), 14, Element.smoke, &random)

    // The fire underneath, the pots stacked above it.
    let fireDepth = randInt(&random, 4, 7)
    fillRect(e, x0 + wall + 1, bottom - fireDepth, x1 - wall - 1, bottom - 1, Element.lava, 1150)
    scatter(e, x0 + wall + 1, bottom - 8, x1 - wall - 1, bottom - 2, 16, Element.coal, &random)
    var pot = x0 + wall + randInt(&random, 2, 4)
    while pot < x1 - wall - 3 {
        let size = randInt(&random, 2, 4)
        let shelf = randInt(&random, 2, 6)
        blob(e, pot, top + domeR + shelf, size, Element.mud, &random)
        pot += size + randInt(&random, 2, 5)
    }
    // A woodpile outside, ready.
    let pile = chance(&random, 0.5) ? x0 - randInt(&random, 6, 12) : x1 + randInt(&random, 3, 8)
    // Hoisted: as a loop condition this drew a fresh number on every pass, so the pile's
    // height was decided again each time round.
    let logs = randInt(&random, 3, 6)
    for i in 0 ..< logs {
        let logLen = randInt(&random, 3, 6)
        fillRect(e, pile, bottom - i * 2, pile + logLen, bottom - i * 2, Element.wood)
    }
}

/// Picks one of the twelve at random and scatters deposits through it.
private func seedRemix(_ e: PowderEngine, _ random: inout Mulberry32) {
    let pack: [(PowderEngine, inout Mulberry32) -> Void] = [
        seedVolcano, seedAntFarm, seedOilFire, seedIceDam,
        seedReactor, seedStorm, seedCircuit, seedVacuum,
        seedSnow, seedBeach, seedForest, seedKiln,
    ]
    let choice = Int((random.next() * Double(pack.count)).rounded(.down))
    pack[choice](e, &random)

    let w = e.width
    let h = e.height
    let ids: [ElementID] = [
        Element.sand, Element.water, Element.lava, Element.oil,
        Element.plant, Element.ice, Element.copper, Element.wetMix,
        Element.thermite, Element.honey, Element.salt, Element.coal,
    ]
    // Clusters rather than single cells. Forty lone specks scattered over a world read as
    // dirt on the screen; a dozen small deposits read as something having happened.
    for _ in 0 ..< 12 {
        let x = 4 + Int((random.next() * Double(w - 8)).rounded(.down))
        let y = part(h, 0.25) + Int((random.next() * (Double(h) * 0.55)).rounded(.down))
        let size = randInt(&random, 1, 3)
        let id = ids[Int((random.next() * Double(ids.count)).rounded(.down))]
        blob(e, x, y, size, id, &random)
    }
}

/// The scenes, in the order the interface shows them.
///
/// The order is part of the contract: the daily scene is chosen by taking a hash of the
/// date modulo this count, so reordering the list changes which scene a given day gets.
public let powderRecipes: [PowderRecipe] = [
    PowderRecipe(id: "volcano", name: "Volcano") { e, random in seedVolcano(e, &random) },
    PowderRecipe(id: "ants", name: "Ant farm") { e, random in seedAntFarm(e, &random) },
    PowderRecipe(id: "oil", name: "Oil fire") { e, random in seedOilFire(e, &random) },
    PowderRecipe(id: "dam", name: "Ice dam") { e, random in seedIceDam(e, &random) },
    PowderRecipe(id: "reactor", name: "Reactor") { e, random in seedReactor(e, &random) },
    PowderRecipe(id: "storm", name: "Storm") { e, random in seedStorm(e, &random) },
    PowderRecipe(id: "circuit", name: "Circuit") { e, random in seedCircuit(e, &random) },
    PowderRecipe(id: "vacuum", name: "Vacuum") { e, random in seedVacuum(e, &random) },
    PowderRecipe(id: "snow", name: "Snow") { e, random in seedSnow(e, &random) },
    PowderRecipe(id: "beach", name: "Beach") { e, random in seedBeach(e, &random) },
    PowderRecipe(id: "forest", name: "Forest") { e, random in seedForest(e, &random) },
    PowderRecipe(id: "kiln", name: "Kiln") { e, random in seedKiln(e, &random) },
    PowderRecipe(id: "remix", name: "Remix") { e, random in seedRemix(e, &random) },
]
