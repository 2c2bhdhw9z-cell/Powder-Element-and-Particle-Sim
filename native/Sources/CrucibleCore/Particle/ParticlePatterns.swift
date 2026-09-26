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
    ///
    /// Of the region arrangements are laid out in rather than of the whole world, so an arrangement chosen
    /// after zooming out is its usual size with room round it. See `ParticleLayout.swift`.
    var patternSpan: Double { min(layoutWidth, layoutHeight) }

    /// How many bodies a pattern may add.
    var patternRoom: Int {
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
        lightness: Double = 0.62,
        life: Double = -1,
        role: Swarm.Role = [],
        home: Swarm.Home? = nil
    ) -> Bool {
        swarm.append(
            x: x,
            y: y,
            velocityX: velocityX,
            velocityY: velocityY,
            color: PackedColor(hue: hue, saturation: saturation, lightness: lightness).packedRGBA,
            budget: maxParticles - particles.count,
            life: life,
            role: role,
            home: home
        )
    }

    /// Puts one body into the swarm that holds its place in a shape, turning about a point.
    ///
    /// The body starts exactly where it belongs and already moving the way its place is moving, so a turning
    /// shape turns from the first moment instead of jolting as every body catches up at once.
    ///
    /// - Parameters:
    ///   - aboutX: what the shape turns about.
    ///   - aboutY: see above.
    ///   - spin: how far it turns each moment, in radians. Nought holds still.
    ///   - squash: how much of the circle's height survives. Nought turns the circle into a line, which is how
    ///     a funnel looks from the side.
    @discardableResult
    func placeHeld(
        _ x: Double,
        _ y: Double,
        aboutX: Double,
        aboutY: Double,
        spin: Double = 0,
        squash: Double = 1,
        stiffness: Double = Swarm.holdStiffness,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62,
        life: Double = -1
    ) -> Bool {
        let dx = x - aboutX
        let dy = squash != 0 ? (y - aboutY) / squash : 0
        let radius = (dx * dx + dy * dy).squareRoot()
        let angle = radius > 0 ? JS.atan2(dy, dx) : 0
        let home = Swarm.Home(
            anchorX: aboutX,
            anchorY: squash != 0 ? aboutY : y,
            radius: radius,
            angle: angle,
            spin: spin,
            squash: squash,
            stiffness: stiffness
        )
        let placed = home.point
        return swarm.append(
            x: placed.x,
            y: placed.y,
            velocityX: -jsSin(angle) * radius * spin,
            velocityY: jsCos(angle) * radius * spin * squash,
            color: PackedColor(hue: hue, saturation: saturation, lightness: lightness).packedRGBA,
            budget: maxParticles - particles.count,
            life: life,
            role: .holds,
            home: home
        )
    }

    /// A number between the two given, from the field's own stream.
    func between(_ low: Double, _ high: Double) -> Double {
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
        beginScene("sunflower", gravityY: 0)
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
            // Turning slowly, all together, so the head reads as a disc rather than a printed pattern —
            // and all together rather than faster further out, because a head that turned faster at its
            // rim would wind its own spiral up and lose it within a minute. Each seed holds its place, so
            // a finger can stir the head and it settles back.
            guard placeHeld(
                x,
                y,
                aboutX: centreX,
                aboutY: centreY,
                spin: 0.0016,
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
        beginScene("mandala", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let outer = 0.42 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        let phase = between(0, 0.7853981633974483)

        // Turning slowly as one piece, the whole figure held in shape.
        let spin = 0.0012
        func put(radius: Double, angle: Double, hue: Double, lightness: Double = 0.62) -> Bool {
            placeHeld(
                centreX + jsCos(angle + phase) * radius,
                centreY + jsSin(angle + phase) * radius,
                aboutX: centreX,
                aboutY: centreY,
                spin: spin,
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
                guard placeHeld(
                    centreX + Double(across) * step,
                    centreY + Double(down) * step,
                    aboutX: centreX,
                    aboutY: centreY,
                    spin: spin,
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
        beginScene("snowflakes", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        var placed = 0
        let span = patternSpan

        /// A patch of hexagonal lattice, which is what the solid core of each flake is made of.
        ///
        /// The reference implementation's version of this overshoots its own nominal radius by about two
        /// thirds, so its flakes arrive larger than asked for and with their edges cut off by whatever is
        /// containing them. The scale here divides by the true furthest distance the lattice reaches.
        func hexCore(_ cx: Double, _ cy: Double, radius: Double, hue: Double, spin: Double) -> Bool {
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
                    guard placeHeld(
                        cx + px, cy + py, aboutX: cx, aboutY: cy, spin: spin,
                        hue: hue, saturation: 0.35, lightness: 0.86
                    ) else {
                        return false
                    }
                    placed += 1
                    if placed >= total { return false }
                }
            }
            return true
        }

        func flake(_ cx: Double, _ cy: Double, radius: Double, turn: Double, hue: Double, spin: Double) -> Bool {
            let perArm = max(10, Int((0.08 * Double(total) / 6).rounded()))
            for arm in 0 ..< 6 {
                let along = turn + Double(arm) * 1.0471975511965976
                for bead in 0 ..< perArm {
                    let through = Double(bead) / Double(max(1, perArm - 1))
                    let reach = through * radius
                    guard placeHeld(
                        cx + jsCos(along) * reach,
                        cy + jsSin(along) * reach,
                        aboutX: cx,
                        aboutY: cy,
                        spin: spin,
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
                            guard placeHeld(
                                cx + jsCos(along) * reach + jsCos(barbAngle) * outward,
                                cy + jsSin(along) * reach + jsSin(barbAngle) * outward,
                                aboutX: cx,
                                aboutY: cy,
                                spin: spin,
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
            return hexCore(cx, cy, radius: 0.18 * radius, hue: hue, spin: spin)
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
                across(site.0 + between(-0.02, 0.02)),
                down(site.1 + between(-0.02, 0.02)),
                radius: span * between(0.1, 0.16),
                turn: 0.35 * Double(index),
                hue: 186 + Double(index % 6) * 10,
                // Each flake turning on its own, alternate ones the other way, so the field reads as snow
                // rather than as one rigid diagram.
                spin: (index.isMultiple(of: 2) ? 1 : -1) * between(0.002, 0.005)
            ) else { return }
        }

        // And loose fragments, which is what makes it read as falling snow rather than as a diagram.
        let shards = max(4, min(10, total / 900))
        for index in 0 ..< shards {
            guard hexCore(
                across(between(0.12, 0.88)),
                down(between(0.12, 0.88)),
                radius: span * between(0.035, 0.06),
                hue: 200 + Double(index % 5) * 8,
                spin: between(-0.006, 0.006)
            ) else { return }
        }
    }

    // MARK: - Tornado

    /// A funnel: narrow and fast at the bottom, wide and slow at the top, and turning.
    ///
    /// Seen from the side, so each body swings from one side of the funnel to the other rather than going
    /// round in a circle on the screen — the part of the spin coming toward the viewer should not move a body
    /// up or down. Every body holds its place in the funnel and that place goes round, faster where the
    /// funnel is narrow, which is what a funnel does and what makes it read as one.
    ///
    /// It used to be laid out once with a push sideways and then left alone, so it drifted apart and slid to
    /// the floor within a couple of seconds. A tornado that does not turn is not a tornado.
    public func spawnTornado(count requested: Int = 2_600) {
        beginScene("tornado", gravityY: 0)
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
            // Round once every second and a half at the tip, every five seconds or so at the top.
            let rate = 0.07 - 0.05 * up
            // Standing on the world's floor, the screen's height tall.
            let y = aboveFloor(0.94 - 0.86 * up) + between(-0.01, 0.01) * layoutHeight
            let home = Swarm.Home(
                anchorX: centreX + between(-0.008, 0.008) * span,
                anchorY: y,
                radius: radius,
                angle: angle,
                spin: rate,
                squash: 0,
                // Stiff, so each body keeps up with a place that is going round several times a second.
                stiffness: 0.12
            )
            let at = home.point
            guard place(
                at.x,
                at.y,
                velocityX: -jsSin(angle) * radius * rate,
                velocityY: 0,
                hue: ((angle / 6.283185307179586 + up) * 360).truncatingRemainder(dividingBy: 360),
                saturation: 0.5,
                lightness: 0.7,
                role: .holds,
                home: home
            ) else { return }
        }
    }

    // MARK: - Lightning

    /// A storm: branching bolts that flicker out, and strike again.
    ///
    /// It used to be a single bolt laid out once, which then fell to the floor and lay there as a line of
    /// dots. Now each bolt holds its shape while it lasts, fades within a second, and the storm strikes again
    /// every second and a half or so — see `stepArrangement`.
    public func spawnLightning(count requested: Int = 2_000) {
        beginScene("lightning", gravityY: 0)
        strikeLightning(count: requested)
    }

    /// One strike: a branching bolt, drawn in bodies that last a moment and then go.
    ///
    /// The path is walked first, wandering downward and occasionally splitting, and then the bodies are
    /// laid along whatever path came out. Splitting with a probability rather than at set points is what
    /// stops every bolt looking the same, and the branches are shorter and dimmer than the trunk so the
    /// shape reads as one bolt with offshoots rather than as several bolts.
    func strikeLightning(count requested: Int) {
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
                from: across(between(0.22, 0.78)),
                from: belowCeiling(0.02),
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
            let x = point.x + between(-0.006, 0.006) * span
            let y = point.y + between(-0.006, 0.006) * span
            guard place(
                x,
                y,
                velocityX: between(-0.3, 0.3),
                velocityY: between(-0.2, 1.0),
                hue: 210 + point.brightness * 40,
                saturation: 0.55,
                lightness: 0.6 + point.brightness * 0.35,
                // Most of a bolt is gone within half a second; the brightest parts linger a little longer,
                // which is what makes it flicker out rather than switch off.
                life: between(14, 34) + point.brightness * 26,
                role: .holds,
                home: Swarm.Home(anchorX: x, anchorY: y, stiffness: 0.05)
            ) else { return }
        }
    }

    // MARK: - Aurora

    /// Five curtains of light, rippling.
    ///
    /// Each curtain is a vertical band whose sideways position wanders as it goes down, and the five are
    /// offset from one another so the waves do not line up. That offset is the whole effect: five
    /// curtains waving in step read as one wobbling sheet.
    ///
    /// Each body sways from side to side about its place in the curtain, a little behind the one above it,
    /// so a ripple runs down every curtain. It used to be laid out once and then left to drift and fall.
    public func spawnAurora(count requested: Int = 4_000) {
        beginScene("aurora", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let curtains = 5
        for index in 0 ..< total {
            let curtain = index % curtains
            let down = Double(index) / Double(total)
            // The five sit at even fractions of the width, each waving by four percent of it.
            let base = 0.12 + 0.18 * Double(curtain)
            let wave = 0.04 * jsSin(9 * down)
            let anchorX = across(base + wave) + between(-0.01, 0.01) * layoutWidth
            let anchorY = belowCeiling(down * 0.92 + 0.04) + between(-0.012, 0.012) * layoutHeight
            let home = Swarm.Home(
                anchorX: anchorX,
                anchorY: anchorY,
                radius: 0.018 * layoutWidth,
                // Staggered down the curtain, so the sway travels as a ripple.
                angle: 6 * down + Double(curtain) * 1.3,
                spin: 0.025,
                squash: 0,
                stiffness: 0.05
            )
            let at = home.point
            guard place(
                at.x,
                at.y,
                hue: ((Double(curtain) / Double(curtains) + down) * 200 + 100)
                    .truncatingRemainder(dividingBy: 360),
                saturation: 0.75,
                lightness: 0.62,
                role: .holds,
                home: home
            ) else { return }
        }
    }

    // MARK: - Supernova

    /// A star coming apart: a fast outer shell and a slow lingering core.
    ///
    /// Two populations rather than a spread, which is what gives it a bright expanding ring with a dull
    /// middle instead of a fog that thins out evenly.
    ///
    /// The shell fades as it goes, and the core settles into a slowly turning cloud — the remnant. It used to
    /// end as four thousand dots bouncing round the edges of the field for ever, which is what a supernova
    /// looks like for about a second and then not at all.
    public func spawnSupernova(count requested: Int = 3_200) {
        beginScene("supernova", gravityY: 0)
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
            let x = centreX + between(-0.008, 0.008) * span
            let y = centreY + between(-0.008, 0.008) * span
            if isShell {
                guard place(
                    x,
                    y,
                    velocityX: jsCos(angle) * speed,
                    velocityY: jsSin(angle) * speed,
                    hue: between(20, 60),
                    saturation: 0.9,
                    lightness: 0.7,
                    life: between(110, 200)
                ) else { return }
            } else {
                // Where it will come to rest in the remnant: thrown out to there, then held, turning slowly.
                let settle = between(0.03, 0.16) * span
                let home = Swarm.Home(
                    anchorX: centreX,
                    anchorY: centreY,
                    radius: settle,
                    angle: angle,
                    spin: 0.0025 * (0.2 * span / max(settle, 1)).squareRoot(),
                    squash: 1,
                    stiffness: 0.002
                )
                guard place(
                    x,
                    y,
                    velocityX: jsCos(angle) * speed,
                    velocityY: jsSin(angle) * speed,
                    hue: between(270, 330),
                    saturation: 0.6,
                    lightness: 0.45,
                    role: .holds,
                    home: home
                ) else { return }
            }
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
    ///
    /// Every body holds its place, and the whole triangle turns very slowly about its middle.
    public func spawnSierpinski(count requested: Int = 3_600) {
        beginScene("sierpinski", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let span = 0.42 * patternSpan
        let centreX = width * 0.5
        // A proper equilateral triangle: the height is the root of three times the half-width. The
        // reference implementation uses 1.62 instead of 1.732, which makes its triangle about six
        // percent squat — not obviously wrong on its own, and obvious beside a correct one.
        let tall = 1.7320508075688772 * span
        // Centred on the field rather than hung from a fixed fraction of the top, so it turns about its own
        // middle and stays on screen whichever way the phone is held.
        let top = height * 0.5 - tall * 2 / 3
        let corners: [(Double, Double)] = [
            (centreX, top),
            (centreX - span, top + tall),
            (centreX + span, top + tall),
        ]
        let middleY = top + tall * 2 / 3

        var x = centreX
        var y = top + tall * 0.5
        for _ in 0 ..< 24 {
            let corner = corners[Int(rng.next() * 3) % 3]
            x = (x + corner.0) * 0.5
            y = (y + corner.1) * 0.5
        }

        for _ in 0 ..< total {
            let pick = Int(rng.next() * 3) % 3
            let corner = corners[pick]
            x = (x + corner.0) * 0.5
            y = (y + corner.1) * 0.5
            // Coloured by which corner was chosen, so the three sub-triangles are visibly different —
            // the reference colours by a counter instead, which carries no meaning at all.
            guard placeHeld(
                x,
                y,
                aboutX: centreX,
                aboutY: middleY,
                spin: 0.0008,
                hue: 30 + Double(pick) * 110,
                saturation: 0.75,
                lightness: 0.65
            ) else { return }
        }
    }

    // MARK: - Fireworks

    /// A fireworks display: several shells at once, and more going up.
    ///
    /// One colour per shell is what makes them read as separate fireworks rather than as one large
    /// multicoloured burst. It is a single line of code and it is the whole effect.
    ///
    /// Each spark falls and fades, and a new shell bursts every half second or so — see
    /// `stepArrangement`. It used to be one volley, after which three thousand sparks lay bouncing on the
    /// floor for ever.
    public func spawnFireworks(count requested: Int = 2_800) {
        beginScene("fireworks", gravityY: 0.05)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let shells = max(4, min(14, total / 350))
        let perShell = max(20, total / shells)
        for _ in 0 ..< shells {
            launchShell(count: perShell)
        }
    }

    /// One shell bursting, somewhere in the upper half of the sky.
    func launchShell(count requested: Int) {
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let span = patternSpan
        let originX = across(between(0.12, 0.88))
        let originY = belowCeiling(between(0.12, 0.55))
        let hue = between(0, 360)
        for _ in 0 ..< total {
            let angle = between(0, 6.283185307179586)
            let speed = between(0.25, 1.15) * 5
            guard place(
                originX + between(-0.004, 0.004) * span,
                originY + between(-0.004, 0.004) * span,
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                hue: hue + between(-12, 12),
                saturation: 0.9,
                lightness: between(0.55, 0.78),
                life: between(70, 140)
            ) else { return }
        }
    }

    // MARK: - Magma

    /// A molten pool churning at the bottom of the field, throwing embers up out of it.
    ///
    /// It used to be three thousand embers thrown upward that fell straight back and lay on the floor for
    /// ever — which is not magma, it is orange sand. The pool now holds its level and heaves from side to
    /// side in slow waves, and three vents along it keep throwing up embers that arc, fade and are gone.
    public func spawnMagma(count requested: Int = 3_600) {
        beginScene("magma", gravityY: 0.05)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        for _ in 0 ..< total {
            let heat = rng.next()
            let x = across(between(0.04, 0.96))
            let y = aboveFloor(between(0.8, 0.985))
            let home = Swarm.Home(
                anchorX: x,
                anchorY: y,
                radius: between(0.01, 0.03) * patternSpan,
                // The phase follows the position across, so the heave travels as a wave along the pool.
                angle: (x - layoutLeft) / max(1, layoutWidth) * 9 + between(0, 0.6),
                spin: 0.018,
                squash: 0.35,
                stiffness: 0.03
            )
            let at = home.point
            guard place(
                at.x,
                at.y,
                // The hottest near the surface, darkest at the bottom.
                hue: 4 + heat * 36,
                saturation: 0.95,
                lightness: 0.3 + heat * 0.32,
                role: .holds,
                home: home
            ) else { return }
        }

        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5,
            atFractionY: 0.8,
            direction: -1.5707963267948966,
            rate: 45,
            spread: 0.45,
            speed: 5,
            speedVariation: 0.4,
            lifespan: 90,
            weight: 0.6,
            weightVariation: 0.3,
            hue: 28
        )
        for share in [0.22, 0.52, 0.8] {
            addEmitter(atX: across(share), y: aboveFloor(0.8))
        }
    }

    // MARK: - Confetti

    /// Paper thrown in the air, fluttering down, and more of it still coming.
    ///
    /// Falls gently rather than at the speed of a stone, and a light wind makes it flutter on the way down.
    /// It used to drop straight to the floor and pile up there for good, which is what confetti does a minute
    /// after the party. Each piece now lasts a while and then goes, and three sources across the top keep
    /// more coming.
    public func spawnConfetti(count requested: Int = 3_200) {
        beginScene("confetti", gravityY: 0.025)
        storedFlowEnabled = true
        storedFlowSettings = SwarmFlow.Settings(strength: 0.3, scale: max(60, patternSpan * 0.2), drift: 0.15)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        for _ in 0 ..< total {
            guard place(
                across(between(0.1, 0.9)),
                belowCeiling(between(0.03, 0.35)),
                velocityX: between(-3, 3),
                // Mostly downward, but some still going up — which is what a handful of thrown paper
                // looks like a moment after it leaves the hand.
                velocityY: between(-1.2, 3),
                hue: between(0, 360),
                saturation: 0.9,
                lightness: 0.66,
                life: between(600, 1_100)
            ) else { return }
        }

        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5,
            atFractionY: 0.02,
            direction: 1.5707963267948966,
            rate: 30,
            spread: 1.2,
            speed: 1.2,
            speedVariation: 0.6,
            lifespan: 1_000,
            weight: 1,
            weightVariation: 0,
            hue: -1
        )
        for share in [0.2, 0.5, 0.8] {
            addEmitter(atX: across(share), y: belowCeiling(0.02))
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
        beginScene("molecules", gravityY: 0)
        addMolecules(count: requested, laidOut: true)
    }

    /// Adds molecules to whatever is there.
    ///
    /// - Parameter laidOut: whether to use the set places first. The scene does, so its molecules sit apart
    ///   and can be told from one another; adding more afterwards puts them wherever there is room.
    func addMolecules(count requested: Int, laidOut: Bool) {
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
        for site in ringSites where laidOut && budget > 12 {
            benzene(across(site.0), down(site.1), size: ringSize)
        }
        if laidOut, budget > 12 {
            chain(
                0.5 * width - 0.16 * span,
                down(0.55),
                length: 9,
                size: 0.032 * span,
                heading: 0.15
            )
        }
        for site in waterSites where laidOut && budget > 3 {
            water(across(site.0), down(site.1), size: waterSize)
        }
        // And whatever budget is left over, filled with more of the same in random places.
        var guardCount = 0
        while budget > 12, guardCount < 400 {
            guardCount += 1
            if rng.next() < 0.55 {
                benzene(
                    across(between(0.1, 0.9)),
                    down(between(0.1, 0.9)),
                    size: ringSize * between(0.7, 1.05)
                )
            } else {
                water(
                    across(between(0.1, 0.9)),
                    down(between(0.1, 0.9)),
                    size: waterSize * between(0.8, 1.2)
                )
            }
        }
    }
}


// MARK: - The last four from the reference

/// The scenes the read documented and the first pass did not build.
///
/// Two of them — fire and smoke — are continuous rather than arrangements: what makes a fire a fire is that
/// it keeps burning. So they place a *source* as well as a body of particles, which is why they had to wait
/// for sources to exist. See the gap audit in `HELION-MERGE.md`.
extension ParticleEngine {
    /// A tilted ring.
    ///
    /// The smallest of the four and the one that shows off the camera's tilt: a ring seen from straight on is
    /// a circle, and leaning the plane over turns it into a proper ellipse with the near side drawn larger.
    public func spawnRing(count requested: Int = 3_200) {
        beginScene("ring", gravityY: 0)
        let total = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard total > 0 else { return }

        let radius = 0.32 * patternSpan
        let band = 0.07 * radius
        let centreX = width * 0.5
        let centreY = height * 0.5
        // Squashed, so it already reads as a ring seen at an angle before the camera is touched at all.
        let squash = 0.86

        for index in 0 ..< total {
            // One body per slice of the circle with a little jitter inside its own slice, rather than a free
            // scatter — a scatter leaves visible gaps and clumps, and a ring is a thing whose evenness is the
            // whole of its appeal.
            let around = (Double(index) + between(0, 1)) / Double(total) * 6.283185307179586
            let outward = radius + between(-band, band)
            // Circling, every body holding its place in the band — so it goes round for as long as it is
            // left rather than drifting off its orbit and sliding to the floor, which is what it used to do.
            guard placeHeld(
                centreX + jsCos(around) * outward,
                centreY + jsSin(around) * outward * squash,
                aboutX: centreX,
                aboutY: centreY,
                spin: 0.004,
                squash: squash,
                stiffness: 0.01,
                hue: (around / 6.283185307179586 * 360).truncatingRemainder(dividingBy: 360),
                saturation: 0.8,
                lightness: 0.64
            ) else { return }
        }
    }

    /// A standing pool of water with something pouring into it.
    ///
    /// Switches the fluid on, because without it this is a rectangle of dots. It is also the one scene whose
    /// spacing has a right answer: the bodies are laid out at exactly the spacing the fluid is set to keep,
    /// so the pool starts settled instead of exploding outward on the first moment.
    ///
    /// Laid out in a honeycomb rather than on a square grid. A square grid at rest spacing is unstable — every
    /// body has four neighbours at the spacing and four more at the diagonal, so the fluid immediately
    /// rearranges it into a honeycomb anyway, with a visible shudder. Starting where it wants to be skips that.
    public func spawnWaterPool(count requested: Int = 6_000) {
        beginScene("water", gravityY: 0.35)
        let total = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard total > 0 else { return }

        fluidEnabled = true

        let spacing = (1 / max(1e-6, fluidSettings.sanitized.restDensity)).squareRoot()
        // Four fifths of the budget in the pool, the rest falling into it.
        let poolBudget = Int(Double(total) * 0.8)

        let left = across(0.08)
        let right = across(0.92)
        let bottom = aboveFloor(0.96)
        let top = aboveFloor(0.52)
        var placed = 0
        var y = bottom
        var row = 0
        while y > top, placed < poolBudget {
            // Odd rows offset by half a spacing, and rows themselves separated by the height of an
            // equilateral triangle — which is what makes it a honeycomb rather than bricks.
            let offset = row.isMultiple(of: 2) ? 0 : spacing * 0.5
            var x = left + offset
            while x < right, placed < poolBudget {
                guard place(
                    x + between(-spacing * 0.08, spacing * 0.08),
                    y + between(-spacing * 0.08, spacing * 0.08),
                    velocityX: between(-0.05, 0.05),
                    velocityY: between(-0.05, 0.05),
                    hue: 198 + between(-6, 6),
                    saturation: 0.72,
                    lightness: 0.55
                ) else { return }
                placed += 1
                x += spacing
            }
            y -= spacing * 0.866_025_403_784_438_6
            row += 1
        }

        // And an inlet pouring in, which is what makes it a scene rather than a still life.
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5,
            atFractionY: 0.06,
            direction: 1.5707963267948966,
            rate: 240,
            spread: 0.12,
            speed: 2.4,
            speedVariation: 0.25,
            // Twenty seconds each. Poured for ever, the inlet used to fill the tank and then the rest of the
            // field, and the fluid got slower the fuller it was; with a lifetime the pool reaches a level.
            lifespan: 1_200,
            weight: 1,
            weightVariation: 0,
            hue: 196
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.06))
    }

    /// A fire: a column of embers rising from the floor, and a source keeping it going.
    ///
    /// The embers are given lifetimes, which is what makes a flame look like a flame — a body that rises
    /// forever is a jet, and a body that fades out part of the way up is a flame. That needed the crowd to
    /// carry lifetimes at all, which until now it did not.
    public func spawnFire(count requested: Int = 2_400) {
        // Upward, so gravity has to point the other way. Fire rises because it is hotter than the air round
        // it, and the cheapest honest way to say that here is negative gravity.
        beginScene("fire", gravityY: -0.22)
        let total = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard total > 0 else { return }

        let columnWidth = 0.18 * layoutWidth
        for _ in 0 ..< total {
            let heat = rng.next()
            let life = between(30, 110)
            guard placeMortal(
                width * 0.5 + between(-columnWidth, columnWidth),
                aboveFloor(between(0.78, 0.98)),
                velocityX: between(-0.7, 0.7),
                velocityY: -between(1.2, 3.4),
                life: life,
                // Hottest at the bottom, cooling as it goes: deep orange through to pale yellow.
                hue: 8 + heat * 44,
                saturation: 0.96,
                lightness: 0.46 + heat * 0.3
            ) else { return }
        }

        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5,
            atFractionY: 0.95,
            // A quarter turn the other way is straight up.
            direction: -1.5707963267948966,
            rate: 420,
            spread: 0.42,
            speed: 2.6,
            speedVariation: 0.45,
            lifespan: 80,
            weight: 0.6,
            weightVariation: 0.3,
            hue: 24
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.95))
    }

    /// Smoke: slower, wider and lighter than fire, and lasting far longer.
    public func spawnSmoke(count requested: Int = 2_400) {
        beginScene("smoke", gravityY: -0.1)
        let total = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard total > 0 else { return }

        let columnWidth = 0.12 * layoutWidth
        for _ in 0 ..< total {
            guard placeMortal(
                width * 0.5 + between(-columnWidth, columnWidth),
                aboveFloor(between(0.72, 0.96)),
                velocityX: between(-0.35, 0.35),
                velocityY: -between(0.4, 1.2),
                life: between(140, 320),
                // Barely coloured at all. Smoke that is a colour reads as gas; smoke that is nearly grey
                // reads as smoke.
                hue: 220 + between(-20, 20),
                saturation: 0.12,
                lightness: 0.34 + rng.next() * 0.22
            ) else { return }
        }

        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5,
            atFractionY: 0.94,
            direction: -1.5707963267948966,
            rate: 180,
            spread: 0.62,
            speed: 1.1,
            speedVariation: 0.5,
            lifespan: 240,
            weight: 0.3,
            weightVariation: 0.4,
            hue: 222
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.94))
    }

    /// Puts one body into the crowd with a lifetime, and says whether to keep going.
    @discardableResult
    private func placeMortal(
        _ x: Double,
        _ y: Double,
        velocityX: Double,
        velocityY: Double,
        life: Double,
        hue: Double,
        saturation: Double,
        lightness: Double
    ) -> Bool {
        swarm.append(
            x: x,
            y: y,
            velocityX: velocityX,
            velocityY: velocityY,
            color: PackedColor(hue: hue, saturation: saturation, lightness: lightness).packedRGBA,
            budget: maxParticles - particles.count,
            mass: 1,
            life: life
        )
    }
}
