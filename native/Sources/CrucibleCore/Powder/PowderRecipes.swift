/// The built-in scenes: a volcano, an ant farm, a reactor, and ten more.
///
/// Each one wipes the world and lays out a starting arrangement, in fractions of the
/// world's width and height so it looks right at any size. Twelve are laid out purely from
/// the dimensions and so are identical every time; the thirteenth, Remix, scatters
/// elements and needs a source of random numbers.
///
/// ## The basin, and why the repair tools must not touch it
///
/// Every scene starts with ``basin(_:)``: bedrock across the bottom two rows and up the
/// two outer columns, but only from 22% of the way down. The top of the world and the
/// upper fifth of the side walls are deliberately open, so things can be poured in and
/// gas can escape. That is why sealing the perimeter is a manual action and not part of
/// the automatic repair pass — running it over a scene destroys the shape the scene is.
///
/// ## Undo
///
/// Applying a recipe resets the grid but takes no snapshot; recording one is the caller's
/// business, because the engine does not own the undo record. The web reference bundled
/// the two together, which meant the only way to clear the world was also the only way to
/// record an undo point.

/// One scene.
public struct PowderRecipe: Sendable {
    public let id: String
    public let name: String
    /// Lays the scene out. The generator is consulted only by Remix.
    let build: @Sendable (PowderEngine, inout Mulberry32) -> Void

    /// Wipes the world and lays this scene out in it.
    ///
    /// - Parameter random: Consulted only by Remix. Pass a generator seeded from something
    ///   shared — the date, say — when every player must get the same world.
    public func apply(to engine: PowderEngine, random: inout Mulberry32) {
        engine.resetGrid()
        build(engine, &random)
    }

    /// Convenience for the twelve scenes that need no randomness.
    public func apply(to engine: PowderEngine) {
        var unused = Mulberry32(seed: 0)
        apply(to: engine, random: &unused)
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
    // Corners are sorted, so the two may be given in either order.
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

/// The bowl every scene sits in. See the note at the top of this file.
private func basin(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    guard w > 2, h > 2 else { return }
    fillRect(e, 0, h - 2, w - 1, h - 1, Element.bedrock)
    fillRect(e, 0, Int(Double(h) * 0.22), 1, h - 1, Element.bedrock)
    fillRect(e, w - 2, Int(Double(h) * 0.22), w - 1, h - 1, Element.bedrock)
}

/// `Math.floor` on a fraction of a dimension, which is how every scene is laid out.
private func part(_ total: Int, _ fraction: Double) -> Int {
    Int((Double(total) * fraction).rounded(.down))
}

// MARK: - The scenes

private func seedVolcano(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    let cx = part(w, 0.5)
    let base = h - 3
    let peak = part(h, 0.28)
    let half = part(w, 0.38)

    // The cone: stone at the edges, dirt inside, widening toward the base.
    if peak < base {
        for y in peak ..< base {
            let t = Double(y - peak) / Double(max(1, base - peak))
            let span = max(3, Int((Double(half) * t).rounded(.down)))
            for x in (cx - span) ... (cx + span) {
                let edge = abs(x - cx) > span - 2
                put(e, x, y, edge ? Element.stone : Element.dirt)
            }
        }
    }

    let vent = max(2, part(w, 0.04))
    let ventTop = part(h, 0.72)
    if peak < ventTop {
        for y in peak ..< ventTop {
            fillRect(e, cx - vent, y, cx + vent, y, Element.lava, 1400)
        }
    }
    fillCircle(e, cx, peak + 2, vent + 1, Element.lava, 1600)
    fillCircle(e, cx, peak - 1, vent, Element.fire, 900)
    for i in 0 ..< 18 {
        put(e, cx + ((i % 5) - 2), peak - 2 - (i / 5), Element.smoke)
    }
}

private func seedAntFarm(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.35), w - 3, h - 3, Element.dirt)
    fillRect(e, 2, part(h, 0.72), w - 3, h - 3, Element.sand)

