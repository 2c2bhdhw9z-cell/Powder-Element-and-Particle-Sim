import Foundation
import Testing

@testable import CrucibleCore

/// What a finger does, checked directly, on a field the size of a phone's screen.
///
/// These replace eight recorded comparisons of the finger against the web version. They were retired because
/// what they recorded was the fault: the crowd's push was eight hundredths of a pixel a moment, too faint to
/// see, and the individual bodies' fell away so steeply that on a phone it did almost nothing a short way from
/// the finger (see `ParticleGoldenTests.retired`). Every tool now uses Built-Helion's brush on everything —
/// the owner's working reference — and these check that each does what it says, on both kinds of body, on
/// every arrangement, and the same whether or not zooming out has grown the world.
@Suite("The finger")
struct ParticleBrushTests {
    /// A phone's screen, in pixels.
    static let screen = (width: 1_320.0, height: 2_868.0)
    /// How far the finger reaches as a share of the screen's height: Built-Helion's twelve hundredths, which is
    /// what the app starts at.
    static let reachShare = 0.12
    /// The middle of the screen, where the finger goes unless a test says otherwise.
    static let finger = (x: screen.width * 0.5, y: screen.height * 0.5)

    /// The two kinds of body. Every arrangement is made of one or the other or both, so every tool is checked
    /// on each.
    enum Kind: String, CaseIterable, Sendable {
        case bodies
        case crowd
    }

    static let kinds = Kind.allCases

    /// The tools that move bodies.
    static let movingTools: [ParticleMouseMode] = [.attract, .repel, .vortex, .gravityWell, .hawk, .hyperDrive]

    /// Every tool that acts on bodies.
    static let bodyTools: [ParticleMouseMode] = movingTools + [.freeze, .painter]

    /// A field the size of a phone's screen, set up as the app sets it up — or grown, as zooming out grows it.
    private func phone(growth: Double = 1, seed: UInt32 = 7) -> ParticleEngine {
        let engine = ParticleEngine(width: Self.screen.width * growth, height: Self.screen.height * growth, seed: seed)
        engine.setMaxParticles(400_000)
        engine.screenWidth = Self.screen.width
        engine.screenHeight = Self.screen.height
        // The circle stays the same size on the screen, so it covers more of a grown world.
        engine.mouseRadius = Self.reachShare * Self.screen.height * growth
        return engine
    }

    /// An empty field with nothing else acting on it, so whatever moves a body is the finger.
    private func stillPhone(growth: Double = 1) -> ParticleEngine {
        let engine = phone(growth: growth)
        engine.clear()
        engine.gravityX = 0
        engine.gravityY = 0
        engine.collisionsEnabled = false
        return engine
    }

    /// Adds one resting body of a kind.
    private func add(_ kind: Kind, to engine: ParticleEngine, x: Double, y: Double) {
        switch kind {
        case .bodies:
            engine.addParticle(
                x: x, y: y, velocityX: 0, velocityY: 0, radius: 2, charge: 0,
                color: PackedColor(r: 0xFF, g: 0xFF, b: 0xFF)
            )
        case .crowd:
            engine.swarm.append(x: x, y: y, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000_000)
        }
    }

    /// Puts resting bodies in a ring round the middle of the field, a share of the finger's reach out.
    private func ring(_ kind: Kind, in engine: ParticleEngine, at share: Double, count: Int = 36) {
        let distance = share * engine.mouseRadius
        let centre = (x: engine.width * 0.5, y: engine.height * 0.5)
        for k in 0 ..< count {
            let angle = Double(k) / Double(count) * 2 * Double.pi
            add(kind, to: engine, x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
        }
    }

    /// Where each body of a kind is, in the order they were added.
    private func places(_ kind: Kind, in engine: ParticleEngine) -> [(x: Double, y: Double)] {
        switch kind {
        case .bodies:
            return engine.particles.map { (x: $0.x, y: $0.y) }
        case .crowd:
            return (0 ..< engine.swarm.count).map { index in
                (x: Double(engine.swarm.positions[index * 2]), y: Double(engine.swarm.positions[index * 2 + 1]))
            }
        }
    }

    /// How fast each body of a kind is going.
    private func velocities(_ kind: Kind, in engine: ParticleEngine) -> [(x: Double, y: Double)] {
        switch kind {
        case .bodies:
            return engine.particles.map { (x: $0.velocityX, y: $0.velocityY) }
        case .crowd:
            return (0 ..< engine.swarm.count).map { index in
                (x: Double(engine.swarm.velocities[index * 2]), y: Double(engine.swarm.velocities[index * 2 + 1]))
            }
        }
    }

    /// Each body's colour.
    private func colours(_ kind: Kind, in engine: ParticleEngine) -> [UInt32] {
        switch kind {
        case .bodies:
            return engine.particles.map(\.color.packedRGBA)
        case .crowd:
            return (0 ..< engine.swarm.count).map { engine.swarm.colors[$0] }
        }
    }

    private func speed(_ v: (x: Double, y: Double)) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    /// How far, on average, the bodies are from a point.
    private func meanDistance(_ points: [(x: Double, y: Double)], from centre: (x: Double, y: Double)) -> Double {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0.0) { sum, p in sum + hypot(p.x - centre.x, p.y - centre.y) }
        return total / Double(points.count)
    }

