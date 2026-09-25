/// Twelve more things to fill the field with.
///
/// The scenes the field already had are all one family — galaxies, black holes, vortices, fountains,
/// lattices. They are all about a centre and a force. These twelve are about a *pattern*: a shape that
/// exists because of where each body was put, not because of what is pulling on it.
///
/// Merged from the reference particle sandbox (`HELION-MERGE.md`, slice D), with the geometry kept and
/// three things changed on purpose:
///
///   - **Every draw comes from the field's own random stream.** Nothing in the reference is seeded, so
///     nothing in it can be repeated; this project has recorded comparisons that check the stream is
///     consumed identically, which means a scene here can be reproduced exactly from a seed.
///   - **Distances are in pixels, not in fractions of a normalised world.** Its world is a fixed shape;
///     here the world is the phone's screen. Anything that should stay the same shape whatever the
///     screen is measured against the *shorter* side, so a circle is a circle in either orientation. A
///     handful of its scenes mix the two, so they stretch when the window does.
///   - **A few of its figures are wrong and are corrected**, each noted where it happens — its
///     triangle is squat, its water molecule's angle comes out at seventy-five degrees rather than the
///     hundred and four and a half it claims, and its snowflakes overrun their own radius.
///
/// These place into the swarm rather than the object list, because they are crowds: a sunflower is four
/// thousand seeds, and the per-body extras the object list carries — charge, springs, trails, lifetimes —
/// mean nothing to a seed and would cap the count at a few hundred. The one exception is the molecule
/// scene, which is bonds and therefore belongs with the springs.
extension ParticleEngine {
    // MARK: - Shared groundwork

    /// The shorter side of the world.
    ///
    /// Anything that should keep its shape is measured against this. Using the width would make every
    /// circle an ellipse the moment the phone was turned.
    var patternSpan: Double { min(width, height) }

    /// How many bodies a pattern may add.
    private var patternRoom: Int {
        max(0, maxParticles - particles.count - swarm.count)
    }

    /// Puts one body into the swarm, and says whether to keep going.
    @discardableResult
    private func place(
        _ x: Double,
        _ y: Double,
        velocityX: Double = 0,
        velocityY: Double = 0,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62
    ) -> Bool {
        swarm.append(
            x: x,
            y: y,
            velocityX: velocityX,
            velocityY: velocityY,
            color: PackedColor(hue: hue, saturation: saturation, lightness: lightness).packedRGBA,
            budget: maxParticles - particles.count
        )
    }

    /// A number between the two given, from the field's own stream.
    private func between(_ low: Double, _ high: Double) -> Double {
        low + rng.next() * (high - low)
    }

    // MARK: - Sunflower

    /// A sunflower's seed head: the spiral that appears when each seed is placed a fixed turn on from
    /// the last.
    ///
    /// The turn is the golden angle, which is what makes this work rather than producing arms. Written
    /// out because it is the whole scene: a turn of exactly a third, or a quarter, or any simple
    /// fraction gives three or four straight spokes, and only an angle that is not any fraction fills
    /// the disc evenly. The golden angle is the least fraction-like number there is.
    ///
    /// The radius grows as the square root of how far through the count a seed is, which is what keeps
    /// the seeds the same distance apart all the way out — area grows as the square of radius, so
    /// spacing stays even only if radius grows as the square root of the number placed.
    public func spawnSunflower(count requested: Int = 4_200) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        // Pi times three minus the square root of five. About 137.5 degrees.
        let goldenAngle = 3.141592653589793 * (3 - 5.0.squareRoot())
        let outer = 0.44 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        // A quarter turn of jitter on the whole head, so two sunflowers in a row are not the same
        // picture. The pattern itself is exact; only where it starts is random.
        let phase = between(0, 6.283185307179586)