    // Tunnels, carved as air along five straight runs.
    var tunnels: [(x: Int, y: Int)] = []
    let path: [(Double, Double, Double, Double)] = [
        (0.18, 0.42, 0.55, 0.42),
        (0.55, 0.42, 0.55, 0.62),
        (0.55, 0.62, 0.82, 0.62),
        (0.30, 0.42, 0.30, 0.70),
        (0.30, 0.70, 0.48, 0.70),
    ]
    for (x0, y0, x1, y1) in path {
        let ax = part(w, x0)
        let ay = part(h, y0)
        let bx = part(w, x1)
        let by = part(h, y1)
        let steps = max(abs(bx - ax), abs(by - ay), 1)
        for i in 0 ... steps {
            let x = Int(JS.round(Double(ax) + Double((bx - ax) * i) / Double(steps)))
            let y = Int(JS.round(Double(ay) + Double((by - ay) * i) / Double(steps)))
            fillCircle(e, x, y, 2, Element.empty)
            tunnels.append((x, y))
        }
    }
    // Ants go in after all the carving, so none of them is buried by a later run.
    var i = 0
    while i < tunnels.count {
        put(e, tunnels[i].x, tunnels[i].y, Element.ant)
        i += 6
    }

    fillRect(e, part(w, 0.12), part(h, 0.28), part(w, 0.22), part(h, 0.34), Element.plant)
    fillRect(e, part(w, 0.70), part(h, 0.30), part(w, 0.78), part(h, 0.34), Element.wood)
    fillRect(e, part(w, 0.08), part(h, 0.78), part(w, 0.20), h - 4, Element.water)
}

private func seedOilFire(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.62), w - 3, h - 3, Element.sand)
    fillRect(e, part(w, 0.18), part(h, 0.48), part(w, 0.82), part(h, 0.62), Element.oil)
    var x = part(w, 0.22)
    while Double(x) < Double(w) * 0.78 {
        put(e, x, part(h, 0.46), Element.wood)
        put(e, x, part(h, 0.45), Element.wood)
        x += 3
    }
    fillCircle(e, part(w, 0.5), part(h, 0.44), 4, Element.fire, 800)
    fillRect(e, part(w, 0.08), part(h, 0.70), part(w, 0.16), h - 4, Element.water)
}

private func seedIceDam(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.70), part(w, 0.52), h - 3, Element.dirt)
    let damX = part(w, 0.52)
    fillRect(e, damX, part(h, 0.32), damX + 4, h - 3, Element.ice, -20)
    fillRect(e, damX + 1, part(h, 0.32), damX + 3, h - 3, Element.ice, -30)
    fillRect(e, 2, part(h, 0.38), damX - 1, part(h, 0.70), Element.water)
    fillRect(e, damX + 5, part(h, 0.78), w - 3, h - 3, Element.sand)
    var x = 4
    while x < damX - 2 {
        put(e, x, part(h, 0.36), Element.snow, -10)
        x += 4
    }
    fillRect(e, part(w, 0.70), part(h, 0.68), part(w, 0.86), part(h, 0.78), Element.plant)
}

private func seedReactor(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    let x0 = part(w, 0.28)
    let x1 = part(w, 0.72)
    let y0 = part(h, 0.28)
    let y1 = part(h, 0.78)
    fillRect(e, x0, y0, x1, y1, Element.metal)
    fillRect(e, x0 + 2, y0 + 2, x1 - 2, y1 - 2, Element.empty)
    fillRect(e, x0 + 3, part(h, 0.52), x1 - 3, y1 - 3, Element.water)
    fillRect(e, x0 + 6, y0 + 4, x1 - 6, part(h, 0.48), Element.hydrogen)
    fillRect(e, part(w, 0.48), y0 + 3, part(w, 0.52), y0 + 6, Element.spark)
    fillRect(e, x0 - 4, y1 - 8, x0 + 1, y1 - 2, Element.thermite)
    fillRect(e, x1 - 1, y1 - 8, x1 + 4, y1 - 2, Element.concrete)
    fillRect(e, 3, h - 8, part(w, 0.22), h - 3, Element.water)
}