    /// How far each body has turned about a point, in radians.
    private func turns(
        from before: [(x: Double, y: Double)],
        to after: [(x: Double, y: Double)],
        about centre: (x: Double, y: Double)
    ) -> [Double] {
        zip(before, after).map { start, end in
            var turn = atan2(end.y - centre.y, end.x - centre.x) - atan2(start.y - centre.y, start.x - centre.x)
            if turn > Double.pi { turn -= 2 * Double.pi }
            if turn < -Double.pi { turn += 2 * Double.pi }
            return turn
        }
    }

    /// Holds a finger down with a tool in the middle of the field.
    private func hold(_ mode: ParticleMouseMode, on engine: ParticleEngine, for moments: Int) {
        engine.mouseMode = mode
        for _ in 0 ..< moments {
            engine.step(mouseX: engine.width * 0.5, mouseY: engine.height * 0.5, mouseActive: true)
        }
    }

    private func middle(of engine: ParticleEngine) -> (x: Double, y: Double) {
        (x: engine.width * 0.5, y: engine.height * 0.5)
    }

    // MARK: - Each tool does what it says, on both kinds of body

    @Test("Pull draws bodies in", arguments: kinds)
    func pullDrawsIn(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        let before = meanDistance(places(kind, in: engine), from: middle(of: engine))
        hold(.attract, on: engine, for: 4)
        let after = meanDistance(places(kind, in: engine), from: middle(of: engine))
        #expect(after < before * 0.8, "\(kind): from \(before) to \(after) in four moments")
    }

    @Test("Push sends bodies away", arguments: kinds)
    func pushSendsAway(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        let before = meanDistance(places(kind, in: engine), from: middle(of: engine))
        hold(.repel, on: engine, for: 4)
        let after = meanDistance(places(kind, in: engine), from: middle(of: engine))
        #expect(after > before * 1.2, "\(kind): from \(before) to \(after) in four moments")
    }

    @Test("Swirl turns bodies round the finger, all the same way", arguments: kinds)
    func swirlTurns(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        let before = places(kind, in: engine)
        hold(.vortex, on: engine, for: 4)
        let after = places(kind, in: engine)
        let turned = turns(from: before, to: after, about: middle(of: engine))
        let mean = turned.reduce(0, +) / Double(turned.count)
        #expect(abs(mean) > 0.25, "\(kind): turned only \(mean) radians in four moments")
        #expect(turned.allSatisfy { ($0 > 0) == (mean > 0) }, "\(kind): some turned the other way")
        // Round, rather than in or out.
        let start = meanDistance(before, from: middle(of: engine))
        let end = meanDistance(after, from: middle(of: engine))
        #expect(end > start * 0.8 && end < start * 1.5, "\(kind): the ring went from \(start) to \(end) across")
    }

    @Test("The well draws bodies in and turns them as they come", arguments: kinds)
    func wellDrawsInAndTurns(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        let before = places(kind, in: engine)
        hold(.gravityWell, on: engine, for: 4)
        let after = places(kind, in: engine)
        let start = meanDistance(before, from: middle(of: engine))
        let end = meanDistance(after, from: middle(of: engine))
        #expect(end < start * 0.85, "\(kind): from \(start) to \(end) in four moments")
        let turned = turns(from: before, to: after, about: middle(of: engine))
        let mean = turned.reduce(0, +) / Double(turned.count)
        #expect(abs(mean) > 0.05, "\(kind): the well did not turn them (\(mean) radians)")
    }

    @Test("Freeze stops bodies dead inside the circle, and only there", arguments: kinds)
    func freezeStops(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        ring(kind, in: engine, at: 1.6)
        // Every one of them moving.
        switch kind {
        case .bodies:
            for index in engine.particles.indices { engine.particles[index].velocityX = 3 }
        case .crowd:
            for index in 0 ..< engine.swarm.count { engine.swarm.velocities[index * 2] = 3 }
        }
        hold(.freeze, on: engine, for: 1)
        let speeds = velocities(kind, in: engine).map(speed)
        #expect(speeds[..<36].allSatisfy { $0 < 0.01 }, "\(kind): a body inside the circle is still moving")
        #expect(speeds[36...].allSatisfy { $0 > 2.5 }, "\(kind): a body outside the circle was stopped")
    }

