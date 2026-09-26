import Foundation
import Testing

@testable import CrucibleCore

/// The wind, and forces somebody writes themselves.
struct SwarmFlowTests {
    private func swarm(_ points: [(Double, Double)]) -> Swarm {
        let result = Swarm()
        var rng = Mulberry32(seed: 1)
        result.spawn(
            count: points.count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 40_000,
            rng: &rng
        )
        for (index, point) in points.enumerated() {
            result.positions[index * 2] = Float(point.0)
            result.positions[index * 2 + 1] = Float(point.1)
            result.velocities[index * 2] = 0
            result.velocities[index * 2 + 1] = 0
        }
        return result
    }

    private func grid(_ spacing: Double) -> [(Double, Double)] {
        var points: [(Double, Double)] = []
        var y = spacing
        while y < 700 {
            var x = spacing
            while x < 400 {
                points.append((x, y))
                x += spacing
            }
            y += spacing
        }
        return points
    }

    // MARK: - The wind

    @Test("The same place gives the same flow every time")
    func flowIsRepeatable() {
        // Nothing is stored, so this is only true if the whole thing is a fixed function of where you
        // ask. It is what lets the wind fill a world of any size without remembering anything.
        for point in [(0.3, 1.7), (-4.2, 9.9), (0.0, 0.0), (137.5, 42.25)] {
            let first = SwarmFlow.curl(atX: point.0, y: point.1, time: 0.75)
            for _ in 0 ..< 4 {
                let again = SwarmFlow.curl(atX: point.0, y: point.1, time: 0.75)
                #expect(again.x == first.x)
                #expect(again.y == first.y)
            }
        }
    }