private func seedStorm(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.62), w - 3, h - 3, Element.water)
    let rod = part(w, 0.5)
    fillRect(e, rod - 1, part(h, 0.22), rod + 1, part(h, 0.62), Element.copper)
    fillRect(e, rod - 4, part(h, 0.20), rod + 4, part(h, 0.22), Element.metal)
    fillCircle(e, rod, part(h, 0.16), 2, Element.spark, 1200)
    fillRect(e, part(w, 0.12), part(h, 0.50), part(w, 0.28), part(h, 0.62), Element.oil)
    fillRect(e, part(w, 0.70), part(h, 0.48), part(w, 0.84), part(h, 0.58), Element.wood)
}

private func seedCircuit(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    let y = part(h, 0.55)
    fillRect(e, 8, y, w - 9, y + 1, Element.copper)
    fillRect(e, 6, y - 1, 8, y + 2, Element.metal)
    fillCircle(e, 6, y, 2, Element.spark, 1400)
    fillRect(e, w - 14, y - 3, w - 8, y + 4, Element.c4)
}

private func seedVacuum(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    let x0 = part(w, 0.22)
    let x1 = part(w, 0.78)
    let y0 = part(h, 0.28)
    let y1 = part(h, 0.78)
    fillRect(e, x0, y0, x1, y0 + 1, Element.stone)
    fillRect(e, x0, y1 - 1, x1, y1, Element.stone)
    fillRect(e, x0, y0, x0 + 1, y1, Element.stone)
    fillRect(e, x1 - 1, y0, x1, y1, Element.stone)
    fillCircle(e, part(w, 0.5), part(h, 0.52), 3, Element.void)
    fillRect(e, x0 + 3, y1 - 8, x1 - 3, y1 - 3, Element.smoke)
    fillRect(e, x0 + 4, y0 + 4, x0 + 18, y0 + 10, Element.steam, 140)
}

private func seedSnow(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.72), w - 3, h - 3, Element.ice)
    // Three rows of falling snow. The web original wrapped an index in a way that made
    // the row number always zero, so it drew exactly one row.
    let snowSpan = max(1, w - 6)
    for row in 0 ..< 3 {
        for i in 0 ..< snowSpan {
            put(e, 3 + i, 4 + row * 2, Element.snow)
        }
    }
    fillRect(e, part(w, 0.40), part(h, 0.45), part(w, 0.60), part(h, 0.72), Element.stone)
    fillRect(e, part(w, 0.18), part(h, 0.58), part(w, 0.32), part(h, 0.72), Element.water)
}

private func seedBeach(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.62), w - 3, h - 3, Element.sand)
    fillRect(e, 2, part(h, 0.48), part(w, 0.62), part(h, 0.62), Element.water)
    fillRect(e, part(w, 0.55), part(h, 0.58), w - 3, part(h, 0.72), Element.oil)
    fillRect(e, part(w, 0.08), part(h, 0.42), part(w, 0.16), part(h, 0.62), Element.ant)
}

private func seedForest(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    fillRect(e, 2, part(h, 0.72), w - 3, h - 3, Element.plant)
    for i in 0 ..< 7 {
        let x = 8 + Int((Double(i) / 6.0 * Double(w - 20)).rounded(.down))
        fillRect(e, x, part(h, 0.50), x + 1, part(h, 0.72), Element.wood)
        // Plant, not ant. Ants eat wood, dirt and plants, so canopies made of ants
        // devoured the trunks holding them up moments after the scene loaded.
        fillCircle(e, x, part(h, 0.48), 4, Element.plant)
    }
    fillRect(e, part(w, 0.70), part(h, 0.58), w - 4, part(h, 0.72), Element.water)
}