    @Test("Hyper pulls as hard at the edge of the circle as beside the finger, and turns bodies rose", arguments: kinds)
    func hyperDoesNotFade(kind: Kind) {
        func twoBodies() -> ParticleEngine {
            let engine = stillPhone()
            let centre = middle(of: engine)
            add(kind, to: engine, x: centre.x + engine.mouseRadius * 0.2, y: centre.y)
            add(kind, to: engine, x: centre.x - engine.mouseRadius * 0.9, y: centre.y)
            return engine
        }
        let rushing = twoBodies()
        hold(.hyperDrive, on: rushing, for: 1)
        let rush = velocities(kind, in: rushing).map(speed)
        #expect(rush[0] > 5, "\(kind): hyper barely moved the near body (\(rush[0]))")
        #expect(abs(rush[0] - rush[1]) < rush[0] * 0.05, "\(kind): near \(rush[0]), far \(rush[1])")
        let rose = ParticleBrush.rushColor.packedRGBA
        #expect(colours(kind, in: rushing).allSatisfy { $0 == rose }, "\(kind): hyper did not recolour them")

        // Pull, for contrast, fades to nothing at the edge.
        let pulling = twoBodies()
        hold(.attract, on: pulling, for: 1)
        let pull = velocities(kind, in: pulling).map(speed)
        #expect(pull[1] < pull[0] * 0.3, "\(kind): pull did not fade: near \(pull[0]), far \(pull[1])")
    }

    @Test("The hawk scatters bodies, hardest right beside the finger", arguments: kinds)
    func hawkScatters(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        let before = meanDistance(places(kind, in: engine), from: middle(of: engine))
        hold(.hawk, on: engine, for: 4)
        let after = meanDistance(places(kind, in: engine), from: middle(of: engine))
        #expect(after > before * 1.3, "\(kind): from \(before) to \(after) in four moments")

        // A light touch, so that neither ring is at a limit: the near one is thrown much harder.
        let light = stillPhone()
        light.mouseForceMultiplier = 0.05
        ring(kind, in: light, at: 0.1)
        ring(kind, in: light, at: 0.8)
        hold(.hawk, on: light, for: 1)
        let speeds = velocities(kind, in: light).map(speed)
        let near = speeds[..<36].reduce(0, +) / 36
        let far = speeds[36...].reduce(0, +) / 36
        #expect(far > 0, "\(kind): the far ring was not touched")
        #expect(near > far * 3, "\(kind): near \(near), far \(far)")
    }

    @Test("Paint recolours what it touches, moves nothing, and leaves the rest alone", arguments: kinds)
    func paintRecolours(kind: Kind) {
        let engine = stillPhone()
        ring(kind, in: engine, at: 0.5)
        ring(kind, in: engine, at: 1.6)
        let before = places(kind, in: engine)
        hold(.painter, on: engine, for: 1)
        let painted = colours(kind, in: engine)
        #expect(painted[..<36].allSatisfy { $0 != 0xFFFF_FFFF }, "\(kind): a body inside the circle kept its colour")
        #expect(painted[36...].allSatisfy { $0 == 0xFFFF_FFFF }, "\(kind): a body outside the circle was painted")
        let after = places(kind, in: engine)
        #expect(zip(before, after).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 1e-3 }, "\(kind): paint moved a body")
    }

    // MARK: - How far and how hard