    @Test("Nothing can pile up: as much flows out of anywhere as flows in")
    func flowHasNoSourcesOrSinks() {
        // This is the whole reason for taking a curl rather than a plain varying direction. A field with
        // places where more flows in than out collects the crowd into blobs within a few seconds, which
        // reads as clumping rather than as flow.
        //
        // Divergence is how much the sideways flow changes sideways plus how much the vertical flow changes
        // vertically, and for a curl those two are equal and opposite. So the test compares their *sum*
        // against their individual sizes: if the cancellation works, the sum is a vanishing fraction of
        // either half. Comparing against the flow's own size instead would be meaningless wherever the flow
        // happens to be nearly still, which is exactly where a relative measure blows up.
        // Measured against the largest the two halves get anywhere on the grid, rather than against their
        // size at each individual point. At a point where the flow happens to be turning over, both halves
        // are near nothing and what is left is the rounding of the measurement itself — so a per-point
        // comparison there divides a small number by a smaller one and reports a hundred percent error for
        // a field that is behaving perfectly.
        var worstSum = 0.0
        var largestHalves = 0.0
        let step = SwarmFlow.slopeStep

        for gridX in 0 ..< 12 {
            for gridY in 0 ..< 12 {
                let x = Double(gridX) * 0.37 + 0.11
                let y = Double(gridY) * 0.41 + 0.07
                let right = SwarmFlow.curl(atX: x + step, y: y, time: 0.3)
                let left = SwarmFlow.curl(atX: x - step, y: y, time: 0.3)
                let below = SwarmFlow.curl(atX: x, y: y + step, time: 0.3)
                let above = SwarmFlow.curl(atX: x, y: y - step, time: 0.3)
                let acrossTerm = (right.x - left.x) / (2 * step)
                let downTerm = (below.y - above.y) / (2 * step)
                largestHalves = max(largestHalves, abs(acrossTerm) + abs(downTerm))
                worstSum = max(worstSum, abs(acrossTerm + downTerm))
            }
        }
        #expect(largestHalves > 1e-6, "the flow does not vary, so there is nothing to cancel")
        let leftOver = worstSum / largestHalves
        #expect(
            leftOver < 0.02,
            "the two halves failed to cancel by \(leftOver * 100) percent of how large they get"
        )
    }

    @Test("The flow actually varies from place to place")
    func flowIsNotUniform() {
        // A wind that blew the same way everywhere would pass the test above and be a gravity setting.
        var directions: [(Double, Double)] = []
        for step in 0 ..< 40 {
            let x = Double(step) * 0.7
            let flow = SwarmFlow.curl(atX: x, y: x * 0.6, time: 0)
            let size = (flow.x * flow.x + flow.y * flow.y).squareRoot()
            guard size > 1e-9 else { continue }
            directions.append((flow.x / size, flow.y / size))
        }
        #expect(directions.count > 30)
        // Average the directions. A field pointing one way averages to length one; a varied one averages
        // to much less.
        let meanX = directions.map(\.0).reduce(0, +) / Double(directions.count)
        let meanY = directions.map(\.1).reduce(0, +) / Double(directions.count)
        let bias = (meanX * meanX + meanY * meanY).squareRoot()
        #expect(bias < 0.4, "the wind leans one way by \(bias), which is close to uniform")
    }

    @Test("The flow has strong and weak places, not one speed everywhere")
    func flowHasCalmPatches() {
        // The reference implementation throws the strength away and keeps only the direction — twice over
        // — so its wind blows at one speed everywhere and the calm patches that make a flow look like a
        // flow do not exist.
        var speeds: [Double] = []
        for gridX in 0 ..< 24 {
            for gridY in 0 ..< 24 {
                let flow = SwarmFlow.curl(
                    atX: Double(gridX) * 0.23,
                    y: Double(gridY) * 0.19,
                    time: 0
                )
                speeds.append((flow.x * flow.x + flow.y * flow.y).squareRoot())
            }
        }
        let fastest = speeds.max() ?? 0
        let slowest = speeds.min() ?? 0
        #expect(fastest > 0)
        #expect(slowest < fastest * 0.3, "slowest \(slowest) against fastest \(fastest)")
    }

    @Test("The flow is smooth — no sudden changes at grid lines")
    func flowIsSmooth() {
        // The blending curve between grid corners is what buys this. A straight blend leaves a crease at
        // every grid line, and since the flow *is* the slope, those creases show up as a square grid of
        // abrupt changes in direction.
        var worstJump = 0.0
        var previous = SwarmFlow.curl(atX: 0, y: 0.5, time: 0)
        var x = 0.0
        while x < 6 {
            x += 0.01
            let here = SwarmFlow.curl(atX: x, y: 0.5, time: 0)
            let jump = ((here.x - previous.x) * (here.x - previous.x)
                + (here.y - previous.y) * (here.y - previous.y)).squareRoot()
            worstJump = max(worstJump, jump)
            previous = here
        }
        // Whatever the scale, a step of a hundredth should change the flow by far less than the flow's own
        // typical size.
        #expect(worstJump < 0.3, "the flow jumps by \(worstJump) over a hundredth of an eddy")
    }

    @Test("The pattern changes over time")
    func flowDrifts() {
        // A fixed pattern is a set of channels the crowd finds and then follows forever, and after a few
        // seconds nothing changes again.
        let early = SwarmFlow.curl(atX: 1.3, y: 2.7, time: 0)
        let later = SwarmFlow.curl(atX: 1.3, y: 2.7, time: 4)
        let moved = ((early.x - later.x) * (early.x - later.x)
            + (early.y - later.y) * (early.y - later.y)).squareRoot()
        #expect(moved > 0.05, "the pattern moved by only \(moved) over four seconds")
    }

    @Test("The wind pushes the crowd, and keeps it spread out")
    func windMovesTheCrowdWithoutClumping() {
        let field = swarm(grid(20))
        let flow = SwarmFlow()
        var settings = SwarmFlow.Settings.default
        settings.strength = 1.2

        func spread() -> Double {
            // How unevenly the crowd is distributed, as the variation between cell counts of a coarse
            // grid. Clumping makes this climb.
            var cells = [Int](repeating: 0, count: 100)
            for index in 0 ..< field.count {
                let x = Double(field.positions[index * 2])
                let y = Double(field.positions[index * 2 + 1])
                let column = max(0, min(9, Int(x / 40)))
                let row = max(0, min(9, Int(y / 70)))
                cells[row * 10 + column] += 1
            }
            let mean = Double(field.count) / 100
            let variance = cells.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / 100
            return variance.squareRoot() / max(1e-9, mean)
        }

        let before = spread()
        var moved = 0.0
        for tick in 0 ..< 120 {
            flow.step(swarm: field, settings: settings, time: Double(tick) / 60)
            field.step(Swarm.StepOptions(
                width: 400, height: 700, gravityX: 0, gravityY: 0,
                damping: 0.96, elasticity: 0.5, collide: false, maxSpeed: 30,
                boundaryMode: .wrap
            ))
        }
        for index in 0 ..< field.count {
            moved += abs(Double(field.velocities[index * 2]))
        }
        let after = spread()

        #expect(moved > 1, "the wind did not move anything")
        #expect(after < before + 1.2, "the crowd clumped: unevenness went from \(before) to \(after)")
    }

    @Test("No strength means no wind")
    func windRespectsItsStrength() {
        let field = swarm(grid(40))
        let flow = SwarmFlow()
        flow.step(
            swarm: field,
            settings: SwarmFlow.Settings(strength: 0, scale: 140, drift: 0.08),
            time: 1
        )
        for index in 0 ..< field.count {
            #expect(Double(field.velocities[index * 2]) == 0)
        }
    }

    @Test("Nonsense wind settings are pulled into range")
    func windSettingsAreSanitized() {
        let field = swarm(grid(40))
        let flow = SwarmFlow()
        for settings in [
            SwarmFlow.Settings(strength: .nan, scale: .nan, drift: .nan),
            SwarmFlow.Settings(strength: -4, scale: 0, drift: -2),
            SwarmFlow.Settings(strength: 1e9, scale: 1e9, drift: 1e9),
        ] {
            flow.step(swarm: field, settings: settings, time: .nan)
            for index in 0 ..< field.count {
                #expect(Double(field.velocities[index * 2]).isFinite)
            }
        }
    }

    // MARK: - Forces somebody writes

    private func compiled(_ text: String) -> ParticleForceExpression? {
        guard case .success(let expression) = ParticleForceExpression.compile(text) else { return nil }
        return expression
    }

    private func value(
        _ text: String,
        x: Double = 0.5,
        y: Double = 0.5,
        vx: Double = 0,
        vy: Double = 0,
        t: Double = 0
    ) -> Double? {
        guard let expression = compiled(text) else { return nil }
        let fromCentreX = x - 0.5
        let fromCentreY = y - 0.5
        return expression.value(for: ParticleForceExpression.Inputs(
            x: x,
            y: y,
            velocityX: vx,
            velocityY: vy,
            time: t,
            radius: (fromCentreX * fromCentreX + fromCentreY * fromCentreY).squareRoot()
        ))
    }

    @Test("Ordinary arithmetic works, with the right precedence")
    func arithmeticIsCorrect() {
        #expect(value("1 + 2") == 3)
        #expect(value("2 + 3 * 4") == 14, "multiplying binds tighter than adding")
        #expect(value("(2 + 3) * 4") == 20)
        #expect(value("10 - 3 - 2") == 5, "subtracting goes left to right")
        #expect(value("12 / 3 / 2") == 2, "so does dividing")
        #expect(value("-4 + 1") == -3)
        #expect(value("--4") == 4)
        #expect(value("2.5 * 4") == 10)
        #expect(value(".5 * 4") == 2)
    }

    @Test("Everything a body knows about itself can be read")
    func variablesAreReadable() throws {
        #expect(value("x", x: 0.25) == 0.25)
        #expect(value("y", y: 0.75) == 0.75)
        #expect(value("vx", vx: -3.5) == -3.5)
        #expect(value("vy", vy: 7) == 7)
        #expect(value("t", t: 2.5) == 2.5)
        #expect(value("r", x: 0.5, y: 0.5) == 0, "the middle is no distance from the middle")
        let corner = try #require(value("r", x: 1, y: 1))
        #expect(abs(corner - 0.7071067811865476) < 1e-12)
        #expect(abs((value("pi") ?? 0) - 3.141592653589793) < 1e-12)
    }

    @Test("Every function is available and does what it says")
    func functionsWork() {
        #expect(abs((value("sin(0)") ?? 9)) < 1e-12)
        #expect(abs((value("cos(0)") ?? 0) - 1) < 1e-12)
        #expect(value("abs(0 - 4)") == 4)
        #expect(value("sqrt(9)") == 3)
        #expect(value("sign(0 - 2)") == -1)
        #expect(value("sign(0)") == 0)
        #expect(value("floor(2.8)") == 2)
        #expect(value("floor(0 - 2.2)") == -3, "floor goes down, not toward nought")
        #expect(abs((value("frac(2.25)") ?? 0) - 0.25) < 1e-12)
        #expect(value("min(3, 7)") == 3)
        #expect(value("max(3, 7)") == 7)
        #expect(value("hypot(3, 4)") == 5)
        #expect(value("wrap(7, 3)") == 1)
        #expect(value("wrap(0 - 1, 3)") == 2, "wrapping always comes out positive")

        // And every one of them is reachable, so none has been added to the list and left unwired.
        for function in ParticleForceExpression.Function1.allCases {
            #expect(compiled("\(function.rawValue)(1)") != nil, "\(function.rawValue) does not compile")
        }
        for function in ParticleForceExpression.Function2.allCases {
            #expect(compiled("\(function.rawValue)(1, 2)") != nil, "\(function.rawValue) does not compile")
        }
        for variable in ParticleForceExpression.Variable.allCases {
            #expect(compiled(variable.rawValue) != nil, "\(variable.rawValue) does not compile")
        }
    }

    @Test("An empty box means no force, not a mistake")
    func emptyIsNotAMistake() {
        for text in ["", "   ", "\t"] {
            guard case .success(let expression) = ParticleForceExpression.compile(text) else {
                Issue.record("‘\(text)’ was treated as a mistake")
                continue
            }
            #expect(expression.isEmpty)
            #expect(expression.value(for: .init(
                x: 0.2, y: 0.3, velocityX: 1, velocityY: 2, time: 3, radius: 0.4
            )) == 0)
        }
    }

    @Test("A mistake is reported, with something a person can act on")
    func mistakesAreExplained() {
        // The reference implementation turns every mistake into silence: a typo there produces no force
        // and no message, so the only symptom is that nothing happens.
        let mistakes = [
            "1 +", "sin(", "sin()", "sin(1, 2)", "min(1)", "alert(1)", "constructor",
            "1 $ 2", "2 2", "(1 + 2",
        ]
        for text in mistakes {
            switch ParticleForceExpression.compile(text) {
            case .success:
                Issue.record("‘\(text)’ was accepted and should not have been")
            case .failure(let why):
                #expect(!why.message.isEmpty, "‘\(text)’ gave an empty explanation")
            }
        }
    }

    @Test("An expression longer or more tangled than the limits is refused")
    func limitsAreEnforced() {
        let long = String(repeating: "1+", count: 200) + "1"
        switch ParticleForceExpression.compile(long) {
        case .success: Issue.record("an over-long expression was accepted")
        case .failure(let why):
            #expect(why == .tooLong(limit: ParticleForceExpression.characterLimit))
        }
    }

    @Test("Nothing an expression can do produces an unusable number")
    func nothingEscapesAsNotANumber() throws {
        // A body whose velocity is not a number spreads that to every body it touches, so the arithmetic
        // has to be closed: whatever goes in, a usable number comes out.
        let dangerous = [
            "1 / 0", "0 / 0", "sqrt(0 - 4)", "1 / (x - x)", "wrap(1, 0)",
            "1 / sin(0)", "99999 * 99999 * 99999 * 99999 * 99999 * 99999",
        ]
        for text in dangerous {
            let result = try #require(value(text))
            #expect(result.isFinite, "‘\(text)’ gave \(result)")
        }
    }

    @Test("Extreme inputs cannot make an expression produce nonsense")
    func extremeInputsAreSafe() {
        guard let expression = compiled("x * vx / (r + sin(t)) + hypot(vx, vy)") else {
            Issue.record("the expression did not compile")
            return
        }
        for inputs in [
            ParticleForceExpression.Inputs(x: .nan, y: .nan, velocityX: .nan, velocityY: .nan, time: .nan, radius: .nan),
            ParticleForceExpression.Inputs(x: .infinity, y: 0, velocityX: -.infinity, velocityY: 0, time: 0, radius: 0),
            ParticleForceExpression.Inputs(x: 1e300, y: 1e300, velocityX: 1e300, velocityY: 1e300, time: 1e300, radius: 0),
        ] {
            let result = expression.value(for: inputs)
            #expect(result.isFinite, "gave \(result)")
        }
    }

    @Test("A written force actually pushes the crowd, and is bounded")
    func writtenForceMovesTheCrowd() {
        let field = swarm(grid(40))
        let force = SwarmCustomForce()
        guard let across = compiled("sin(y * 8) * 2"), let down = compiled("0 - 0.5") else {
            Issue.record("the expressions did not compile")
            return
        }
        force.step(
            swarm: field,
            acrossward: across,
            downward: down,
            strength: 1,
            width: 400,
            height: 700,
            time: 0
        )

        var moved = 0
        for index in 0 ..< field.count {
            let vx = Double(field.velocities[index * 2])
            let vy = Double(field.velocities[index * 2 + 1])
            #expect(vx.isFinite && vy.isFinite)
            #expect(abs(vy) <= SwarmCustomForce.pushLimit + 1e-6)
            if abs(vx) > 1e-9 { moved += 1 }
        }
        #expect(moved > field.count / 2, "only \(moved) of \(field.count) were pushed sideways")
    }

    @Test("A wild expression is bounded rather than destroying the field")
    func writtenForceIsBounded() {
        // An expression somebody typed can ask for any number at all, and a velocity too large to hold
        // becomes infinity — which later meets the speed limit and turns into not-a-number, at which point
        // the body is gone for good and nothing says why.
        let field = swarm(grid(60))
        let force = SwarmCustomForce()
        guard let wild = compiled("999999 * 999999") else {
            Issue.record("the expression did not compile")
            return
        }
        for _ in 0 ..< 10 {
            force.step(
                swarm: field,
                acrossward: wild,
                downward: wild,
                strength: 1e6,
                width: 400,
                height: 700,
                time: 0
            )
        }
        for index in 0 ..< field.count {
            let speed = abs(Double(field.velocities[index * 2]))
            #expect(speed.isFinite, "body \(index) reached \(speed)")
        }
    }

    @Test("Position is measured as a fraction of the field, not in pixels")
    func writtenForceUsesFractions() {
        // So an expression means the same thing whichever way the phone is held and on any screen. The
        // same expression should push a body at the middle of a tall field exactly as it pushes one at the
        // middle of a wide one.
        guard let across = compiled("x * 10") else {
            Issue.record("the expression did not compile")
            return
        }
        let force = SwarmCustomForce()

        let tall = swarm([(200, 350)])
        force.step(
            swarm: tall, acrossward: across, downward: .blank,
            strength: 1, width: 400, height: 700, time: 0
        )
        let wide = swarm([(350, 200)])
        force.step(
            swarm: wide, acrossward: across, downward: .blank,
            strength: 1, width: 700, height: 400, time: 0
        )
        #expect(abs(Double(tall.velocities[0]) - Double(wide.velocities[0])) < 1e-5)
    }

    @Test("Both switches are joined up to the engine")
    func bothAreWiredToTheEngine() {
        for mode in ["wind", "written"] {
            func build() -> ParticleEngine {
                let engine = ParticleEngine(width: 400, height: 700, seed: 5)
                engine.setMaxParticles(40_000)
                engine.gravityX = 0
                engine.gravityY = 0
                engine.collisionsEnabled = false
                engine.spawnBatch(count: 6_000, color: PackedColor(r: 255, g: 255, b: 255))
                return engine
            }

            let plain = build()
            for _ in 0 ..< 4 { plain.step() }
            let without = (0 ..< 100).map { plain.swarm.positions[$0 * 2] }

            let changed = build()
            if mode == "wind" {
                changed.flowEnabled = true
                changed.flowSettings.strength = 2
            } else {
                guard case .success(let expression) = ParticleForceExpression.compile("sin(y * 10)") else {
                    Issue.record("the expression did not compile")
                    continue
                }
                changed.writtenForceAcross = expression
            }
            for _ in 0 ..< 4 { changed.step() }
            let with = (0 ..< 100).map { changed.swarm.positions[$0 * 2] }

            #expect(without != with, "\(mode) changed nothing")
            for value in with {
                #expect(Double(value).isFinite, "\(mode) produced an unusable position")
            }
        }
    }

    @Test("The engine's own clock advances with its ticks, not with the wall")
    func clockFollowsTheTicks() {
        // So a wind or a written force that reads the time advances in step with the physics. A paused
        // field would otherwise still have a moving force acting on it the moment it was unpaused.
        let engine = ParticleEngine(width: 400, height: 700, seed: 1)
        #expect(engine.elapsedSeconds == 0)
        for _ in 0 ..< 60 { engine.step() }
        #expect(abs(engine.elapsedSeconds - 1) < 1e-9, "sixty ticks should be one second")
    }

    @Test("Wind settings survive being written down and read back")
    func settingsRoundTrip() throws {
        let settings = SwarmFlow.Settings(strength: 1.5, scale: 88, drift: 0.4)
        let bytes = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(SwarmFlow.Settings.self, from: bytes) == settings)
    }
}