private func seedKiln(_ e: PowderEngine) {
    let w = e.width
    let h = e.height
    basin(e)
    let x0 = part(w, 0.28)
    let x1 = part(w, 0.72)
    let y0 = part(h, 0.38)
    let y1 = part(h, 0.78)
    fillRect(e, x0, y0, x1, y0 + 1, Element.stone)
    fillRect(e, x0, y1 - 1, x1, y1, Element.stone)
    fillRect(e, x0, y0, x0 + 1, y1, Element.stone)
    fillRect(e, x1 - 1, y0, x1, y1, Element.stone)
    fillRect(e, x0 + 3, y1 - 8, x1 - 3, y1 - 3, Element.lava, 1100)
    fillRect(e, x0 + 4, y0 + 6, x1 - 4, y0 + 10, Element.sand)
    fillRect(e, x0 + 2, y0 + 2, x0 + 4, y0 + 5, Element.fire, 700)
}

/// Picks one of the twelve at random and scatters extras through it.
private func seedRemix(_ e: PowderEngine, _ random: inout Mulberry32) {
    let pack: [(PowderEngine) -> Void] = [
        seedVolcano, seedAntFarm, seedOilFire, seedIceDam,
        seedReactor, seedStorm, seedCircuit, seedVacuum,
        seedSnow, seedBeach, seedForest, seedKiln,
    ]
    pack[Int(random.next() * Double(pack.count))](e)

    let w = e.width
    let h = e.height
    let ids: [ElementID] = [
        Element.sand, Element.water, Element.lava, Element.oil,
        Element.plant, Element.ice, Element.copper, Element.wetMix,
    ]
    // Forty scattered cells. The three draws happen in this order — position across,
    // position down, then which element — and every one is taken even when the resulting
    // position falls outside a very small world and the cell is dropped. The order and
    // the count are part of the behaviour, not an implementation detail.
    for _ in 0 ..< 40 {
        let x = 4 + Int((random.next() * Double(w - 8)).rounded(.down))
        let y = part(h, 0.3) + Int((random.next() * (Double(h) * 0.5)).rounded(.down))
        put(e, x, y, ids[Int(random.next() * Double(ids.count))])
    }
}

/// The scenes, in the order the interface shows them.
///
/// The order is part of the contract: the daily scene is chosen by taking a hash of the
/// date modulo this count, so reordering the list changes which scene a given day gets.
public let powderRecipes: [PowderRecipe] = [
    PowderRecipe(id: "volcano", name: "Volcano") { e, _ in seedVolcano(e) },
    PowderRecipe(id: "ants", name: "Ant farm") { e, _ in seedAntFarm(e) },
    PowderRecipe(id: "oil", name: "Oil fire") { e, _ in seedOilFire(e) },
    PowderRecipe(id: "dam", name: "Ice dam") { e, _ in seedIceDam(e) },
    PowderRecipe(id: "reactor", name: "Reactor") { e, _ in seedReactor(e) },
    PowderRecipe(id: "storm", name: "Storm") { e, _ in seedStorm(e) },
    PowderRecipe(id: "circuit", name: "Circuit") { e, _ in seedCircuit(e) },
    PowderRecipe(id: "vacuum", name: "Vacuum") { e, _ in seedVacuum(e) },
    PowderRecipe(id: "snow", name: "Snow") { e, _ in seedSnow(e) },
    PowderRecipe(id: "beach", name: "Beach") { e, _ in seedBeach(e) },
    PowderRecipe(id: "forest", name: "Forest") { e, _ in seedForest(e) },
    PowderRecipe(id: "kiln", name: "Kiln") { e, _ in seedKiln(e) },
    PowderRecipe(id: "remix", name: "Remix") { e, random in seedRemix(e, &random) },
]