    @Test("Nothing outside the circle is touched", arguments: bodyTools)
    func outsideIsUntouched(mode: ParticleMouseMode) {
        for kind in Kind.allCases {
            let engine = stillPhone()
            ring(kind, in: engine, at: 1.05)
            let before = places(kind, in: engine)
            hold(mode, on: engine, for: 3)
            let after = places(kind, in: engine)
            #expect(
                zip(before, after).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 1e-3 },
                "\(mode) moved a \(kind) body outside its reach"
            )
            #expect(colours(kind, in: engine).allSatisfy { $0 == 0xFFFF_FFFF }, "\(mode) recoloured a \(kind) body outside its reach")
        }
    }

    @Test("The whole field reaches everything, however far away")
    func wholeFieldReachesEverything() {
        for kind in Kind.allCases {
            let engine = stillPhone()
            engine.mouseRadius = .infinity
            add(kind, to: engine, x: 20, y: 20)
            add(kind, to: engine, x: engine.width - 20, y: engine.height - 20)
            let before = meanDistance(places(kind, in: engine), from: middle(of: engine))
            hold(.attract, on: engine, for: 3)
            let after = meanDistance(places(kind, in: engine), from: middle(of: engine))
            #expect(after < before - 5, "\(kind): the corners did not feel the whole-field pull (\(before) to \(after))")
        }
    }

    @Test("Strength scales the push")
    func strengthScales() {
        for kind in Kind.allCases {
            func pushed(by strength: Double) -> Double {
                let engine = stillPhone()
                engine.mouseForceMultiplier = strength
                ring(kind, in: engine, at: 0.5, count: 8)
                hold(.repel, on: engine, for: 1)
                return velocities(kind, in: engine).map(speed).reduce(0, +) / 8
            }
            let single = pushed(by: 1)
            let double = pushed(by: 2)
            #expect(single > 1, "\(kind): barely pushed at full strength (\(single))")
            #expect(abs(double / single - 2) < 0.1, "\(kind): twice the strength pushed \(double / single) times as hard")
        }
    }

    @Test("A finger's forces are measured against the screen, not against a world grown by zooming out")
    func forcesAreMeasuredAgainstTheScreen() {
        #expect(phone(growth: 2).brushUnit == Self.screen.height)
        #expect(ParticleEngine(width: 400, height: 700, seed: 1).brushUnit == 700)

        // The same share of the circle out, zoomed out or not: the same push in the world, so zooming out does
        // not make the finger stronger.
        for kind in Kind.allCases {
            var pushes: [Double] = []
            for growth in [1.0, 2.0] {
                let engine = stillPhone(growth: growth)
                ring(kind, in: engine, at: 0.5, count: 8)
                hold(.repel, on: engine, for: 1)
                pushes.append(velocities(kind, in: engine).map(speed).reduce(0, +) / 8)
            }
            #expect(abs(pushes[0] - pushes[1]) < pushes[0] * 0.01, "\(kind): \(pushes[0]) on the screen, \(pushes[1]) zoomed out")
        }
    }

    // MARK: - Every arrangement

    static let sceneIDs = ParticleArrangement.scenes.map(\.id).filter { $0 != "text" }

    /// Where to put a finger on an arrangement: where its own bodies are thickest, away from any black hole.
    private func target(on engine: ParticleEngine) -> (x: Double, y: Double) {
        var points: [(x: Double, y: Double)] = []
        for body in engine.particles where body.kind == .standard && !body.isFixed && body.isFinite {
            points.append((x: body.x, y: body.y))
        }
        for index in 0 ..< engine.swarm.count {
            points.append((x: Double(engine.swarm.positions[index * 2]), y: Double(engine.swarm.positions[index * 2 + 1])))
        }
        let wells = engine.particles.filter { $0.kind == .blackhole || $0.kind == .repulsor }
        let reach = engine.mouseRadius
        var best = points.first ?? middle(of: engine)
        var bestCount = -1
        let candidateStep = max(1, points.count / 97)
        let sampleStep = max(1, points.count / 4_000)
        var index = 0
        while index < points.count {
            let candidate = points[index]
            index += candidateStep
            if wells.contains(where: { hypot($0.x - candidate.x, $0.y - candidate.y) < reach }) { continue }
            var count = 0
            var k = 0
            while k < points.count {
                if hypot(points[k].x - candidate.x, points[k].y - candidate.y) < reach * 0.6 { count += 1 }
                k += sampleStep
            }
            if count > bestCount {
                bestCount = count
                best = candidate
            }
        }
        return best
    }

    /// One body the finger can reach: which kind, where in its list, and where it was.
    private struct Reached {
        var kind: Kind
        var index: Int
        var x: Double
        var y: Double
    }

    private func reached(near finger: (x: Double, y: Double), in engine: ParticleEngine) -> [Reached] {
        var found: [Reached] = []
        let near = engine.mouseRadius * 0.6
        for (index, body) in engine.particles.enumerated()
        where body.kind == .standard && !body.isFixed && hypot(body.x - finger.x, body.y - finger.y) < near {
            found.append(Reached(kind: .bodies, index: index, x: body.x, y: body.y))
        }
        for index in 0 ..< engine.swarm.count {
            let x = Double(engine.swarm.positions[index * 2])
            let y = Double(engine.swarm.positions[index * 2 + 1])
            if hypot(x - finger.x, y - finger.y) < near {
                found.append(Reached(kind: .crowd, index: index, x: x, y: y))
            }
        }
        return found
    }

    private func velocity(of body: Reached, in engine: ParticleEngine) -> (x: Double, y: Double) {
        switch body.kind {
        case .bodies:
            return (x: engine.particles[body.index].velocityX, y: engine.particles[body.index].velocityY)
        case .crowd:
            return (
                x: Double(engine.swarm.velocities[body.index * 2]),
                y: Double(engine.swarm.velocities[body.index * 2 + 1])
            )
        }
    }

    private func colour(of body: Reached, in engine: ParticleEngine) -> UInt32 {
        switch body.kind {
        case .bodies: return engine.particles[body.index].color.packedRGBA
        case .crowd: return engine.swarm.colors[body.index]
        }
    }

    private func place(of body: Reached, in engine: ParticleEngine) -> (x: Double, y: Double) {
        switch body.kind {
        case .bodies:
            return (x: engine.particles[body.index].x, y: engine.particles[body.index].y)
        case .crowd:
            return (
                x: Double(engine.swarm.positions[body.index * 2]),
                y: Double(engine.swarm.positions[body.index * 2 + 1])
            )
        }
    }

    /// An arrangement a second in, so that the ones that pour or burst have something there — and on, for a
    /// storm, until the next bolt has struck.
    private func warmedUp(_ id: String) -> ParticleEngine {
        let engine = phone()
        #expect(engine.loadArrangement(id), "\(id) is not known to the engine")
        for _ in 0 ..< 60 { engine.step() }
        var waited = 0
        while engine.bodyCount < 200, waited < 300 {
            engine.step()
            waited += 1
        }
        return engine
    }

    /// The owner's complaint was that none of the tools worked. Every arrangement, every tool: the same field
    /// is stepped once without a finger and once with one, and what the finger added is checked for going the
    /// way the tool says.
    @Test("Every tool acts on every arrangement", arguments: sceneIDs)
    func everyArrangementFeelsEveryTool(id: String) throws {
        let warmed = warmedUp(id)
        let state = warmed.captureState()
        let finger = target(on: warmed)

        for mode in Self.movingTools + [.painter] {
            let control = phone()
            let touched = phone()
            #expect(control.apply(state) && touched.apply(state))
            let bodies = reached(near: finger, in: touched)
            try #require(bodies.count >= 3, "\(id): only \(bodies.count) bodies under the finger")

            control.mouseMode = mode
            touched.mouseMode = mode
            control.step()
            touched.step(mouseX: finger.x, mouseY: finger.y, mouseActive: true)
            try #require(
                control.particles.count == touched.particles.count && control.swarm.count == touched.swarm.count,
                "\(id): the finger changed how many bodies there are"
            )

            var inward = 0.0
            var around = 0.0
            var recoloured = 0
            for body in bodies {
                let without = velocity(of: body, in: control)
                let with = velocity(of: body, in: touched)
                let dx = finger.x - body.x
                let dy = finger.y - body.y
                let distance = max(1e-6, hypot(dx, dy))
                let changeX = with.x - without.x
                let changeY = with.y - without.y
                inward += (changeX * dx + changeY * dy) / distance
                around += (changeY * dx - changeX * dy) / distance
                if colour(of: body, in: touched) != colour(of: body, in: control) { recoloured += 1 }
            }
            let count = Double(bodies.count)
            inward /= count
            around /= count

            switch mode {
            case .attract, .gravityWell, .hyperDrive:
                #expect(inward > 1, "\(id): \(mode) drew bodies in by only \(inward) a moment")
            case .repel, .hawk:
                #expect(inward < -1, "\(id): \(mode) sent bodies out by only \(-inward) a moment")
            case .vortex:
                #expect(abs(around) > 1, "\(id): swirl turned bodies by only \(around) a moment")
                #expect(abs(around) > abs(inward) * 2, "\(id): swirl pushed in or out (\(inward)) more than round (\(around))")
            case .painter:
                #expect(Double(recoloured) >= count * 0.8, "\(id): paint recoloured \(recoloured) of \(bodies.count)")
            default:
                break
            }
        }
    }

    /// Whether what a tool adds in a moment is undone by the arrangement before anybody could see it — by
    /// the springs of a cloth, the pressure of a liquid, a flock's steering or a shape's hold. Held down for a
    /// third of a second, a pull has to have moved the bodies under it a distance anybody can see, and freeze
    /// has to have stilled them.
    @Test("Held down on any arrangement, pull visibly draws bodies in and freeze stills them", arguments: sceneIDs)
    func holdingAToolOnEveryArrangement(id: String) throws {
        let warmed = warmedUp(id)
        let state = warmed.captureState()
        let finger = target(on: warmed)

        let control = phone()
        let pulled = phone()
        let frozen = phone()
        #expect(control.apply(state) && pulled.apply(state) && frozen.apply(state))
        let bodies = reached(near: finger, in: pulled)
        try #require(bodies.count >= 3, "\(id): only \(bodies.count) bodies under the finger")
        pulled.mouseMode = .attract
        frozen.mouseMode = .freeze
        var frozenBefore: [Reached] = []
        var controlBefore: [Reached] = []
        for moment in 0 ..< 20 {
            // For the last moment, where everything under the finger is, to see how far it then moves.
            if moment == 19 {
                frozenBefore = reached(near: finger, in: frozen)
                controlBefore = reached(near: finger, in: control)
            }
            control.step()
            pulled.step(mouseX: finger.x, mouseY: finger.y, mouseActive: true)
            frozen.step(mouseX: finger.x, mouseY: finger.y, mouseActive: true)
        }
        try #require(
            control.particles.count == pulled.particles.count && control.swarm.count == pulled.swarm.count,
            "\(id): the finger changed how many bodies there are"
        )

        var closer = 0.0
        for body in bodies {
            let without = place(of: body, in: control)
            let with = place(of: body, in: pulled)
            closer += hypot(without.x - finger.x, without.y - finger.y) - hypot(with.x - finger.x, with.y - finger.y)
        }
        closer /= Double(bodies.count)
        #expect(closer > 20, "\(id): a third of a second of pulling brought bodies only \(closer) closer")

        // How far the bodies under the finger moved in that last moment. Movement rather than speed, because a
        // spring's pull is recorded on a frozen body after it has been held still, and is not movement.
        func moved(_ before: [Reached], in engine: ParticleEngine) -> Double {
            var total = 0.0
            var count = 0
            for body in before {
                switch body.kind {
                case .bodies where body.index >= engine.particles.count: continue
                case .crowd where body.index >= engine.swarm.count: continue
                default: break
                }
                let now = place(of: body, in: engine)
                let distance = hypot(now.x - body.x, now.y - body.y)
                // Further than anything can move in a moment is not movement: it is a body whose time ran out
                // being launched again, or one that went and left its place in the list to another.
                if distance > engine.maxSpeed + 1 { continue }
                total += distance
                count += 1
            }
            return count > 0 ? total / Double(count) : 0
        }
        let still = moved(frozenBefore, in: frozen)
        let moving = moved(controlBefore, in: control)
        #expect(still <= max(0.05, moving * 0.2), "\(id): frozen bodies still move \(still) a moment, \(moving) untouched")
    }

    // MARK: - Shapes

    @Test("A held shape can be pulled out of place, and mends once the finger lifts")
    func heldShapesGiveAndMend() {
        let engine = phone()
        engine.loadArrangement("sunflower")
        let finger = (x: engine.width * 0.5 + engine.patternSpan * 0.15, y: engine.height * 0.5)
        // The seeds that belong within the finger's circle.
        let under = (0 ..< engine.swarm.count).filter { index in
            guard let home = engine.swarm.home(at: index) else { return false }
            return hypot(home.point.x - finger.x, home.point.y - finger.y) < engine.mouseRadius * 0.8
        }
        #expect(under.count > 100, "only \(under.count) seeds under the finger")
        func outOfPlace() -> Double {
            var total = 0.0
            for index in under {
                guard let home = engine.swarm.home(at: index) else { continue }
                let place = home.point
                total += hypot(
                    Double(engine.swarm.positions[index * 2]) - place.x,
                    Double(engine.swarm.positions[index * 2 + 1]) - place.y
                )
            }
            return total / Double(max(1, under.count))
        }
        engine.mouseMode = .attract
        for _ in 0 ..< 30 { engine.step(mouseX: finger.x, mouseY: finger.y, mouseActive: true) }
        let pulled = outOfPlace()
        #expect(pulled > 40, "half a second of pulling moved the seeds only \(pulled) out of place")
        for _ in 0 ..< 600 { engine.step() }
        let mended = outOfPlace()
        #expect(mended < pulled * 0.3, "pulled \(pulled) out of place, still \(mended) ten seconds later")
    }

    // MARK: - Walls and wind

    @Test("A wall stops individual bodies as it stops the crowd")
    func wallsStopBodies() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.clear()
        engine.gravityY = 0.4
        engine.addWall(fromFractionX: 0.05, y: 0.5, toFractionX: 0.95, y: 0.5)
        for k in 0 ..< 20 {
            engine.addParticle(x: 40 + Double(k) * 16, y: 200, velocityX: 0, velocityY: 0, radius: 3, charge: 0)
        }
        for _ in 0 ..< 400 { engine.step() }
        let through = engine.particles.filter { $0.y > 350 }.count
        #expect(through == 0, "\(through) of 20 fell through the wall")
        #expect(engine.particles.allSatisfy { $0.y > 300 }, "they did not fall as far as the wall")
    }

    @Test("Painted wind blows individual bodies along, as it does the crowd")
    func windBlowsBodies() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.clear()
        engine.gravityY = 0
        for x in stride(from: 60.0, through: 340, by: 20) {
            engine.paintCurrent(atX: x, y: 350, directionX: 1, directionY: 0)
        }
        engine.addParticle(x: 120, y: 350, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        for _ in 0 ..< 20 { engine.step() }
        #expect(engine.particles[0].x > 135, "the wind moved it only to \(engine.particles[0].x)")
        #expect(abs(engine.particles[0].y - 350) < 10, "the wind blew it sideways to \(engine.particles[0].y)")
    }

    // MARK: - Zoomed out

    /// How far out an arrangement reaches from the middle of the world, ignoring the furthest tenth.
    private func extent(of engine: ParticleEngine) -> Double {
        var distances: [Double] = []
        let centre = middle(of: engine)
        for body in engine.particles where body.kind == .standard {
            distances.append(hypot(body.x - centre.x, body.y - centre.y))
        }
        for index in 0 ..< engine.swarm.count {
            distances.append(hypot(
                Double(engine.swarm.positions[index * 2]) - centre.x,
                Double(engine.swarm.positions[index * 2 + 1]) - centre.y
            ))
        }
        distances.sort()
        return distances.isEmpty ? 0 : distances[distances.count * 9 / 10]
    }

    @Test(
        "An arrangement chosen after zooming out is its usual size, in the middle, with room round it",
        arguments: ["galaxy", "blackhole", "sunflower", "mandala", "sierpinski", "ring", "swarm", "nbody", "supernova"]
    )
    func arrangementsKeepTheirSizeWhenZoomedOut(id: String) {
        let screen = phone()
        let grown = phone(growth: 2)
        screen.loadArrangement(id)
        grown.loadArrangement(id)
        let usual = extent(of: screen)
        let zoomedOut = extent(of: grown)
        #expect(usual > 0)
        #expect(abs(zoomedOut - usual) < usual * 0.03, "\(id): \(usual) across on the screen, \(zoomedOut) zoomed out")
        #expect(zoomedOut < grown.height * 0.3, "\(id) filled the grown world")
        #expect(grown.bodyCount == screen.bodyCount, "\(id): \(screen.bodyCount) bodies on the screen, \(grown.bodyCount) zoomed out")
    }

    @Test("What stands on the floor stands on the grown world's floor, at its usual width", arguments: ["water", "fire", "magma"])
    func floorArrangementsStandOnTheFloor(id: String) {
        func footprint(_ engine: ParticleEngine) -> (width: Double, lowest: Double) {
            var xs: [Double] = []
            var lowest = 0.0
            for index in 0 ..< engine.swarm.count {
                xs.append(Double(engine.swarm.positions[index * 2]))
                lowest = max(lowest, Double(engine.swarm.positions[index * 2 + 1]))
            }
            xs.sort()
            guard xs.count > 20 else { return (0, lowest) }
            return (xs[xs.count * 95 / 100] - xs[xs.count * 5 / 100], lowest)
        }
        let screen = phone()
        let grown = phone(growth: 2)
        screen.loadArrangement(id)
        grown.loadArrangement(id)
        let usual = footprint(screen)
        let zoomedOut = footprint(grown)
        #expect(usual.width > 0)
        #expect(abs(zoomedOut.width - usual.width) < usual.width * 0.05, "\(id): \(usual.width) wide on the screen, \(zoomedOut.width) zoomed out")
        #expect(zoomedOut.lowest > grown.height * 0.9, "\(id) is floating at \(zoomedOut.lowest) in a world \(grown.height) high")
    }

    @Test("Undo after zooming out brings the field back in the middle of the grown world")
    func undoFollowsTheGrownWorld() throws {
        let engine = phone()
        engine.loadArrangement("sunflower")
        engine.addWall(fromFractionX: 0.1, y: 0.8, toFractionX: 0.9, y: 0.8)
        // The point undo will come back to: the sunflower and its wall, before a crowd was added.
        engine.spawnBatch(count: 5_000)
        let before = engine.width
        engine.resizeKeepingContentsCentred(width: engine.width * 2, height: engine.height * 2)
        #expect(engine.width == before * 2)
        let wall = try #require(engine.walls.first)
        #expect(engine.undo())

        #expect(engine.swarm.count < 5_000, "undo did not take the added crowd away")
        var sumX = 0.0
        var sumY = 0.0
        for index in 0 ..< engine.swarm.count {
            sumX += Double(engine.swarm.positions[index * 2])
            sumY += Double(engine.swarm.positions[index * 2 + 1])
        }
        let count = Double(max(1, engine.swarm.count))
        #expect(abs(sumX / count - engine.width * 0.5) < engine.width * 0.02, "the sunflower came back off to one side")
        #expect(abs(sumY / count - engine.height * 0.5) < engine.height * 0.02, "the sunflower came back too high")
        // The places its seeds belong came back with them, or the flower would pull itself back to the corner.
        let home = try #require(engine.swarm.home(at: 0))
        #expect(abs(home.anchorX - engine.width * 0.5) < engine.width * 0.02)
        #expect(abs(home.anchorY - engine.height * 0.5) < engine.height * 0.02)
        // And the wall is where it was drawn, under the flower, rather than stretched across the grown world.
        #expect(engine.walls.first == wall, "the wall moved when undo brought it back")
    }

    @Test("Bodies added after zooming out are scattered as they would be on the screen")
    func addingAfterZoomingOut() {
        let screen = phone()
        let grown = phone(growth: 2)
        screen.clear()
        grown.clear()
        screen.spawnBatch(count: 20_000)
        grown.spawnBatch(count: 20_000)
        let usual = extent(of: screen)
        let zoomedOut = extent(of: grown)
        #expect(abs(zoomedOut - usual) < usual * 0.03, "\(usual) across on the screen, \(zoomedOut) zoomed out")
    }

    // MARK: - Sizes

    @Test("Bodies joining a galaxy are the size of its stars, unless matching is turned off")
    func joiningMatchesTheArrangementsSize() {
        let matched = phone()
        matched.loadArrangement("galaxy")
        #expect(matched.matchesArrangementSize, "matching should be on unless somebody turns it off")
        matched.spawnJoining(count: 5_000)
        #expect(matched.swarm.count == 5_000)
        #expect(matched.swarm.hasSizes)
        // The galaxy's stars have radii from one to three, so diameters from two to six.
        let sizes = (0 ..< matched.swarm.count).map { Double(matched.swarm.sizes[$0]) }
        #expect(sizes.allSatisfy { $0 >= 2 && $0 <= 6 }, "a joined star is not the size of the galaxy's")
        let mean = sizes.reduce(0, +) / Double(sizes.count)
        #expect(abs(mean - matched.arrangementBodySize) < 0.5, "joined \(mean) across, the galaxy's are \(matched.arrangementBodySize)")

        let plain = phone()
        plain.loadArrangement("galaxy")
        plain.matchesArrangementSize = false
        plain.spawnJoining(count: 5_000)
        #expect((0 ..< plain.swarm.count).allSatisfy { plain.swarm.sizes[$0] == 0 }, "with matching off they should be the slider's size")
    }

    @Test("Bodies joining an arrangement made of individual bodies copy their size, or take the slider's")
    func joiningObjectsCopiesTheirSize() {
        let matched = phone()
        matched.loadArrangement("flare")
        let before = matched.particles.count
        let radii = Set(matched.particles.filter { $0.kind == .standard && !$0.isFixed }.map(\.radius))
        matched.spawnJoining(count: 200)
        let joined = matched.particles[before...]
        #expect(joined.count == 200)
        #expect(joined.allSatisfy { radii.contains($0.radius) }, "a joined body is a size the flare's bodies are not")

        let plain = phone()
        plain.loadArrangement("flare")
        plain.matchesArrangementSize = false
        let start = plain.particles.count
        plain.spawnJoining(count: 200)
        #expect(plain.particles[start...].allSatisfy { $0.radius == 1 }, "with matching off they should be the slider's size")
    }

    @Test("Bodies joining a crowd copy the size of the body they copy")
    func joiningACrowdCopiesSizes() {
        let engine = phone()
        engine.loadArrangement("sunflower")
        for index in 0 ..< engine.swarm.count { engine.swarm.setSize(5, at: index) }
        let before = engine.swarm.count
        engine.spawnJoining(count: 1_000)
        #expect(engine.swarm.count == before + 1_000)
        #expect((before ..< engine.swarm.count).allSatisfy { engine.swarm.sizes[$0] == 5 })
    }

    @Test("An arrangement's size is the average of its own bodies'")
    func arrangementsHaveASize() {
        let galaxy = phone()
        galaxy.loadArrangement("galaxy")
        #expect(abs(galaxy.arrangementBodySize - 4) < 0.4, "the galaxy's stars average \(galaxy.arrangementBodySize) across")
        let sunflower = phone()
        sunflower.loadArrangement("sunflower")
        #expect(sunflower.arrangementBodySize == 0, "a crowd with no sizes of its own is the slider's size")
    }

    @Test("With nothing arranged, added bodies are the slider's size whatever is lying about")
    func nothingToMatchAfterClearing() {
        let engine = phone()
        engine.clear()
        // A burst's big charged bodies are not an arrangement anybody chose to match.
        engine.loadArrangement("burst")
        #expect(engine.arrangement == nil)
        #expect(engine.arrangementBodySize == 0)
        engine.spawnJoining(count: 5_000)
        #expect((0 ..< engine.swarm.count).allSatisfy { engine.swarm.sizes[$0] == 0 })
    }

    @Test("A crowd added at a size keeps it, through saving and through undo")
    func sizesAreKept() throws {
        let engine = phone()
        engine.clear()
        engine.spawnBatch(count: 5_000, size: 4)
        #expect(engine.swarm.hasSizes)
        #expect((0 ..< engine.swarm.count).allSatisfy { engine.swarm.sizes[$0] == 4 })

        let bytes = try JSONEncoder().encode(engine.captureState())
        let loaded = phone(seed: 2)
        #expect(loaded.apply(try JSONDecoder().decode(ParticleState.self, from: bytes)))
        #expect(loaded.swarm.count == 5_000)
        #expect((0 ..< loaded.swarm.count).allSatisfy { loaded.swarm.sizes[$0] == 4 }, "saving lost the sizes")

        engine.spawnBatch(count: 5_000)
        #expect(engine.swarm.count == 10_000)
        #expect(engine.swarm.sizes[9_999] == 0)
        #expect(engine.undo())
        #expect(engine.swarm.count == 5_000)
        #expect((0 ..< engine.swarm.count).allSatisfy { engine.swarm.sizes[$0] == 4 }, "undo lost the sizes")
    }

    @Test("A few bodies added at a size are that size too")
    func smallBatchesTakeTheSize() {
        let engine = phone()
        engine.clear()
        engine.spawnBatch(count: 100, size: 6)
        #expect(engine.particles.count == 100)
        #expect(engine.particles.allSatisfy { $0.radius == 3 })
    }

    @Test("When a body goes, its size goes with it rather than passing to another")
    func sizesFollowTheirBodies() {
        let engine = stillPhone()
        for k in 0 ..< 200 {
            let fades = k % 2 == 0
            engine.swarm.append(
                x: 100 + Double(k) * 4,
                y: 500,
                velocityX: 0,
                velocityY: 0,
                color: fades ? 0xFF00_00FF : 0xFFFF_0000,
                budget: 1_000_000,
                life: fades ? 3 : -1,
                size: fades ? 9 : 3
            )
        }
        for _ in 0 ..< 10 { engine.step() }
        #expect(engine.swarm.count == 100)
        #expect((0 ..< engine.swarm.count).allSatisfy { engine.swarm.sizes[$0] == 3 && engine.swarm.colors[$0] == 0xFFFF_0000 })
    }
}