        for index in 0 ..< total {
            let through = Double(index) / Double(max(1, total - 1))
            let radius = through.squareRoot() * outer
            let angle = Double(index) * goldenAngle + phase
            let x = centreX + jsCos(angle) * radius
            let y = centreY + jsSin(angle) * radius
            // Turning slowly, faster further out, so the head reads as a disc rather than a printed
            // pattern. The reference implementation does the same and it is what sells it.
            let spin = 0.0825
            guard place(
                x,
                y,
                velocityX: -jsSin(angle) * spin * radius * 0.02,
                velocityY: jsCos(angle) * spin * radius * 0.02,
                hue: (through * 300 + angle * 18).truncatingRemainder(dividingBy: 360),
                saturation: 0.8,
                lightness: 0.6
            ) else { return }
        }
    }

    // MARK: - Mandala

    /// A mandala: an eight-petalled rose, three rings round it, eight spikes and a solid hub.
    ///
    /// Four separate figures drawn over one another, which is what gives it the layered look. The rose
    /// comes from taking the cosine of four times the angle: that goes positive and negative four times
    /// round the circle, and taking its size regardless of sign doubles it to eight.
    public func spawnMandala(count requested: Int = 3_600) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let outer = 0.42 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        let phase = between(0, 0.7853981633974483)

        func put(radius: Double, angle: Double, hue: Double, lightness: Double = 0.62) -> Bool {
            place(
                centreX + jsCos(angle + phase) * radius,
                centreY + jsSin(angle + phase) * radius,
                hue: hue,
                saturation: 0.82,
                lightness: lightness
            )
        }

        // The petals take a bit over half the budget, filled outward along each spoke so they are solid
        // rather than an outline.
        let petalBudget = Int(Double(total) * 0.55)
        for index in 0 ..< petalBudget {
            let angle = Double(index) / Double(max(1, petalBudget)) * 6.283185307179586
            let rose = abs(jsCos(4 * angle))
            // The `0.55` power fattens the petals near their tips; without it they come to hairline
            // points and the figure reads as a starburst rather than a flower.
            let reach = outer * (0.22 + 0.78 * jsPow(rose, 0.55))
            let steps = 5 + index % 3
            for step in 2 ... steps {
                let radius = reach * Double(step) / Double(steps)
                guard put(radius: radius, angle: angle, hue: rose * 250 + 36) else { return }
            }
        }

        // Three rings, each with more bodies than the last so they read as the same weight of line.
        for ring in 0 ..< 3 {
            let radius = outer * (0.18 + 0.14 * Double(ring))
            let along = 8 * (6 + 4 * ring)
            for step in 0 ..< along {
                let angle = Double(step) / Double(along) * 6.283185307179586 + 0.08 * Double(ring)
                guard put(
                    radius: radius,
                    angle: angle,
                    hue: 54 + 43 * Double(ring),
                    lightness: 0.7
                ) else { return }
            }
        }

        // Eight spikes, each drawn out along one line and back along another a little round from it, so
        // it comes back as a narrow wedge rather than retracing itself.
        for spike in 0 ..< 8 {
            let out = Double(spike) * 0.7853981633974483 - 1.5707963267948966
            let back = out + 0.39269908169872414
            let near = 0.12 * outer
            let far = 0.95 * outer
            for step in 0 ... 18 {
                let through = Double(step) / 18
                let goingOut = through < 0.5
                let radius = goingOut
                    ? near + (far - near) * through * 2
                    : far + (near - far) * (through * 2 - 1)
                guard put(
                    radius: radius,
                    angle: goingOut ? out : back,
                    hue: 306,
                    lightness: 0.72
                ) else { return }
            }
        }

        // And a solid hub, as a diamond of points rather than a disc — it sits under the petals, and a
        // disc there would read as a blot.
        let step = outer * 0.018
        for across in -8 ... 8 {
            for down in -8 ... 8 where abs(across) + abs(down) <= 8 {
                guard place(
                    centreX + Double(across) * step,
                    centreY + Double(down) * step,
                    hue: 18,
                    saturation: 0.7,
                    lightness: 0.78
                ) else { return }
            }
        }
    }

    // MARK: - Snowflakes

    /// Five to eight six-armed snowflakes, with loose fragments scattered between them.
    ///
    /// Each arm is a line of beads with pairs of barbs growing off it at sixty degrees, getting shorter
    /// toward the tip. Six arms because that is how ice crystallises, and the barbs at sixty degrees for
    /// the same reason — it is the one angle that makes the shape read as ice rather than as a star.
    public func spawnSnowflakes(count requested: Int = 3_600) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        var placed = 0
        let span = patternSpan

        /// A patch of hexagonal lattice, which is what the solid core of each flake is made of.
        ///
        /// The reference implementation's version of this overshoots its own nominal radius by about two
        /// thirds, so its flakes arrive larger than asked for and with their edges cut off by whatever is
        /// containing them. The scale here divides by the true furthest distance the lattice reaches.
        func hexCore(_ cx: Double, _ cy: Double, radius: Double, hue: Double) -> Bool {
            let rings = max(2, Int((radius / (0.012 * span)).rounded()))
            // A hexagonal patch: three axes whose sum is nought, so bounding all three bounds the patch.
            var furthest = 1e-6
            for q in -rings ... rings {
                for r in -rings ... rings where abs(-q - r) <= rings {
                    let px = 1.5 * Double(q)
                    let py = 1.7320508075688772 * (Double(r) + Double(q) / 2)
                    furthest = max(furthest, (px * px + py * py).squareRoot())
                }
            }
            let scale = radius / furthest
            for q in -rings ... rings {
                for r in -rings ... rings where abs(-q - r) <= rings {
                    let px = 1.5 * Double(q) * scale
                    let py = 1.7320508075688772 * (Double(r) + Double(q) / 2) * scale
                    guard place(cx + px, cy + py, hue: hue, saturation: 0.35, lightness: 0.86) else {
                        return false
                    }
                    placed += 1
                    if placed >= total { return false }
                }
            }
            return true
        }

        func flake(_ cx: Double, _ cy: Double, radius: Double, turn: Double, hue: Double) -> Bool {
            let perArm = max(10, Int((0.08 * Double(total) / 6).rounded()))
            for arm in 0 ..< 6 {
                let along = turn + Double(arm) * 1.0471975511965976
                for bead in 0 ..< perArm {
                    let through = Double(bead) / Double(max(1, perArm - 1))
                    let reach = through * radius
                    guard place(
                        cx + jsCos(along) * reach,
                        cy + jsSin(along) * reach,
                        hue: (hue + 72 * through).truncatingRemainder(dividingBy: 360),
                        saturation: 0.4,
                        lightness: 0.88
                    ) else { return false }
                    placed += 1
                    if placed >= total { return false }

                    // Barbs, on every other bead past the third, shortening toward the tip.
                    guard bead > 2, bead.isMultiple(of: 2) else { continue }
                    let barbLength = 0.28 * radius * (1 - through)
                    for side in [-1.0, 1.0] {
                        let barbAngle = along + side * 1.0471975511965976
                        for tick in 1 ... 3 {
                            let outward = barbLength * Double(tick) / 3
                            guard place(
                                cx + jsCos(along) * reach + jsCos(barbAngle) * outward,
                                cy + jsSin(along) * reach + jsSin(barbAngle) * outward,
                                hue: (hue + 54).truncatingRemainder(dividingBy: 360),
                                saturation: 0.3,
                                lightness: 0.9
                            ) else { return false }
                            placed += 1
                            if placed >= total { return false }
                        }
                    }
                }
            }
            return hexCore(cx, cy, radius: 0.18 * radius, hue: hue)
        }

        // Placed at set positions rather than at random, so the flakes never overlap into a single blob.
        let sites: [(Double, Double)] = [
            (0.22, 0.28), (0.5, 0.22), (0.78, 0.3), (0.28, 0.68),
            (0.72, 0.66), (0.5, 0.52), (0.18, 0.5), (0.84, 0.5),
        ]
        let flakes = max(5, min(8, total / 700))
        for index in 0 ..< flakes {
            let site = sites[index % sites.count]
            guard flake(
                (site.0 + between(-0.02, 0.02)) * width,
                (site.1 + between(-0.02, 0.02)) * height,
                radius: span * between(0.1, 0.16),
                turn: 0.35 * Double(index),
                hue: 186 + Double(index % 6) * 10
            ) else { return }
        }

        // And loose fragments, which is what makes it read as falling snow rather than as a diagram.
        let shards = max(4, min(10, total / 900))
        for index in 0 ..< shards {
            guard hexCore(
                between(0.12, 0.88) * width,
                between(0.12, 0.88) * height,
                radius: span * between(0.035, 0.06),
                hue: 200 + Double(index % 5) * 8
            ) else { return }
        }
    }

    // MARK: - Tornado

    /// A funnel: narrow and fast at the bottom, wide and slow at the top.
    ///
    /// Only the sideways part of the circular motion is set. That is deliberate rather than an omission:
    /// this is a funnel seen from the side, so the part of the spin coming toward the viewer should not
    /// also move the body up or down the screen.
    public func spawnTornado(count requested: Int = 2_600) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let centreX = width * 0.5
        let span = patternSpan

        for index in 0 ..< total {
            let up = Double(index) / Double(max(1, total - 1))
            // A straight cone: under two percent of the span at the tip, a little under a quarter at
            // the top.
            let radius = (0.018 + 0.22 * up) * span
            // Fourteen radians from bottom to top, which is a bit over two full turns.
            let angle = 14 * up + between(0, 0.4)
            // Spinning faster where it is narrow, which is what a funnel does and what makes it look
            // like one.
            let rate = 2.4 - 1.1 * up

            guard place(
                centreX + jsCos(angle) * radius + between(-0.008, 0.008) * span,
                (0.08 + 0.86 * up) * height + between(-0.01, 0.01) * height,
                velocityX: -jsSin(angle) * rate * radius * 0.02,
                // Rising hardest at the base, where the funnel is tightest.
                velocityY: -0.18 * (1 - up) * 8 + between(-0.4, 0.2),
                hue: ((angle / 6.283185307179586 + up) * 360).truncatingRemainder(dividingBy: 360),
                saturation: 0.5,
                lightness: 0.7
            ) else { return }
        }
    }

    // MARK: - Lightning

    /// A branching bolt.
    ///
    /// The path is walked first, wandering downward and occasionally splitting, and then the bodies are
    /// laid along whatever path came out. Splitting with a probability rather than at set points is what
    /// stops every bolt looking the same, and the branches are shorter and dimmer than the trunk so the
    /// shape reads as one bolt with offshoots rather than as several bolts.
    public func spawnLightning(count requested: Int = 2_000) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        // Where the bolt goes, and how bright each part of it is.
        var path: [(x: Double, y: Double, brightness: Double)] = []
        let span = patternSpan

        func walk(from startX: Double, from startY: Double, heading: Double, step: Double, depth: Int) {
            var x = startX
            var y = startY
            var angle = heading
            // The trunk runs longest; each generation of branch is shorter.
            let segments = 7 + (3 - depth) * 3
            for _ in 0 ..< segments {
                angle += between(-0.55, 0.55)
                x += jsCos(angle) * step
                y += jsSin(angle) * step
                // Stop at the edges rather than wrapping or clamping, which would bunch the bolt up
                // against the side of the world.
                guard y < height * 0.98, x > width * 0.02, x < width * 0.98 else { return }
                path.append((x, y, 1 - 0.22 * Double(depth)))
                // Three in ten rather than the reference implementation's two: at its rate a short bolt
                // often produces no branches at all, and a bolt that does not branch is just a wobbly
                // line.
                if depth < 3, rng.next() < 0.3 {
                    walk(
                        from: x,
                        from: y,
                        heading: angle + between(-0.9, 0.9),
                        step: step * 0.62,
                        depth: depth + 1
                    )
                }
            }
        }

        let bolts = max(1, min(4, total / 1_800))
        for _ in 0 ..< bolts {
            walk(
                from: between(0.22, 0.78) * width,
                from: 0.02 * height,
                // Downward. A quarter turn, because the world's vertical axis grows downward.
                heading: 1.5707963267948966 + between(-0.15, 0.15),
                step: 0.045 * span,
                depth: 0
            )
        }
        guard !path.isEmpty else { return }

        // Every point on the path gets one body, and whatever budget is left is scattered over the path
        // again — so a generous count makes the bolt thicker rather than longer.
        for index in 0 ..< total {
            let point = index < path.count ? path[index] : path[Int(rng.next() * Double(path.count)) % path.count]
            guard place(
                point.x + between(-0.006, 0.006) * span,
                point.y + between(-0.006, 0.006) * span,
                velocityX: between(-0.3, 0.3),
                velocityY: between(-0.2, 1.0),
                hue: 210 + point.brightness * 40,
                saturation: 0.55,
                lightness: 0.6 + point.brightness * 0.35
            ) else { return }
        }
    }

    // MARK: - Aurora

    /// Five wavy curtains of light.
    ///
    /// Each curtain is a vertical band whose sideways position wanders as it goes down, and the five are
    /// offset from one another so the waves do not line up. That offset is the whole effect: five
    /// curtains waving in step read as one wobbling sheet.
    public func spawnAurora(count requested: Int = 4_000) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let curtains = 5
        for index in 0 ..< total {
            let curtain = index % curtains
            let down = Double(index) / Double(total)
            // The five sit at even fractions of the width, each waving by four percent of it.
            let base = 0.12 + 0.18 * Double(curtain)
            let wave = 0.04 * jsSin(9 * down)
            guard place(
                (base + wave) * width + between(-0.01, 0.01) * width,
                (down * 0.92 + 0.04) * height + between(-0.012, 0.012) * height,
                // Drifting sideways, each curtain a little out of step with the next.
                velocityX: 0.08 * jsSin(6 * down + Double(curtain)) * 8,
                velocityY: between(-0.3, 0.3),
                hue: ((Double(curtain) / Double(curtains) + down) * 200 + 100)
                    .truncatingRemainder(dividingBy: 360),
                saturation: 0.75,
                lightness: 0.62
            ) else { return }
        }
    }

    // MARK: - Supernova

    /// A star coming apart: a fast outer shell and a slow lingering core.
    ///
    /// Two populations rather than a spread, which is what gives it a bright expanding ring with a dull
    /// middle instead of a fog that thins out evenly.
    public func spawnSupernova(count requested: Int = 3_200) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let centreX = width * 0.5
        let centreY = height * 0.5
        let span = patternSpan

        for _ in 0 ..< total {
            let angle = between(0, 6.283185307179586)
            // Seven in ten belong to the shell.
            let isShell = rng.next() < 0.7
            let speed = isShell ? between(0.85, 1.35) * 9 : between(0.05, 0.45) * 9
            guard place(
                centreX + between(-0.008, 0.008) * span,
                centreY + between(-0.008, 0.008) * span,
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                hue: isShell ? between(20, 60) : between(270, 330),
                saturation: isShell ? 0.9 : 0.6,
                lightness: isShell ? 0.7 : 0.45
            ) else { return }
        }
    }

    // MARK: - Sierpinski

    /// The Sierpiński triangle, drawn by the chaos game.
    ///
    /// Pick a corner at random, move halfway to it, place a body, repeat. That produces the figure
    /// reliably no matter where it starts, which is the surprising part and the reason it is worth
    /// having as a scene.
    ///
    /// The first two dozen steps are thrown away. Until the point has been folded in a few times it can
    /// be anywhere, including outside the triangle, and those first few would otherwise leave a faint
    /// streak from wherever the walk began to where the figure actually is.
    public func spawnSierpinski(count requested: Int = 3_600) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let span = 0.42 * patternSpan
        let centreX = width * 0.5
        let top = 0.12 * height
        // A proper equilateral triangle: the height is the root of three times the half-width. The
        // reference implementation uses 1.62 instead of 1.732, which makes its triangle about six
        // percent squat — not obviously wrong on its own, and obvious beside a correct one.
        let tall = 1.7320508075688772 * span
        let corners: [(Double, Double)] = [
            (centreX, top),
            (centreX - span, top + tall),
            (centreX + span, top + tall),
        ]

        var x = centreX
        var y = top + tall * 0.5
        for _ in 0 ..< 24 {
            let corner = corners[Int(rng.next() * 3) % 3]
            x = (x + corner.0) * 0.5
            y = (y + corner.1) * 0.5
        }

        for index in 0 ..< total {
            let pick = Int(rng.next() * 3) % 3
            let corner = corners[pick]
            x = (x + corner.0) * 0.5
            y = (y + corner.1) * 0.5
            // Coloured by which corner was chosen, so the three sub-triangles are visibly different —
            // the reference colours by a counter instead, which carries no meaning at all.
            guard place(
                x,
                y,
                hue: 30 + Double(pick) * 110,
                saturation: 0.75,
                lightness: 0.65
            ) else { return }
            _ = index
        }
    }

    // MARK: - Fireworks

    /// Several separate shells, each one colour.
    ///
    /// One colour per shell is what makes them read as separate fireworks rather than as one large
    /// multicoloured burst. It is a single line of code and it is the whole effect.
    public func spawnFireworks(count requested: Int = 2_800) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let shells = max(4, min(14, total / 350))
        let perShell = max(20, total / shells)
        let span = patternSpan

        for _ in 0 ..< shells {
            let originX = between(0.12, 0.88) * width
            let originY = between(0.12, 0.55) * height
            let hue = between(0, 360)
            for _ in 0 ..< perShell {
                let angle = between(0, 6.283185307179586)
                let speed = between(0.25, 1.15) * 5
                guard place(
                    originX + between(-0.004, 0.004) * span,
                    originY + between(-0.004, 0.004) * span,
                    velocityX: jsCos(angle) * speed,
                    velocityY: jsSin(angle) * speed,
                    hue: hue + between(-12, 12),
                    saturation: 0.9,
                    lightness: between(0.55, 0.78)
                ) else { return }
            }
        }
    }

    // MARK: - Magma

    /// Embers rising from the floor.
    public func spawnMagma(count requested: Int = 3_600) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        for _ in 0 ..< total {
            let heat = rng.next()
            guard place(
                between(0.08, 0.92) * width,
                between(0.62, 0.98) * height,
                velocityX: between(-0.6, 0.6),
                // Upward, which is toward smaller numbers.
                velocityY: -between(0.2, 1.1) * 6,
                hue: 8 + heat * 44,
                saturation: 0.95,
                lightness: 0.4 + heat * 0.35
            ) else { return }
        }
    }

    // MARK: - Confetti

    /// A handful of paper thrown in the air.
    public func spawnConfetti(count requested: Int = 3_200) {
        pushUndo()
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        for _ in 0 ..< total {
            guard place(
                between(0.15, 0.85) * width,
                between(0.05, 0.35) * height,
                velocityX: between(-5, 5),
                // Mostly downward, but some still going up — which is what a handful of thrown paper
                // looks like a moment after it leaves the hand.
                velocityY: between(-1.2, 6),
                hue: between(0, 360),
                saturation: 0.9,
                lightness: 0.66
            ) else { return }
        }
    }

    // MARK: - Molecules

    /// Ball-and-stick molecules: benzene rings, water, and a zig-zag chain.
    ///
    /// The only one of these that goes into the object list, because it is bonds — and bonds are springs,
    /// which the swarm does not carry.
    ///
    /// Worth being clear what this is and is not. These are **distances held by springs**, not chemistry:
    /// nothing here knows what an electron is, nothing reacts, and the shapes are held only because each
    /// pair of joined atoms is trying to stay a set distance apart. The reference implementation's own
    /// notes are honest about the same thing.
    ///
    /// One correction. It places a water molecule's two hydrogens at the bond angle measured *from the
    /// upright*, which puts the angle between them at seventy-five degrees rather than the hundred and
    /// four and a half it names. Here the angle between them is the angle.
    public func spawnMolecules(count requested: Int = 900) {
        pushUndo()
        let span = patternSpan
        let ringSize = 0.055 * span
        let waterSize = 0.04 * span
        var budget = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard budget > 0 else { return }

        func atom(
            _ x: Double,
            _ y: Double,
            radius: Double,
            mass: Double,
            color: PackedColor
        ) -> Int? {
            guard budget > 0 else { return nil }
            budget -= 1
            // The returned index rather than the list's length, because adding a body when the field is
            // already full evicts the oldest one — so the list does not always grow, and a spring built
            // from its length would point at the wrong body.
            return addParticle(
                x: x, y: y,
                velocityX: between(-0.2, 0.2), velocityY: between(-0.2, 0.2),
                radius: radius, mass: mass, charge: 0, color: color
            )
        }

        func bond(_ a: Int?, _ b: Int?, rest: Double, stiffness: Double) {
            guard let a, let b else { return }
            springs.append(Spring(a: a, b: b, rest: rest, k: stiffness))
        }

        let carbon = PackedColor(r: 0x3F, g: 0x4A, b: 0x5A)
        let hydrogen = PackedColor(r: 0xE8, g: 0xEE, b: 0xF6)
        let oxygen = PackedColor(r: 0xE0, g: 0x4F, b: 0x4F)

        /// A benzene ring: six carbons in a hexagon, each with a hydrogen hanging off it.
        ///
        /// The rest length between neighbouring carbons is the ring's own radius, which is exactly right
        /// — in a regular hexagon the distance between neighbouring corners equals the distance from the
        /// centre to a corner. That is not an approximation, it is a property of hexagons.
        func benzene(_ cx: Double, _ cy: Double, size: Double) {
            var ring: [Int?] = []
            for step in 0 ..< 6 {
                let angle = Double(step) / 6 * 6.283185307179586 - 1.5707963267948966
                ring.append(atom(
                    cx + jsCos(angle) * size,
                    cy + jsSin(angle) * size,
                    radius: 3.2, mass: 1.6, color: carbon
                ))
            }
            for step in 0 ..< 6 {
                bond(ring[step], ring[(step + 1) % 6], rest: size, stiffness: 0.62)
                let angle = Double(step) / 6 * 6.283185307179586 - 1.5707963267948966
                let attached = atom(
                    cx + jsCos(angle) * size * 1.55,
                    cy + jsSin(angle) * size * 1.55,
                    radius: 2, mass: 0.45, color: hydrogen
                )
                bond(ring[step], attached, rest: size * 0.55, stiffness: 0.5)
            }
        }

        /// Water: one oxygen with two hydrogens, at the real bond angle between them.
        func water(_ cx: Double, _ cy: Double, size: Double) {
            let centre = atom(cx, cy, radius: 3.6, mass: 1.8, color: oxygen)
            // A hundred and four and a half degrees, in radians, split either side of the upright — so
            // the angle *between the two hydrogens* is the bond angle, which is what the number means.
            let half = 1.8238691004641712 / 2
            for side in [-1.0, 1.0] {
                let angle = -1.5707963267948966 + side * half
                let attached = atom(
                    cx + jsCos(angle) * size,
                    cy + jsSin(angle) * size,
                    radius: 2, mass: 0.4, color: hydrogen
                )
                bond(centre, attached, rest: size, stiffness: 0.7)
            }
        }

        /// A zig-zag chain, the shape a simple hydrocarbon takes.
        ///
        /// The rest length is a little longer than the spacing along the chain, because the zig-zag means
        /// the real distance between neighbours is the diagonal — the root of one plus the offset
        /// squared, which for an offset of thirty-five hundredths is a fraction under 1.06.
        func chain(_ startX: Double, _ startY: Double, length: Int, size: Double, heading: Double) {
            var previous: Int?
            for step in 0 ..< length {
                let alongX = startX + jsCos(heading) * size * Double(step)
                let alongY = startY + jsSin(heading) * size * Double(step)
                let offset = step.isMultiple(of: 2) ? 0.0 : 0.35 * size
                let across = heading + 1.5707963267948966
                let here = atom(
                    alongX + jsCos(across) * offset,
                    alongY + jsSin(across) * offset,
                    radius: 3, mass: step.isMultiple(of: 3) ? 1.5 : 1, color: carbon
                )
                bond(previous, here, rest: size * 1.0595, stiffness: 0.55)
                previous = here
            }
        }

        // Set positions rather than random ones, so the molecules sit apart and can be told from one
        // another. A scatter would overlap them into a single knot of springs.
        let ringSites: [(Double, Double)] = [
            (0.22, 0.32), (0.5, 0.28), (0.78, 0.34), (0.3, 0.68), (0.7, 0.7),
        ]
        let waterSites: [(Double, Double)] = [
            (0.18, 0.52), (0.86, 0.55), (0.42, 0.82), (0.62, 0.18),
        ]
        for site in ringSites where budget > 12 {
            benzene(site.0 * width, site.1 * height, size: ringSize)
        }
        if budget > 12 {
            chain(
                0.5 * width - 0.16 * span,
                0.55 * height,
                length: 9,
                size: 0.032 * span,
                heading: 0.15
            )
        }
        for site in waterSites where budget > 3 {
            water(site.0 * width, site.1 * height, size: waterSize)
        }
        // And whatever budget is left over, filled with more of the same in random places.
        var guardCount = 0
        while budget > 12, guardCount < 400 {
            guardCount += 1
            if rng.next() < 0.55 {
                benzene(
                    between(0.1, 0.9) * width,
                    between(0.1, 0.9) * height,
                    size: ringSize * between(0.7, 1.05)
                )
            } else {
                water(
                    between(0.1, 0.9) * width,
                    between(0.1, 0.9) * height,
                    size: waterSize * between(0.8, 1.2)
                )
            }
        }
    }
}
